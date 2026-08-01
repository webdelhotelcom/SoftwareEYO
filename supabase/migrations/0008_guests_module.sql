-- ════════════════════════════════════════════════════════════════
-- 0008 — GUESTS (Huéspedes). Con esto se reconecta reservations.guest_id
-- como una FK real (hasta ahora era texto suelto, sin nada del otro lado).
-- ════════════════════════════════════════════════════════════════

create table public.guests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  nombre text not null,
  apellido text,
  telefono text,
  email text,
  tipo_doc text default 'CI',
  doc text,
  pais text,
  fecha_nacimiento date,
  direccion text,
  obs text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index guests_tenant_idx on public.guests(tenant_id);

alter table public.guests enable row level security;

create policy "guests_select_own_tenant" on public.guests
  for select using (tenant_id = public.current_tenant_id());

create policy "guests_insert_own_tenant" on public.guests
  for insert with check (tenant_id = public.current_tenant_id());

create policy "guests_update_own_tenant" on public.guests
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "guests_delete_own_tenant" on public.guests
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_guests_insert_audit
  before insert on public.guests
  for each row execute function public.set_audit_fields();

create trigger trg_guests_update_audit
  before update on public.guests
  for each row execute function public.set_audit_fields();

-- reservations.guest_id era texto suelto (IDs numéricos de un esquema
-- anterior a que existiera esta tabla). No corresponden a ningún huésped
-- real, así que se limpian antes de convertir la columna al tipo correcto.
update public.reservations set guest_id = null where guest_id is not null;
alter table public.reservations alter column guest_id type uuid using guest_id::uuid;
alter table public.reservations
  add constraint reservations_guest_id_fkey
  foreign key (guest_id) references public.guests(id) on delete set null;
