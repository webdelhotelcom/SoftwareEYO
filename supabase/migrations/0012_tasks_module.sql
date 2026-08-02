-- ════════════════════════════════════════════════════════════════
-- 0012 — TASKS (Tareas): último módulo de datos que quedaba en
-- localStorage. Con esto, todo el negocio vive en Supabase.
-- ════════════════════════════════════════════════════════════════

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  propiedad_id uuid references public.properties(id),
  label text not null,
  cat text not null default 'otro',
  due date,
  done boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index tasks_tenant_idx on public.tasks(tenant_id);

alter table public.tasks enable row level security;

create policy "tasks_select_own_tenant" on public.tasks
  for select using (tenant_id = public.current_tenant_id());

create policy "tasks_insert_own_tenant" on public.tasks
  for insert with check (tenant_id = public.current_tenant_id());

create policy "tasks_update_own_tenant" on public.tasks
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "tasks_delete_own_tenant" on public.tasks
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_tasks_insert_audit
  before insert on public.tasks
  for each row execute function public.set_audit_fields();

create trigger trg_tasks_update_audit
  before update on public.tasks
  for each row execute function public.set_audit_fields();

create trigger trg_audit_tasks
  after insert or update or delete on public.tasks
  for each row execute function public.log_audit_event();
