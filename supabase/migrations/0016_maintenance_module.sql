-- ════════════════════════════════════════════════════════════════
-- 0016 — MANTENIMIENTO: incidencias de las habitaciones.
-- ════════════════════════════════════════════════════════════════

create table public.maint_tickets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  room_id uuid references public.rooms(id),
  prioridad text not null default 'media',
  categoria text,
  responsable text,
  costo numeric(12,2) not null default 0,
  estado text not null default 'abierta',
  notas text,
  fecha date not null default current_date,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index maint_tickets_tenant_idx on public.maint_tickets(tenant_id);

alter table public.maint_tickets enable row level security;

create policy "maint_tickets_select_own_tenant" on public.maint_tickets
  for select using (tenant_id = public.current_tenant_id());

create policy "maint_tickets_insert_own_tenant" on public.maint_tickets
  for insert with check (tenant_id = public.current_tenant_id());

create policy "maint_tickets_update_own_tenant" on public.maint_tickets
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "maint_tickets_delete_own_tenant" on public.maint_tickets
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_maint_tickets_insert_audit
  before insert on public.maint_tickets
  for each row execute function public.set_audit_fields();

create trigger trg_maint_tickets_update_audit
  before update on public.maint_tickets
  for each row execute function public.set_audit_fields();

create trigger trg_audit_maint_tickets
  after insert or update or delete on public.maint_tickets
  for each row execute function public.log_audit_event();
