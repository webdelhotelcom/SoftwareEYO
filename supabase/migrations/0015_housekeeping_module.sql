-- ════════════════════════════════════════════════════════════════
-- 0015 — HOUSEKEEPING: tareas de limpieza de habitaciones.
-- ════════════════════════════════════════════════════════════════

create table public.hk_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  room_id uuid references public.rooms(id),
  responsable text,
  estado text not null default 'pendiente',
  notas text,
  ts date not null default current_date,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index hk_tasks_tenant_idx on public.hk_tasks(tenant_id);

alter table public.hk_tasks enable row level security;

create policy "hk_tasks_select_own_tenant" on public.hk_tasks
  for select using (tenant_id = public.current_tenant_id());

create policy "hk_tasks_insert_own_tenant" on public.hk_tasks
  for insert with check (tenant_id = public.current_tenant_id());

create policy "hk_tasks_update_own_tenant" on public.hk_tasks
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "hk_tasks_delete_own_tenant" on public.hk_tasks
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_hk_tasks_insert_audit
  before insert on public.hk_tasks
  for each row execute function public.set_audit_fields();

create trigger trg_hk_tasks_update_audit
  before update on public.hk_tasks
  for each row execute function public.set_audit_fields();

create trigger trg_audit_hk_tasks
  after insert or update or delete on public.hk_tasks
  for each row execute function public.log_audit_event();
