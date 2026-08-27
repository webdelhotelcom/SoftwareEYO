-- ════════════════════════════════════════════════════════════════
-- 0050 — Finanzas personales, Fase 3: Cuenta Empresa + transferencias
-- internas + base de consolidación.
--
-- Cuenta Empresa nace VACÍA (kind='business', sin movimientos sembrados) --
-- no se reconstruye ni se inventa historial. finance_internal_transfers
-- queda lista (con FK compuestas + índices únicos parciales) para cuando
-- haya al menos un movimiento real cruzable entre las dos cuentas. Detección
-- de transferencias desacoplada de la importación (scan_finance_internal_
-- transfer_candidates() es un segundo paso explícito del cliente, nunca una
-- dependencia de import_finance_transactions()). get_accounts_summary()
-- distingue explícitamente saldo bancario verificado (requiere
-- balance_reference_amount) de completitud de movimientos (transactions_
-- complete_from/through) -- son dos cosas independientes, nunca mezcladas.
-- ════════════════════════════════════════════════════════════════

-- ── Cuenta Empresa: fila vacía, ningún movimiento sembrado ──
do $$
declare
  v_user_id uuid;
  v_tenant_id uuid;
begin
  select id, tenant_id into v_user_id, v_tenant_id
  from public.profiles where email = 'orielesymama@gmail.com' limit 1;

  if v_user_id is null then
    return;
  end if;

  insert into public.finance_accounts (tenant_id, user_id, kind, name, currency)
  values (v_tenant_id, v_user_id, 'business', 'Cuenta Empresa', 'UYU');
end $$;

-- ── finance_transactions: admite origin='reconstructed' (excepción marcada,
-- no se ejerce todavía) + description_original nullable + reconstruction_note ──
alter table public.finance_transactions drop constraint if exists finance_transactions_origin_check;
alter table public.finance_transactions add constraint finance_transactions_origin_check
  check (origin in ('manual', 'import', 'reconstructed'));
alter table public.finance_transactions alter column description_original drop not null;
alter table public.finance_transactions add column reconstruction_note text;

comment on column public.finance_transactions.reconstruction_note is 'Solo para origin=''reconstructed'': explica de dónde sale un movimiento que no viene de un extracto bancario real (ej. contraparte reconstruida de una transferencia ya confirmada del otro lado). Nunca se usa para fingir una descripción bancaria real.';

-- ── Transferencias entre las propias cuentas del usuario ──
create table public.finance_internal_transfers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  user_id uuid not null references auth.users(id),
  source_transaction_id uuid not null,
  destination_transaction_id uuid not null,
  source_account_id uuid not null,
  destination_account_id uuid not null,
  amount numeric not null,
  date date not null,
  purpose text check (purpose in ('credit_card_payment_funding')),
  confidence numeric,
  status text not null check (status in ('confirmed', 'rejected')),
  decided_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (source_transaction_id, user_id, tenant_id) references public.finance_transactions (id, user_id, tenant_id),
  foreign key (destination_transaction_id, user_id, tenant_id) references public.finance_transactions (id, user_id, tenant_id),
  foreign key (source_account_id, user_id, tenant_id) references public.finance_accounts (id, user_id, tenant_id),
  foreign key (destination_account_id, user_id, tenant_id) references public.finance_accounts (id, user_id, tenant_id),
  unique (source_transaction_id, destination_transaction_id)
);

-- Una transacción CONFIRMADA nunca puede quedar vinculada a más de una
-- transferencia (ni como origen ni como destino) -- garantizado por índice
-- único parcial, no solo por lógica de aplicación.
create unique index finance_internal_transfers_source_confirmed
  on public.finance_internal_transfers (source_transaction_id) where status = 'confirmed';
create unique index finance_internal_transfers_dest_confirmed
  on public.finance_internal_transfers (destination_transaction_id) where status = 'confirmed';

alter table public.finance_internal_transfers enable row level security;
create policy "finance_internal_transfers_own" on public.finance_internal_transfers for all
  using (user_id = auth.uid() and public.has_personal_finance_beta())
  with check (user_id = auth.uid() and public.has_personal_finance_beta() and tenant_id = public.current_tenant_id());

-- ── find_finance_internal_transfer_candidates: candidatos por consulta a la
-- base (no por array en memoria del cliente). Excluye transacciones ya
-- confirmadas en cualquier transferencia, y excluye PARES puntuales ya
-- rechazados (un rechazo descarta ese par exacto, nunca la transacción
-- completa contra el resto de sus posibles candidatos). ──
create or replace function public.find_finance_internal_transfer_candidates(p_transaction_id uuid)
returns setof public.finance_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_account_id uuid;
  v_date date;
  v_amount numeric;
  v_direction text;
begin
  if not public.has_personal_finance_beta() then
    raise exception 'No tenés acceso a Finanzas personales.' using errcode = '42501';
  end if;

  select account_id, date, amount, direction
  into v_account_id, v_date, v_amount, v_direction
  from public.finance_transactions
  where id = p_transaction_id and user_id = v_uid;

  if v_account_id is null then
    raise exception 'Movimiento inválido o no pertenece al usuario.' using errcode = '42501';
  end if;

  return query
  select c.*
  from public.finance_transactions c
  where c.user_id = v_uid
    and c.account_id <> v_account_id
    and c.date = v_date
    and c.amount = v_amount
    and c.direction <> v_direction
    and not exists (
      select 1 from public.finance_internal_transfers ft
      where ft.status = 'confirmed'
        and (ft.source_transaction_id = c.id or ft.destination_transaction_id = c.id)
    )
    and not exists (
      select 1 from public.finance_internal_transfers ft
      where ft.status = 'rejected'
        and ((ft.source_transaction_id = p_transaction_id and ft.destination_transaction_id = c.id)
          or (ft.source_transaction_id = c.id and ft.destination_transaction_id = p_transaction_id))
    );
end;
$$;

comment on function public.find_finance_internal_transfer_candidates(uuid) is 'Candidatos de transferencia interna para un movimiento: misma fecha/monto, dirección opuesta, otra cuenta del mismo usuario. Excluye ya-confirmados (globalmente) y pares ya-rechazados (solo ese par exacto).';

revoke all on function public.find_finance_internal_transfer_candidates(uuid) from public;
grant execute on function public.find_finance_internal_transfer_candidates(uuid) to authenticated;

-- ── scan_finance_internal_transfer_candidates: mismo matching de arriba,
-- aplicado en lote a todos los movimientos pendientes de una cuenta. Se
-- llama como paso EXPLÍCITO del cliente después de una importación exitosa
-- (o a demanda, botón "Buscar transferencias") -- nunca desde adentro de
-- import_finance_transactions() (0049 no depende de esta función). ──
create or replace function public.scan_finance_internal_transfer_candidates(p_account_id uuid)
returns table (transaction_id uuid, candidate_id uuid, candidate_account_id uuid, candidate_date date, candidate_amount numeric)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_personal_finance_beta() then
    raise exception 'No tenés acceso a Finanzas personales.' using errcode = '42501';
  end if;

  if not exists (select 1 from public.finance_accounts where id = p_account_id and user_id = auth.uid()) then
    raise exception 'Cuenta inválida o no pertenece al usuario.' using errcode = '42501';
  end if;

  return query
  select t.id, c.id, c.account_id, c.date, c.amount
  from public.finance_transactions t
  cross join lateral public.find_finance_internal_transfer_candidates(t.id) c
  where t.account_id = p_account_id
    and t.user_id = auth.uid()
    and not exists (
      select 1 from public.finance_internal_transfers ft
      where ft.status = 'confirmed'
        and (ft.source_transaction_id = t.id or ft.destination_transaction_id = t.id)
    );
end;
$$;

comment on function public.scan_finance_internal_transfer_candidates(uuid) is 'Escaneo en lote de find_finance_internal_transfer_candidates() para todos los movimientos pendientes de una cuenta -- pensado para correr después de importar un extracto real, sin revisar movimiento por movimiento a mano.';

revoke all on function public.scan_finance_internal_transfer_candidates(uuid) from public;
grant execute on function public.scan_finance_internal_transfer_candidates(uuid) to authenticated;

-- ── confirm_finance_internal_transfer: RPC atómico de Confirmar/Rechazar ──
create or replace function public.confirm_finance_internal_transfer(
  p_source_transaction_id uuid,
  p_destination_transaction_id uuid,
  p_decision text
)
returns public.finance_internal_transfers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tenant_id uuid;
  v_source record;
  v_destination record;
  v_result public.finance_internal_transfers;
begin
  if not public.has_personal_finance_beta() then
    raise exception 'No tenés acceso a Finanzas personales.' using errcode = '42501';
  end if;

  if p_decision not in ('confirmed', 'rejected') then
    raise exception 'Decisión inválida.';
  end if;

  select id, tenant_id, account_id, date, amount, direction into v_source
  from public.finance_transactions
  where id = p_source_transaction_id and user_id = v_uid;

  select id, tenant_id, account_id, date, amount, direction into v_destination
  from public.finance_transactions
  where id = p_destination_transaction_id and user_id = v_uid;

  if v_source.id is null or v_destination.id is null then
    raise exception 'Movimiento inválido o no pertenece al usuario.' using errcode = '42501';
  end if;
  if v_source.account_id = v_destination.account_id then
    raise exception 'Las dos transacciones deben ser de cuentas distintas.';
  end if;
  if v_source.date <> v_destination.date or v_source.amount <> v_destination.amount then
    raise exception 'Las transacciones no coinciden en fecha/monto.';
  end if;
  if v_source.direction = v_destination.direction then
    raise exception 'Las transacciones deben tener direcciones opuestas.';
  end if;

  v_tenant_id := v_source.tenant_id;

  if p_decision = 'confirmed' then
    if exists (
      select 1 from public.finance_internal_transfers
      where status = 'confirmed'
        and (source_transaction_id in (p_source_transaction_id, p_destination_transaction_id)
          or destination_transaction_id in (p_source_transaction_id, p_destination_transaction_id))
    ) then
      raise exception 'Una de las dos transacciones ya está vinculada a otra transferencia confirmada.';
    end if;
  end if;

  insert into public.finance_internal_transfers (
    tenant_id, user_id, source_transaction_id, destination_transaction_id,
    source_account_id, destination_account_id, amount, date, status, decided_at
  )
  values (
    v_tenant_id, v_uid, p_source_transaction_id, p_destination_transaction_id,
    v_source.account_id, v_destination.account_id, v_source.amount, v_source.date, p_decision, now()
  )
  on conflict (source_transaction_id, destination_transaction_id)
  do update set status = excluded.status, decided_at = excluded.decided_at
  returning * into v_result;

  if p_decision = 'confirmed' then
    update public.finance_transactions set nature = 'transferencia_interna'
    where id in (p_source_transaction_id, p_destination_transaction_id) and user_id = v_uid;
  end if;

  return v_result;
end;
$$;

comment on function public.confirm_finance_internal_transfer(uuid, uuid, text) is 'Confirma o rechaza una transferencia interna candidata. Atómico: valida ambos lados, evita doble-vínculo de una transacción confirmada, y (si se confirma) marca nature=transferencia_interna en ambas transacciones. Revierte todo si cualquier validación falla.';

revoke all on function public.confirm_finance_internal_transfer(uuid, uuid, text) from public;
grant execute on function public.confirm_finance_internal_transfer(uuid, uuid, text) to authenticated;

-- ── get_accounts_summary: base de consolidación, solo motor de consulta ──
create or replace function public.get_accounts_summary()
returns table (
  account_id uuid,
  kind text,
  name text,
  transactions_complete_from date,
  transactions_complete_through date,
  balance_reference_amount numeric,
  balance_reference_date date,
  verified_balance_amount numeric,
  balance_as_of date,
  is_current boolean,
  real_income numeric,
  real_expenses numeric,
  economic_result numeric
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_personal_finance_beta() then
    raise exception 'No tenés acceso a Finanzas personales.' using errcode = '42501';
  end if;

  return query
  select
    a.id as account_id,
    a.kind,
    a.name,
    a.transactions_complete_from,
    a.transactions_complete_through,
    a.balance_reference_amount,
    a.balance_reference_date,
    case
      when a.balance_reference_amount is null then null
      when a.transactions_complete_from is not null
       and a.transactions_complete_from <= a.balance_reference_date + 1
      then a.balance_reference_amount + coalesce(mv.flow_after_reference, 0)
      else a.balance_reference_amount
    end as verified_balance_amount,
    case
      when a.balance_reference_amount is null then null
      when a.transactions_complete_from is not null
       and a.transactions_complete_from <= a.balance_reference_date + 1
      then a.transactions_complete_through
      else a.balance_reference_date
    end as balance_as_of,
    (
      case
        when a.balance_reference_amount is null then false
        when a.transactions_complete_from is not null
         and a.transactions_complete_from <= a.balance_reference_date + 1
        then a.transactions_complete_through = current_date
        else a.balance_reference_date = current_date
      end
    ) as is_current,
    coalesce(mv.real_income, 0) as real_income,
    coalesce(mv.real_expenses, 0) as real_expenses,
    coalesce(mv.real_income, 0) - coalesce(mv.real_expenses, 0) as economic_result
  from public.finance_accounts a
  left join lateral (
    select
      sum(case when t.direction = 'salida' then -t.amount else t.amount end)
        filter (where a.balance_reference_date is not null and t.date > a.balance_reference_date
                 and (a.transactions_complete_through is null or t.date <= a.transactions_complete_through))
        as flow_after_reference,
      sum(t.amount) filter (where t.direction = 'entrada' and t.nature <> 'transferencia_interna') as real_income,
      sum(t.amount) filter (where t.direction = 'salida' and t.nature = 'gasto') as real_expenses
    from public.finance_transactions t
    where t.account_id = a.id and t.user_id = auth.uid()
  ) mv on true
  where a.user_id = auth.uid();
end;
$$;

comment on function public.get_accounts_summary() is 'Motor de consulta de consolidación (Fase 3): por cuenta, separa saldo bancario verificado (requiere balance_reference_amount) de resultado económico (ingresos reales - gastos reales). verified_balance_amount/balance_as_of nunca proyectan más allá de la cobertura de movimientos confirmada. is_current=true solo si balance_as_of es hoy. No calcula ningún total consolidado -- eso es Fase 4, y solo cuando todas las cuentas tengan saldo verificable para una fecha común.';

revoke all on function public.get_accounts_summary() from public;
grant execute on function public.get_accounts_summary() to authenticated;

-- ── Verificación (solo lectura) ──
-- select kind, name, transactions_complete_from, transactions_complete_through, balance_reference_amount from finance_accounts order by kind;
-- select count(*) from finance_transactions where account_id=(select id from finance_accounts where kind='business');
-- select count(*) from finance_internal_transfers;
-- select * from get_accounts_summary();

-- ── Rollback ──
-- drop function if exists public.get_accounts_summary();
-- drop function if exists public.confirm_finance_internal_transfer(uuid, uuid, text);
-- drop function if exists public.scan_finance_internal_transfer_candidates(uuid);
-- drop function if exists public.find_finance_internal_transfer_candidates(uuid);
-- drop table if exists public.finance_internal_transfers;
-- alter table public.finance_transactions drop column if exists reconstruction_note;
-- alter table public.finance_transactions alter column description_original set not null;
-- alter table public.finance_transactions drop constraint if exists finance_transactions_origin_check;
-- alter table public.finance_transactions add constraint finance_transactions_origin_check check (origin in ('manual','import'));
-- delete from finance_accounts where kind='business';
