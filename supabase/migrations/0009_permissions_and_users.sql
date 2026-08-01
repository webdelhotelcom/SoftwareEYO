-- ════════════════════════════════════════════════════════════════
-- 0009 — USUARIOS Y PERMISOS (catálogo + grilla configurable por rol)
-- ════════════════════════════════════════════════════════════════

-- Catálogo de permisos — mismo para todos los clientes, no es por tenant.
create table public.permissions_catalog (
  key text primary key,
  label text not null,
  sort_order int not null default 0
);

insert into public.permissions_catalog (key,label,sort_order) values
  ('ver_reservas','Ver reservas',1),
  ('crear_reservas','Crear reservas',2),
  ('editar_reservas','Editar reservas',3),
  ('cancelar_reservas','Cancelar reservas',4),
  ('checkin','Hacer check-in',5),
  ('checkout','Hacer check-out',6),
  ('registrar_cobros','Registrar cobros',7),
  ('anular_cobros','Anular cobros',8),
  ('registrar_gastos','Registrar gastos',9),
  ('ver_resultados','Ver resultados',10),
  ('ver_propietarios','Ver propietarios',11),
  ('ver_comisiones','Ver comisiones',12),
  ('ver_caja','Ver caja',13),
  ('abrir_caja','Abrir caja',14),
  ('cerrar_caja','Cerrar caja',15),
  ('administrar_habitaciones','Administrar habitaciones',16),
  ('administrar_precios','Administrar precios',17),
  ('administrar_housekeeping','Administrar housekeeping',18),
  ('administrar_mantenimiento','Administrar mantenimiento',19),
  ('ver_reportes','Ver reportes',20),
  ('exportar_informacion','Exportar información',21),
  ('administrar_usuarios','Administrar usuarios',22),
  ('acceder_prefacturacion','Acceder a pre-facturación',23);

alter table public.permissions_catalog enable row level security;
create policy "permissions_catalog_select_all" on public.permissions_catalog
  for select using (auth.role() = 'authenticated');

-- Permisos por cliente + rol. Arranca con valores por default sensatos
-- (sembrados más abajo) y el administrador los puede reconfigurar desde
-- el panel — por eso es una tabla y no algo fijo en el código.
create table public.role_permissions (
  tenant_id uuid not null references public.tenants(id),
  role text not null,
  permission_key text not null references public.permissions_catalog(key),
  allowed boolean not null default false,
  primary key (tenant_id, role, permission_key)
);

alter table public.role_permissions enable row level security;

create policy "role_permissions_select_own_tenant" on public.role_permissions
  for select using (tenant_id = public.current_tenant_id());

-- current_tenant_id() y is_admin() son security definer para poder leer
-- profiles saltando su propia RLS (si no, recursión infinita). Solo
-- devuelven datos del usuario que hace la consulta (auth.uid()).
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and active = true
  )
$$;

create policy "role_permissions_admin_insert" on public.role_permissions
  for insert with check (tenant_id = public.current_tenant_id() and public.is_admin());

create policy "role_permissions_admin_update" on public.role_permissions
  for update using (tenant_id = public.current_tenant_id() and public.is_admin())
  with check (tenant_id = public.current_tenant_id() and public.is_admin());

create policy "role_permissions_admin_delete" on public.role_permissions
  for delete using (tenant_id = public.current_tenant_id() and public.is_admin());

-- Resuelve si el usuario logueado tiene un permiso puntual, según su rol
-- y los permisos configurados para su tenant. Es la función que usan las
-- políticas de escritura de otras tablas (reservations, expenses, etc.)
-- para exigir el permiso también del lado del servidor, no solo en la UI.
create or replace function public.has_permission(perm_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select rp.allowed
     from public.profiles pr
     join public.role_permissions rp
       on rp.tenant_id = pr.tenant_id and rp.role = pr.role and rp.permission_key = perm_key
     where pr.id = auth.uid()),
    false
  )
$$;

-- Siembra automática de permisos default para cada tenant NUEVO que se cree.
create or replace function public.seed_default_role_permissions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.role_permissions (tenant_id, role, permission_key, allowed)
  select new.id, r.role, p.key,
    case
      when r.role = 'admin' then true
      when r.role = 'gerencia' then p.key <> 'administrar_usuarios'
      when r.role = 'encargado' then p.key in ('ver_reservas','crear_reservas','editar_reservas','checkin','checkout','registrar_cobros','registrar_gastos','ver_caja','abrir_caja','cerrar_caja','administrar_habitaciones','administrar_housekeeping','administrar_mantenimiento','ver_reportes')
      when r.role = 'recepcion' then p.key in ('ver_reservas','crear_reservas','editar_reservas','checkin','checkout','registrar_cobros','ver_caja','abrir_caja','cerrar_caja')
      when r.role = 'limpieza' then p.key in ('ver_reservas','administrar_housekeeping')
      when r.role = 'mantenimiento' then p.key in ('administrar_mantenimiento')
      when r.role = 'contador' then p.key in ('ver_resultados','ver_comisiones','ver_reportes','exportar_informacion','acceder_prefacturacion')
      when r.role = 'propietario' then p.key in ('ver_resultados','ver_reportes')
      else false
    end
  from (values ('admin'),('gerencia'),('encargado'),('recepcion'),('limpieza'),('mantenimiento'),('contador'),('propietario')) as r(role)
  cross join public.permissions_catalog p;
  return new;
end;
$$;

create trigger trg_tenants_seed_permissions
  after insert on public.tenants
  for each row execute function public.seed_default_role_permissions();

-- Backfill: siembra los mismos defaults para los tenants que ya existían
-- antes de que este trigger existiera (por ejemplo, la cuenta founder).
insert into public.role_permissions (tenant_id, role, permission_key, allowed)
select t.id, r.role, p.key,
  case
    when r.role = 'admin' then true
    when r.role = 'gerencia' then p.key <> 'administrar_usuarios'
    when r.role = 'encargado' then p.key in ('ver_reservas','crear_reservas','editar_reservas','checkin','checkout','registrar_cobros','registrar_gastos','ver_caja','abrir_caja','cerrar_caja','administrar_habitaciones','administrar_housekeeping','administrar_mantenimiento','ver_reportes')
    when r.role = 'recepcion' then p.key in ('ver_reservas','crear_reservas','editar_reservas','checkin','checkout','registrar_cobros','ver_caja','abrir_caja','cerrar_caja')
    when r.role = 'limpieza' then p.key in ('ver_reservas','administrar_housekeeping')
    when r.role = 'mantenimiento' then p.key in ('administrar_mantenimiento')
    when r.role = 'contador' then p.key in ('ver_resultados','ver_comisiones','ver_reportes','exportar_informacion','acceder_prefacturacion')
    when r.role = 'propietario' then p.key in ('ver_resultados','ver_reportes')
    else false
  end
from public.tenants t
cross join (values ('admin'),('gerencia'),('encargado'),('recepcion'),('limpieza'),('mantenimiento'),('contador'),('propietario')) as r(role)
cross join public.permissions_catalog p
on conflict (tenant_id, role, permission_key) do nothing;

-- ══════════════════════════════════════════════════════════════
-- PROFILES: permitir que un admin cree y edite usuarios de su tenant.
-- (Hasta ahora solo se podían crear/editar por SQL directo.)
-- ══════════════════════════════════════════════════════════════
alter table public.profiles add column if not exists last_active_at timestamptz;

create policy "profiles_insert_by_admin" on public.profiles
  for insert with check (tenant_id = public.current_tenant_id() and public.is_admin());

create policy "profiles_update_by_admin" on public.profiles
  for update using (tenant_id = public.current_tenant_id() and public.is_admin())
  with check (tenant_id = public.current_tenant_id() and public.is_admin());

-- Límite de usuarios por contrato, validado en el servidor — mismo
-- criterio que el límite de alojamientos: nunca "sin límite" por default.
create or replace function public.check_users_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_plan_max int;
  v_client_max int;
  v_effective int;
  v_count int;
begin
  select plan into v_plan from public.tenants where id = new.tenant_id;
  select max_users into v_plan_max from public.plan_config where plan = v_plan;
  select max_users into v_client_max from public.client_limits where tenant_id = new.tenant_id;
  v_effective := coalesce(v_client_max, v_plan_max);

  if v_effective is null then
    raise exception 'Límite de usuarios no configurado para este cliente. Contactá al administrador de EYO.';
  end if;

  select count(*) into v_count from public.profiles where tenant_id = new.tenant_id;
  if v_count >= v_effective then
    raise exception 'Alcanzaste el límite de % usuarios de tu plan.', v_effective;
  end if;

  return new;
end;
$$;

create trigger trg_profiles_users_limit
  before insert on public.profiles
  for each row execute function public.check_users_limit();
