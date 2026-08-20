-- ════════════════════════════════════════════════════════════════
-- 0038 — CASH_AUDIT_LOG: auditoría campo-por-campo de Caja (Modo
-- Propietario), append-only. Distinta del audit_log genérico (0011),
-- que guarda old_data/new_data como fila completa — acá se pide
-- explícitamente campo/valor anterior/valor nuevo/motivo, y NUNCA debe
-- poder contener el PIN ni su hash (eso lo garantiza que las RPC de
-- 0040 arman esta fila a mano, nunca copiando cash_operator_secrets).
-- ════════════════════════════════════════════════════════════════

create table public.cash_audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  cash_session_id uuid references public.cash_sessions(id),
  operator_id uuid references public.cash_operators(id), -- quién autorizó ESTA acción con su PIN (no necesariamente quien abrió la caja)
  user_id uuid references auth.users(id),                -- auth.uid() logueado en Software EYO al momento de la acción
  accion text not null,
  campo text,
  valor_anterior text,
  valor_nuevo text,
  motivo text,
  created_at timestamptz not null default now()
);
create index idx_cash_audit_log_session on public.cash_audit_log(cash_session_id);
create index idx_cash_audit_log_tenant on public.cash_audit_log(tenant_id);

alter table public.cash_audit_log enable row level security;
create policy "cash_audit_log_select_own_tenant" on public.cash_audit_log
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_caja'));
-- Sin insert/update/delete para "authenticated": append-only, solo lo
-- escriben las funciones security definer de 0040. No se puede borrar
-- ni modificar un registro de auditoría desde el frontend normal.

-- ── Verificación ──
-- select count(*) from pg_policies where tablename='cash_audit_log'; -- debe ser 1 (solo select)

-- ── Rollback ──
-- drop table if exists public.cash_audit_log;
