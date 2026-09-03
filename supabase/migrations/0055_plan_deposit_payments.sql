-- ════════════════════════════════════════════════════════════════
-- 0055 — Botón de pago de la seña del plan (software.html), vía
-- Mercado Pago Checkout Pro / Orders API. NO tiene nada que ver con el
-- software en sí (hoteles cobrándole a huéspedes) -- esto es Bestoic
-- cobrándole a un prospecto la seña del 50% de su propio plan
-- (Inicial/Profesional). Por eso esta tabla NO lleva tenant_id: quien
-- paga es un prospecto, no un usuario logueado de ningún tenant.
--
-- Se lee/escribe EXCLUSIVAMENTE desde las Netlify Functions
-- (netlify/functions/mp-plan-*.js), usando service_role -- ni el sitio
-- público ni el panel logueado tienen ningún acceso directo. El usuario
-- consulta esta tabla con SQL directo en el Dashboard de Supabase.
--
-- Diseño revisado y corregido en 4 rondas antes de implementar (ver
-- plan): Orders API (no Preferences, que Mercado Pago ya trata como
-- legacy), idempotencia atómica sin bloqueos indefinidos, distinción
-- error_reintentable/error_final, estados reales de Orders API.
-- ════════════════════════════════════════════════════════════════

create table public.plan_deposit_payments (
  id uuid primary key default gen_random_uuid(),
  plan text not null check (plan in ('inicial','profesional')),
  nombre text,
  email text,
  telefono text,
  plan_price_usd numeric not null check (plan_price_usd > 0),  -- precio total del plan al momento del cobro (150/500) -- congelado, nunca recalculado después
  deposit_percentage numeric not null default 50 check (deposit_percentage between 1 and 100),
  exchange_rate numeric not null check (exchange_rate > 0),  -- el USD->UYU usado para este cobro puntual -- congelado, mismo criterio
  amount_uyu numeric not null check (amount_uyu > 0),
  idempotency_key uuid not null unique,  -- generado por el frontend, uno por intento -- ancla real de la idempotencia (usado también como X-Idempotency-Key hacia MP)
  mercado_pago_order_id text,   -- id de la Order de Mercado Pago (Orders API) -- hace falta para consultar/cancelar/reembolsar después
  checkout_url text,            -- la URL de checkout devuelta por MP -- se reutiliza si el mismo idempotency_key vuelve a pedir
  mercado_pago_payment_id text, -- el/los pago(s) asociados a la orden, si MP los expone así -- confirmar forma exacta al implementar el webhook real
  external_reference uuid not null unique,  -- = id de esta fila, nunca un valor separado
  status text not null default 'creando' check (status in (
    'creando','listo','pendiente','pagado','rechazado','cancelado',
    'error_reintentable','error_final','reembolsado','reembolso_parcial',
    'contracargo','en_revision','autorizacion_pendiente'
  )),
  creation_started_at timestamptz not null default now(),  -- para detectar un intento trabado (creando hace más del umbral) y poder recuperarlo
  raw_status text,      -- status/status_detail crudos de Mercado Pago, para auditar
  status_detail text,
  failure_reason text,  -- texto legible armado por nosotros para el caso de rechazo/desajuste/error
  paid_at timestamptz,  -- cuándo pasó a 'pagado' según el webhook
  cuenta_creada boolean not null default false,  -- lo marca el usuario a mano cuando da de alta el tenant
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Un mismo mercado_pago_order_id nunca puede quedar guardado en 2 filas
-- (protección estructural extra, más allá de la lógica del RPC/webhook).
create unique index plan_deposit_payments_mp_order_unique
  on public.plan_deposit_payments (mercado_pago_order_id)
  where mercado_pago_order_id is not null;

create index plan_deposit_payments_status_idx on public.plan_deposit_payments (status);

alter table public.plan_deposit_payments enable row level security;
-- Sin ninguna policy para "authenticated" ni "anon" -- a propósito.
-- Se lee/escribe EXCLUSIVAMENTE desde las Netlify Functions
-- (service_role, saltándose RLS). No se construye una pantalla nueva en
-- el panel para esto en esta fase -- volumen bajo, se consulta por SQL.

-- ── RPC atómico que resuelve la carrera de idempotencia ──
-- Nunca bloquea más allá de la duración de este RPC -- el llamador se
-- entera si es "dueño" del intento (is_owner) y actúa según eso, en vez
-- de esperar bloqueado a que otra transacción termine. 4 pasos:
-- (1) reclamar la clave si es la primera vez,
-- (2) recuperar un 'creando' trabado hace más de 30s,
-- (3) reclamar un 'error_reintentable' de inmediato (ya es un resultado
--     definitivo, no ambiguo como 'creando'),
-- (4) si nada de eso aplica, solo leer sin reclamar nada.
create type public.plan_deposit_claim_result as (
  row public.plan_deposit_payments,
  is_owner boolean
);

create or replace function public.claim_plan_deposit_attempt(
  p_idempotency_key uuid, p_plan text, p_plan_price_usd numeric,
  p_exchange_rate numeric, p_deposit_percentage numeric,
  p_amount_uyu numeric, p_nombre text, p_email text, p_telefono text
) returns public.plan_deposit_claim_result
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.plan_deposit_payments;
  v_new_id uuid := gen_random_uuid();
  v_result public.plan_deposit_claim_result;
begin
  -- 1) Intento de ser el primero en reclamar esta clave.
  insert into public.plan_deposit_payments (
    id, plan, plan_price_usd, exchange_rate, deposit_percentage,
    amount_uyu, idempotency_key, nombre, email, telefono,
    external_reference, status, creation_started_at
  ) values (
    v_new_id, p_plan, p_plan_price_usd, p_exchange_rate, p_deposit_percentage,
    p_amount_uyu, p_idempotency_key, p_nombre, p_email, p_telefono,
    v_new_id, 'creando', now()
  )
  on conflict (idempotency_key) do nothing
  returning * into v_row;

  if v_row.id is not null then
    v_result.row := v_row; v_result.is_owner := true;
    return v_result;
  end if;

  -- 2) Ya existía -- intentar recuperar un intento trabado (creando
  -- hace más del umbral de 30s) antes de simplemente leerlo sin más.
  update public.plan_deposit_payments
  set creation_started_at = now()
  where idempotency_key = p_idempotency_key
    and status = 'creando'
    and creation_started_at < now() - interval '30 seconds'
  returning * into v_row;

  if v_row.id is not null then
    v_result.row := v_row; v_result.is_owner := true;  -- recuperó un intento trabado
    return v_result;
  end if;

  -- 3) Reclamar un error reintentable -- a diferencia de 'creando'
  -- (que puede seguir legítimamente en curso), un error ya es un
  -- resultado definitivo de ese intento anterior, así que se puede
  -- reclamar de inmediato, sin esperar ningún umbral de tiempo.
  update public.plan_deposit_payments
  set creation_started_at = now(), status = 'creando'
  where idempotency_key = p_idempotency_key
    and status = 'error_reintentable'
  returning * into v_row;

  if v_row.id is not null then
    v_result.row := v_row; v_result.is_owner := true;
    return v_result;
  end if;

  -- 4) No es dueña -- simple lectura, sin ningún lock.
  select * into v_row from public.plan_deposit_payments
  where idempotency_key = p_idempotency_key;
  v_result.row := v_row; v_result.is_owner := false;
  return v_result;
end;
$$;

revoke all on function public.claim_plan_deposit_attempt(uuid,text,numeric,numeric,numeric,numeric,text,text,text) from public;
grant execute on function public.claim_plan_deposit_attempt(uuid,text,numeric,numeric,numeric,numeric,text,text,text) to service_role;
-- Nunca a "authenticated"/"anon" -- solo las Netlify Functions (con
-- service_role) llaman a esto.

-- ── Rate limiting simple para las funciones públicas (mp-plan-order,
-- mp-plan-order-status) -- Netlify no garantiza rate limiting nativo en
-- todos los planes, así que se arma acá, respaldado por Supabase,
-- atómico vía upsert. Una fila por IP+ventana de tiempo (ventanas de 1
-- minuto, truncadas). No lleva RLS con policies (mismo criterio que
-- plan_deposit_payments): solo la tocan las Netlify Functions con
-- service_role.
create table public.plan_order_rate_limits (
  ip text not null,
  window_start timestamptz not null,
  count int not null default 1,
  primary key (ip, window_start)
);
alter table public.plan_order_rate_limits enable row level security;

-- Incrementa el contador de la ventana actual y devuelve el total.
-- Atómico (insert...on conflict...do update), sin condición de carrera.
-- También poda filas de más de 1 hora en cada llamada (perezoso -- no
-- hace falta un cron para una tabla tan chica).
create or replace function public.bump_plan_order_rate_limit(p_ip text, p_window_start timestamptz)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  delete from public.plan_order_rate_limits where window_start < now() - interval '1 hour';
  insert into public.plan_order_rate_limits (ip, window_start, count)
  values (p_ip, p_window_start, 1)
  on conflict (ip, window_start) do update set count = public.plan_order_rate_limits.count + 1
  returning count into v_count;
  return v_count;
end;
$$;

revoke all on function public.bump_plan_order_rate_limit(text, timestamptz) from public;
grant execute on function public.bump_plan_order_rate_limit(text, timestamptz) to service_role;

-- ── Verificación ──
-- select count(*) from public.plan_deposit_payments; -- 0 filas al aplicar
-- select proname from pg_proc where proname = 'claim_plan_deposit_attempt';
-- select proname from pg_proc where proname = 'bump_plan_order_rate_limit';
