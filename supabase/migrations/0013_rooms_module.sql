-- ════════════════════════════════════════════════════════════════
-- 0013 — HABITACIONES: primer módulo de hotelería en Supabase.
-- Tipos de habitación (room_types) y Habitaciones (rooms), base de
-- la que van a depender Check-in/out, Housekeeping, Mantenimiento
-- y el Calendario hotelero en los próximos módulos.
-- ════════════════════════════════════════════════════════════════

create table public.room_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  nombre text not null,
  capacidad int not null default 1,
  camas int not null default 1,
  tipo_cama text,
  banio text not null default 'privado',
  ac boolean not null default false,
  tv boolean not null default false,
  frigobar boolean not null default false,
  precio numeric(12,2) not null default 0,
  descripcion text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index room_types_tenant_idx on public.room_types(tenant_id);

alter table public.room_types enable row level security;

create policy "room_types_select_own_tenant" on public.room_types
  for select using (tenant_id = public.current_tenant_id());

create policy "room_types_insert_own_tenant" on public.room_types
  for insert with check (tenant_id = public.current_tenant_id());

create policy "room_types_update_own_tenant" on public.room_types
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "room_types_delete_own_tenant" on public.room_types
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_room_types_insert_audit
  before insert on public.room_types
  for each row execute function public.set_audit_fields();

create trigger trg_room_types_update_audit
  before update on public.room_types
  for each row execute function public.set_audit_fields();

create trigger trg_audit_room_types
  after insert or update or delete on public.room_types
  for each row execute function public.log_audit_event();

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  tipo_id uuid references public.room_types(id),
  numero text not null,
  piso text,
  estado text not null default 'disponible',
  notas text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index rooms_tenant_idx on public.rooms(tenant_id);

alter table public.rooms enable row level security;

create policy "rooms_select_own_tenant" on public.rooms
  for select using (tenant_id = public.current_tenant_id());

create policy "rooms_insert_own_tenant" on public.rooms
  for insert with check (tenant_id = public.current_tenant_id());

create policy "rooms_update_own_tenant" on public.rooms
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "rooms_delete_own_tenant" on public.rooms
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_rooms_insert_audit
  before insert on public.rooms
  for each row execute function public.set_audit_fields();

create trigger trg_rooms_update_audit
  before update on public.rooms
  for each row execute function public.set_audit_fields();

create trigger trg_audit_rooms
  after insert or update or delete on public.rooms
  for each row execute function public.log_audit_event();
