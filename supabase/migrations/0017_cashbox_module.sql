-- ════════════════════════════════════════════════════════════════
-- 0017 — CAJA Y TURNOS: último módulo de hotelería en Supabase.
-- Los movimientos del turno se guardan como jsonb en la misma fila
-- (mismo patrón que stays.folio y properties.seasons).
-- ════════════════════════════════════════════════════════════════

create table public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  responsable text,
  efectivo_inicial numeric(12,2) not null default 0,
  abierta boolean not null default true,
  apertura date not null default current_date,
  cierre date,
  movimientos jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index cash_sessions_tenant_idx on public.cash_sessions(tenant_id);

alter table public.cash_sessions enable row level security;

create policy "cash_sessions_select_own_tenant" on public.cash_sessions
  for select using (tenant_id = public.current_tenant_id());

create policy "cash_sessions_insert_own_tenant" on public.cash_sessions
  for insert with check (tenant_id = public.current_tenant_id());

create policy "cash_sessions_update_own_tenant" on public.cash_sessions
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "cash_sessions_delete_own_tenant" on public.cash_sessions
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_cash_sessions_insert_audit
  before insert on public.cash_sessions
  for each row execute function public.set_audit_fields();

create trigger trg_cash_sessions_update_audit
  before update on public.cash_sessions
  for each row execute function public.set_audit_fields();

create trigger trg_audit_cash_sessions
  after insert or update or delete on public.cash_sessions
  for each row execute function public.log_audit_event();
