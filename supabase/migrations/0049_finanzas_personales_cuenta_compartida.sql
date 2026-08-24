-- ════════════════════════════════════════════════════════════════
-- 0049 — Finanzas personales, Fase 2: Cuenta Compartida + importación
-- histórica con preview obligatorio.
--
-- Crea SOLO lo que esta fase necesita: finance_accounts, finance_categories,
-- finance_transactions, finance_imports, finance_import_rows. El resto del
-- esquema (finance_internal_transfers, finance_monthly_savings,
-- finance_budgets) se diseña recién en sus propias fases (3, 4, 5) — no se
-- congela nada por adelantado.
--
-- SEGURIDAD — el feature flag es autorización real, no solo ocultamiento de
-- menú: toda policy y la función de importación exigen
-- `user_id = auth.uid() AND has_personal_finance_beta()`. Sin esto, cualquier
-- otro usuario autenticado de Software EYO podría usar estas tablas para SÍ
-- MISMO llamando directo a la REST API, aunque nunca vea el nav-item.
--
-- INTEGRIDAD — toda la cadena financiera usa FK compuestas (id,user_id,
-- tenant_id) en vez de FK simples por id: una fila nunca puede referenciar
-- una cuenta/categoría/import/transacción de OTRO usuario, ni siquiera
-- conociendo su UUID. RLS protege el acceso; las FK compuestas protegen la
-- integridad estructural incluso si alguna ruta de escritura tuviera un bug.
--
-- CONCURRENCIA — import_finance_transactions() bloquea la fila de la cuenta
-- (`for update`) antes de calcular el dedupe multiset, así que dos
-- importaciones simultáneas de la MISMA cuenta se serializan (la segunda
-- espera a que la primera confirme) y nunca ven el mismo estado "antes" al
-- mismo tiempo. Cuentas distintas (o usuarios distintos) sí pueden importar
-- en paralelo sin pisarse.
-- ════════════════════════════════════════════════════════════════

-- ── Helper: feature flag como función reutilizable ──
-- Mismo espíritu que current_tenant_id()/is_admin() (0002/0020), con el
-- endurecimiento de la migración más reciente (0043): search_path vacío +
-- todo objeto con esquema explícito.
create or replace function public.has_personal_finance_beta()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select personal_finance_beta from public.profiles where id = auth.uid()), false)
$$;

comment on function public.has_personal_finance_beta() is 'Feature flag de Finanzas personales como autorización real (no solo UI). Usado en todas las policies de finance_* y en import_finance_transactions().';

revoke all on function public.has_personal_finance_beta() from public;
grant execute on function public.has_personal_finance_beta() to authenticated;

-- ── Cuentas (Cuenta Compartida / Cuenta Personal) ──
create table public.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  user_id uuid not null references auth.users(id),
  kind text not null check (kind in ('shared','personal')),
  name text not null,
  currency text not null default 'UYU',
  opening_balance numeric not null default 0,
  opening_balance_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id, tenant_id)
);

comment on column public.finance_accounts.opening_balance is 'Saldo previo al primer movimiento cargado. 0 por defecto cuando no hay saldo de referencia real (ver Cuenta Compartida en la Fase 2) -- la UI nunca debe mostrar el cálculo resultante como "saldo actual" si este valor es provisional.';

-- ── Categorías/subcategorías administrables (nunca se borran, se archivan) ──
create table public.finance_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  user_id uuid not null references auth.users(id),
  parent_id uuid,
  name text not null,
  color text,
  icon text,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (id, user_id, tenant_id),
  foreign key (parent_id, user_id, tenant_id) references public.finance_categories (id, user_id, tenant_id)
  -- sin ON DELETE: nunca se borra una categoría, solo se archiva. parent_id NULL = categoría raíz.
);

-- Unicidad case-insensitive por usuario. parent_id puede ser NULL (raíz);
-- un índice único normal no haría chocar dos NULL entre sí, así que hacen
-- falta dos índices parciales.
create unique index finance_categories_unique_root
  on public.finance_categories (user_id, lower(trim(name)))
  where parent_id is null;
create unique index finance_categories_unique_child
  on public.finance_categories (user_id, parent_id, lower(trim(name)))
  where parent_id is not null;

-- ── Movimientos — la tabla central ──
create table public.finance_transactions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  user_id uuid not null references auth.users(id),
  account_id uuid not null,
  date date not null,
  description_original text not null,
  amount numeric not null check (amount >= 0),  -- SIEMPRE positivo (abs()); la dirección va aparte
  currency text not null default 'UYU',
  direction text not null check (direction in ('entrada','salida')),
  nature text not null check (nature in (
    'ingreso','gasto','transferencia_interna','transferencia_externa',
    'pago_tc','retiro','deposito','devolucion','ajuste','pendiente_clasificar'
  )),
  category_id uuid,
  payment_method text check (payment_method in ('efectivo','debito','credito','transferencia','deposito','otro')),
  origin text not null default 'manual' check (origin in ('manual','import')),
  observaciones text,
  import_batch_id uuid,
  dedupe_fingerprint text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id, tenant_id),
  foreign key (account_id, user_id, tenant_id) references public.finance_accounts (id, user_id, tenant_id),
  foreign key (category_id, user_id, tenant_id) references public.finance_categories (id, user_id, tenant_id)
);

comment on column public.finance_transactions.amount is 'SIEMPRE positivo. Para reconstruir el monto con signo: CASE WHEN direction=''salida'' THEN -amount ELSE amount END.';
comment on column public.finance_transactions.dedupe_fingerprint is 'Clave compuesta fecha|monto_con_signo|descripcion.trim().toLowerCase() -- NO es un hash criptográfico. Puede repetirse a propósito (movimientos legítimamente idénticos); el dedupe usa conteo de ocurrencias (multiset), no unicidad estricta.';

-- ── Importaciones (preview obligatorio antes de escribir nada) ──
create table public.finance_imports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  user_id uuid not null references auth.users(id),
  account_id uuid not null,
  source_filename text,
  file_type text check (file_type in ('json','csv','xlsx')),
  status text not null default 'pending' check (status in ('pending','processed','failed')),
  total_rows int,
  new_rows int,
  duplicate_rows int,
  possible_transfers int,
  created_at timestamptz not null default now(),
  foreign key (account_id, user_id, tenant_id) references public.finance_accounts (id, user_id, tenant_id),
  unique (id, user_id, tenant_id)
);

create table public.finance_import_rows (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null,
  tenant_id uuid not null references public.tenants(id),
  user_id uuid not null references auth.users(id),
  raw_row jsonb not null,
  dedupe_fingerprint text,
  is_duplicate boolean not null default false,
  matched_transaction_id uuid,
  created_at timestamptz not null default now(),
  foreign key (import_id, user_id, tenant_id) references public.finance_imports (id, user_id, tenant_id) on delete cascade,
  foreign key (matched_transaction_id, user_id, tenant_id) references public.finance_transactions (id, user_id, tenant_id)
);

alter table public.finance_transactions
  add constraint finance_transactions_import_fk
  foreign key (import_batch_id, user_id, tenant_id) references public.finance_imports (id, user_id, tenant_id);

-- ── Índices ──
create index on public.finance_transactions (user_id, date);
create index on public.finance_transactions (account_id);
create index on public.finance_transactions (category_id);
create index on public.finance_transactions (nature);
create index on public.finance_transactions (account_id, dedupe_fingerprint);

-- ── RLS: dueño + feature flag en las 5 tablas ──
alter table public.finance_accounts enable row level security;
alter table public.finance_categories enable row level security;
alter table public.finance_transactions enable row level security;
alter table public.finance_imports enable row level security;
alter table public.finance_import_rows enable row level security;

create policy "finance_accounts_own" on public.finance_accounts for all
  using (user_id = auth.uid() and public.has_personal_finance_beta())
  with check (user_id = auth.uid() and public.has_personal_finance_beta() and tenant_id = public.current_tenant_id());

create policy "finance_categories_own" on public.finance_categories for all
  using (user_id = auth.uid() and public.has_personal_finance_beta())
  with check (user_id = auth.uid() and public.has_personal_finance_beta() and tenant_id = public.current_tenant_id());

create policy "finance_transactions_own" on public.finance_transactions for all
  using (user_id = auth.uid() and public.has_personal_finance_beta())
  with check (user_id = auth.uid() and public.has_personal_finance_beta() and tenant_id = public.current_tenant_id());

create policy "finance_imports_own" on public.finance_imports for all
  using (user_id = auth.uid() and public.has_personal_finance_beta())
  with check (user_id = auth.uid() and public.has_personal_finance_beta() and tenant_id = public.current_tenant_id());

create policy "finance_import_rows_own" on public.finance_import_rows for all
  using (user_id = auth.uid() and public.has_personal_finance_beta())
  with check (user_id = auth.uid() and public.has_personal_finance_beta() and tenant_id = public.current_tenant_id());

-- ── Seed: 14 categorías padre (punto 11 del pedido) + Cuenta Compartida, ──
-- ── solo para el founder. Sin subcategorías -- el import las crea de los ──
-- ── datos reales. No falla si el perfil todavía no existe (mismo criterio ──
-- ── que el seed de is_founder, 0023). ──
do $$
declare
  v_user_id uuid;
  v_tenant_id uuid;
  v_account_id uuid;
  v_cat text;
begin
  select id, tenant_id into v_user_id, v_tenant_id
  from public.profiles where email = 'orielesymama@gmail.com' limit 1;

  if v_user_id is null then
    return;
  end if;

  insert into public.finance_accounts (tenant_id, user_id, kind, name, currency)
  values (v_tenant_id, v_user_id, 'shared', 'Cuenta Compartida', 'UYU')
  returning id into v_account_id;

  foreach v_cat in array array[
    'Servicios','Obligaciones','Alimentación','Transporte','Hogar/propiedades',
    'Salud','Ocio','Compras','Software','TC','Retiros','Transferencias','Ingresos','Otros'
  ] loop
    insert into public.finance_categories (tenant_id, user_id, parent_id, name)
    values (v_tenant_id, v_user_id, null, v_cat)
    on conflict (user_id, (lower(trim(name)))) where parent_id is null do nothing;
  end loop;
end $$;

-- ── Función de importación atómica + concurrency-safe ──
create or replace function public.import_finance_transactions(p_account_id uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_import_id uuid;
  v_total int := jsonb_array_length(p_rows);
  v_new int := 0;
  v_dup int := 0;
  v_possible_transfers int := 0;
begin
  if not public.has_personal_finance_beta() then
    raise exception 'No tenés acceso a Finanzas personales.' using errcode = '42501';
  end if;

  -- Valida propiedad de la cuenta Y la bloquea (FOR UPDATE) -- serializa
  -- importaciones concurrentes de esta misma cuenta. Otras cuentas/usuarios
  -- no se ven afectados por este lock.
  select tenant_id into v_tenant_id
  from public.finance_accounts
  where id = p_account_id and user_id = v_uid
  for update;

  if v_tenant_id is null then
    raise exception 'Cuenta inválida o no pertenece al usuario.' using errcode = '42501';
  end if;

  insert into public.finance_imports (tenant_id, user_id, account_id, status, total_rows)
  values (v_tenant_id, v_uid, p_account_id, 'pending', v_total)
  returning id into v_import_id;

  -- Resuelve/crea categorías y subcategorías de TODAS las filas del archivo
  -- (aunque terminen siendo duplicadas -- no hay costo real en tenerlas
  -- creadas de antemano, y simplifica no tener que separar "solo las nuevas").
  insert into public.finance_categories (tenant_id, user_id, parent_id, name)
  select distinct v_tenant_id, v_uid, null, r->>'categoria'
  from jsonb_array_elements(p_rows) as r
  where nullif(r->>'categoria', '') is not null
  on conflict (user_id, (lower(trim(name)))) where parent_id is null do nothing;

  insert into public.finance_categories (tenant_id, user_id, parent_id, name)
  select distinct v_tenant_id, v_uid, parent.id, r->>'subcategoria'
  from jsonb_array_elements(p_rows) as r
  join public.finance_categories parent
    on parent.user_id = v_uid
   and parent.parent_id is null
   and lower(trim(parent.name)) = lower(trim(r->>'categoria'))
  where nullif(r->>'subcategoria', '') is not null
  on conflict (user_id, parent_id, (lower(trim(name)))) where parent_id is not null do nothing;

  -- Multiset dedupe: cuenta cuántas veces ya existe cada fingerprint en la
  -- cuenta, y cuántas veces aparece en el archivo (en orden) -- solo las
  -- ocurrencias que EXCEDEN lo ya existente se consideran nuevas.
  with incoming as (
    select
      (r->>'fecha')::date as fecha,
      r->>'descripcion' as descripcion,
      (r->>'amount')::numeric as amount,
      r->>'direction' as direction,
      r->>'nature' as nature,
      nullif(r->>'categoria', '') as categoria,
      nullif(r->>'subcategoria', '') as subcategoria,
      nullif(r->>'payment_method', '') as payment_method,
      r->>'dedupe_fingerprint' as fp,
      r as raw,
      row_number() over (partition by r->>'dedupe_fingerprint' order by ord) as occurrence
    from jsonb_array_elements(p_rows) with ordinality as t(r, ord)
  ),
  existing_counts as (
    select dedupe_fingerprint as fp, count(*) as cnt
    from public.finance_transactions
    where account_id = p_account_id and user_id = v_uid
    group by dedupe_fingerprint
  ),
  classified as (
    select i.*, (i.occurrence > coalesce(e.cnt, 0)) as is_new
    from incoming i left join existing_counts e on e.fp = i.fp
  ),
  resolved as (
    -- category_id = la subcategoría si hay match (root+child), si no la
    -- categoría raíz, si no NULL (sin categorizar). Dos LEFT JOIN separados
    -- en vez de una sola condición combinada -- más fácil de verificar que
    -- cada caso (con/sin subcategoría) resuelve al id correcto.
    select
      c.*,
      coalesce(child.id, root.id) as category_id
    from classified c
    left join public.finance_categories root
      on root.user_id = v_uid
     and root.parent_id is null
     and c.categoria is not null
     and lower(trim(root.name)) = lower(trim(c.categoria))
    left join public.finance_categories child
      on child.user_id = v_uid
     and child.parent_id = root.id
     and c.subcategoria is not null
     and lower(trim(child.name)) = lower(trim(c.subcategoria))
  ),
  inserted_rows as (
    insert into public.finance_import_rows (import_id, tenant_id, user_id, raw_row, dedupe_fingerprint, is_duplicate, matched_transaction_id)
    select v_import_id, v_tenant_id, v_uid, r.raw, r.fp, not r.is_new, null
    from resolved r
    returning 1
  ),
  inserted_tx as (
    insert into public.finance_transactions
      (tenant_id, user_id, account_id, date, description_original, amount, direction, nature,
       category_id, payment_method, origin, import_batch_id, dedupe_fingerprint)
    select v_tenant_id, v_uid, p_account_id, r.fecha, r.descripcion, r.amount, r.direction, r.nature,
           r.category_id, r.payment_method, 'import', v_import_id, r.fp
    from resolved r
    where r.is_new
    returning nature
  )
  select
    count(*) filter (where true),
    count(*) filter (where nature = 'transferencia_interna')
  into v_new, v_possible_transfers
  from inserted_tx;

  v_dup := v_total - v_new;

  update public.finance_imports
  set status = 'processed', new_rows = v_new, duplicate_rows = v_dup, possible_transfers = v_possible_transfers
  where id = v_import_id;

  return jsonb_build_object(
    'import_id', v_import_id,
    'total', v_total,
    'nuevos', v_new,
    'duplicados', v_dup,
    'posibles_transferencias', v_possible_transfers
  );
end;
$$;

comment on function public.import_finance_transactions(uuid, jsonb) is 'Importación atómica de movimientos de Finanzas personales. Bloquea la cuenta (FOR UPDATE) para serializar importaciones concurrentes; dedupe multiset autoritativo del lado del servidor; crea categorías/subcategorías faltantes; revierte todo si cualquier paso falla (una sola función = una sola transacción implícita).';

revoke all on function public.import_finance_transactions(uuid, jsonb) from public;
grant execute on function public.import_finance_transactions(uuid, jsonb) to authenticated;

-- ── Verificación (solo lectura, segura de correr en producción) ──
-- select email, personal_finance_beta from public.profiles where personal_finance_beta=true;
-- select * from public.finance_accounts;
-- select count(*) from public.finance_categories;
-- select proname, prosecdef from pg_proc where proname in ('has_personal_finance_beta','import_finance_transactions');

-- ── Prueba de comportamiento (SOLO en local/staging) ──
-- 1) select public.import_finance_transactions('<account_id>', '[{...146 filas...}]'::jsonb);
-- 2) Repetir la misma llamada -> debe devolver nuevos=0, duplicados=146.
-- 3) select count(*) from finance_transactions where nature='pago_tc'; -- debe dar 7.
-- 4) Ver la sección "Verificación" del plan de Fase 2 para el resto de las pruebas
--    (cruce contra resumen_mensual, RLS cruzado, atomicidad, concurrencia).

-- ── Rollback ──
-- drop function if exists public.import_finance_transactions(uuid, jsonb);
-- drop table if exists public.finance_import_rows;
-- drop table if exists public.finance_imports;
-- alter table public.finance_transactions drop constraint if exists finance_transactions_import_fk;
-- drop table if exists public.finance_transactions;
-- drop table if exists public.finance_categories;
-- drop table if exists public.finance_accounts;
-- drop function if exists public.has_personal_finance_beta();
