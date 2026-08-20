-- ════════════════════════════════════════════════════════════════
-- 0037 — CASH_SESSIONS ampliada para Modo Propietario. Aditiva: los
-- campos viejos (responsable/efectivo_inicial/abierta/apertura/cierre)
-- quedan intactos y siguen siendo lo único que usa Modo Administrador.
--
-- IMPORTANTE: esta migración NO clasifica ninguna fila existente por
-- grupo — "grupo" queda NULL en todas las filas actuales hasta que el
-- usuario revise el preflight de solo lectura (one-off aparte) y decida
-- a mano cuáles son de Modo Propietario. No se puede asumir que las
-- cajas viejas son todas de Modo Administrador: ya se usó la Caja
-- compartida actual desde Modo Propietario al menos una vez.
-- ════════════════════════════════════════════════════════════════

alter table public.cash_sessions
  add column if not exists grupo text,
  add column if not exists operator_id uuid references public.cash_operators(id),
  add column if not exists numero int,
  add column if not exists opened_at timestamptz,
  add column if not exists closed_at timestamptz,
  add column if not exists opening_amount numeric,
  add column if not exists expected_cash numeric,
  add column if not exists declared_cash numeric,
  add column if not exists difference numeric,
  add column if not exists status text,
  add column if not exists opened_by uuid references auth.users(id),
  add column if not exists closed_by uuid references auth.users(id),
  add column if not exists closing_note text;

create unique index if not exists idx_cash_sessions_numero_por_tenant
  on public.cash_sessions(tenant_id, numero) where numero is not null;

-- Garantía REAL (no solo el chequeo previo de la RPC, que puede perder
-- una carrera entre dos requests simultáneas) de una sola Caja de Modo
-- Propietario abierta por tenant a la vez.
create unique index if not exists idx_cash_sessions_una_abierta_hostal
  on public.cash_sessions(tenant_id) where grupo='hostal' and status='abierta';

create table if not exists public.cash_session_counters (
  tenant_id uuid primary key references public.tenants(id),
  prox int not null default 1
);
alter table public.cash_session_counters enable row level security;
create policy "cash_session_counters_select_own_tenant" on public.cash_session_counters
  for select using (tenant_id = public.current_tenant_id());
-- Sin insert/update/delete para authenticated: solo lo toca la RPC de
-- apertura (security definer), con el patrón atómico insert...on conflict.

-- ────────────────────────────────────────────────────────────────
-- RLS: las filas grupo='hostal' dejan de ser escribibles con un
-- supabase.from('cash_sessions').update(...) directo del navegador,
-- aunque el usuario tenga el permiso — solo las RPC security definer
-- de 0040 (que ignoran RLS) pueden tocarlas. Modo Administrador
-- (grupo is null or grupo<>'hostal') sigue exactamente igual que hoy:
-- mismas políticas, mismo comportamiento directo desde el frontend.
-- ────────────────────────────────────────────────────────────────
alter policy "cash_sessions_insert_own_tenant" on public.cash_sessions
  with check (
    tenant_id = public.current_tenant_id()
    and public.has_permission('abrir_caja')
    and grupo is distinct from 'hostal'
  );

alter policy "cash_sessions_update_own_tenant" on public.cash_sessions
  using (
    tenant_id = public.current_tenant_id()
    and grupo is distinct from 'hostal'
    and (abierta = true or (public.has_permission('modificar_turno_cerrado') and public.is_admin()))
  )
  with check (
    tenant_id = public.current_tenant_id()
    and grupo is distinct from 'hostal'
    and (public.has_permission('registrar_movimientos_caja') or public.has_permission('cerrar_caja'))
  );

alter policy "cash_sessions_delete_own_tenant" on public.cash_sessions
  using (
    tenant_id = public.current_tenant_id()
    and grupo is distinct from 'hostal'
    and public.is_admin()
  );

-- ── Verificación ──
-- select column_name from information_schema.columns where table_name='cash_sessions'
--   and column_name in ('grupo','operator_id','numero','opened_at','closed_at',
--   'opening_amount','expected_cash','declared_cash','difference','status',
--   'opened_by','closed_by','closing_note'); -- 13 filas
-- select indexname from pg_indexes where tablename='cash_sessions'
--   and indexname in ('idx_cash_sessions_numero_por_tenant','idx_cash_sessions_una_abierta_hostal'); -- 2 filas
-- select count(*) from public.cash_sessions where grupo is not null; -- debe dar 0 (nada clasificado todavía)

-- ── Rollback ──
-- alter policy "cash_sessions_insert_own_tenant" on public.cash_sessions
--   with check (tenant_id = public.current_tenant_id() and public.has_permission('abrir_caja'));
-- alter policy "cash_sessions_update_own_tenant" on public.cash_sessions
--   using (tenant_id = public.current_tenant_id() and (abierta = true or (public.has_permission('modificar_turno_cerrado') and public.is_admin())))
--   with check (tenant_id = public.current_tenant_id() and (public.has_permission('registrar_movimientos_caja') or public.has_permission('cerrar_caja')));
-- alter policy "cash_sessions_delete_own_tenant" on public.cash_sessions
--   using (tenant_id = public.current_tenant_id() and public.is_admin());
-- drop index if exists idx_cash_sessions_una_abierta_hostal;
-- drop index if exists idx_cash_sessions_numero_por_tenant;
-- drop table if exists public.cash_session_counters;
-- alter table public.cash_sessions drop column if exists grupo, drop column if exists operator_id,
--   drop column if exists numero, drop column if exists opened_at, drop column if exists closed_at,
--   drop column if exists opening_amount, drop column if exists expected_cash, drop column if exists declared_cash,
--   drop column if exists difference, drop column if exists status, drop column if exists opened_by,
--   drop column if exists closed_by, drop column if exists closing_note;
