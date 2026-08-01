-- ════════════════════════════════════════════════════════════════
-- 0007 — EXPENSES (Gastos). Con Reservas ya migrada, reserva_id
-- puede ser una FK real por primera vez (antes hubiera sido un
-- número de la demo vieja sin nada del otro lado).
-- ════════════════════════════════════════════════════════════════

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  propiedad_id uuid references public.properties(id),
  fecha date not null,
  categoria text not null,
  concepto text,
  monto numeric not null default 0,
  reserva_id uuid references public.reservations(id) on delete set null,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index expenses_tenant_idx on public.expenses(tenant_id);
create index expenses_propiedad_idx on public.expenses(propiedad_id);

alter table public.expenses enable row level security;

create policy "expenses_select_own_tenant" on public.expenses
  for select using (tenant_id = public.current_tenant_id());

create policy "expenses_insert_own_tenant" on public.expenses
  for insert with check (tenant_id = public.current_tenant_id());

create policy "expenses_update_own_tenant" on public.expenses
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "expenses_delete_own_tenant" on public.expenses
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_expenses_insert_audit
  before insert on public.expenses
  for each row execute function public.set_audit_fields();

create trigger trg_expenses_update_audit
  before update on public.expenses
  for each row execute function public.set_audit_fields();
