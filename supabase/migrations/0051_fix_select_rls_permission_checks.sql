-- ════════════════════════════════════════════════════════════════
-- 0051 — Corrige el mismo bug que 0026 ya había encontrado y arreglado
-- para el módulo de precios, pero que quedó sin corregir en el resto:
-- las políticas de SELECT de casi todas las tablas exigían únicamente
-- tenant_id = current_tenant_id(), nunca el permiso "ver_X" que ya
-- existe en permissions_catalog desde 0019 (usado ahí solo para
-- insert/update/delete). Un usuario autenticado del tenant, sin
-- importar su rol, podía leer estas tablas completas por la API REST
-- directa, aunque la interfaz le oculte el botón/la pantalla.
--
-- No se toca ninguna política de INSERT/UPDATE/DELETE salvo dos
-- excepciones puntuales (properties/reservations UPDATE), que ya
-- exigían el permiso correcto en el WITH CHECK pero habían perdido el
-- mismo filtro de propietario que sí tiene su política de SELECT.
--
-- owners.cuenta (dato bancario del propietario) queda fuera de esta
-- migración a propósito -- es un problema de nivel de COLUMNA, no de
-- fila (RLS no puede resolverlo), y requiere separar esa columna a su
-- propia tabla. Documentado como pendiente, no se improvisa acá.
-- ════════════════════════════════════════════════════════════════

-- ── OWNERS ──
drop policy if exists "owners_select_own_tenant" on public.owners;
create policy "owners_select_own_tenant" on public.owners
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_propietarios'));

-- ── EXPENSES ──
drop policy if exists "expenses_select_own_tenant" on public.expenses;
create policy "expenses_select_own_tenant" on public.expenses
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_gastos'));

-- ── GUESTS ──
drop policy if exists "guests_select_own_tenant" on public.guests;
create policy "guests_select_own_tenant" on public.guests
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_huespedes'));

-- ── TASKS ──
drop policy if exists "tasks_select_own_tenant" on public.tasks;
create policy "tasks_select_own_tenant" on public.tasks
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_tareas'));

-- ── ROOM_TYPES / ROOMS ──
drop policy if exists "room_types_select_own_tenant" on public.room_types;
create policy "room_types_select_own_tenant" on public.room_types
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_habitaciones'));

drop policy if exists "rooms_select_own_tenant" on public.rooms;
create policy "rooms_select_own_tenant" on public.rooms
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_habitaciones'));

-- ── STAYS (cuenta del huésped) ──
drop policy if exists "stays_select_own_tenant" on public.stays;
create policy "stays_select_own_tenant" on public.stays
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_cuenta_huesped'));

-- ── HK_TASKS (housekeeping) ──
drop policy if exists "hk_tasks_select_own_tenant" on public.hk_tasks;
create policy "hk_tasks_select_own_tenant" on public.hk_tasks
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_housekeeping'));

-- ── MAINT_TICKETS ──
drop policy if exists "maint_tickets_select_own_tenant" on public.maint_tickets;
create policy "maint_tickets_select_own_tenant" on public.maint_tickets
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_mantenimiento'));

-- ── CASH_SESSIONS — el hallazgo más grave: exponía la caja completa ──
drop policy if exists "cash_sessions_select_own_tenant" on public.cash_sessions;
create policy "cash_sessions_select_own_tenant" on public.cash_sessions
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_caja'));

-- ── BILLING_CONFIG / FACTURAS ──
drop policy if exists "billing_config_select_own_tenant" on public.billing_config;
create policy "billing_config_select_own_tenant" on public.billing_config
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('acceder_prefacturacion'));

drop policy if exists "facturas_select_own_tenant" on public.facturas;
create policy "facturas_select_own_tenant" on public.facturas
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('acceder_prefacturacion'));

-- ── PROPERTIES — mantiene el filtro de propietario ya existente ──
drop policy if exists "properties_select_own_tenant" on public.properties;
create policy "properties_select_own_tenant" on public.properties
  for select using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('ver_alojamientos')
    and (
      public.current_owner_id() is null
      or propietario_id = public.current_owner_id()
    )
  );

-- UPDATE ya exigía el permiso correcto (editar_alojamientos) en el WITH
-- CHECK, pero el USING había perdido el filtro de propietario que sí
-- tiene el SELECT -- un rol "propietario" con editar_alojamientos podría
-- haber editado alojamientos ajenos dentro del mismo tenant.
alter policy "properties_update_own_tenant" on public.properties
  using (
    tenant_id = public.current_tenant_id()
    and (
      public.current_owner_id() is null
      or propietario_id = public.current_owner_id()
    )
  );

-- ── RESERVATIONS — mismo criterio que properties ──
drop policy if exists "reservations_select_own_tenant" on public.reservations;
create policy "reservations_select_own_tenant" on public.reservations
  for select using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('ver_reservas')
    and (
      public.current_owner_id() is null
      or propiedad_id in (select id from public.properties where propietario_id = public.current_owner_id())
    )
  );

alter policy "reservations_update_own_tenant" on public.reservations
  using (
    tenant_id = public.current_tenant_id()
    and (
      public.current_owner_id() is null
      or propiedad_id in (select id from public.properties where propietario_id = public.current_owner_id())
    )
  );

-- ── ROLE_PERMISSIONS — solo quien administra roles ve la matriz completa ──
drop policy if exists "role_permissions_select_own_tenant" on public.role_permissions;
create policy "role_permissions_select_own_tenant" on public.role_permissions
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('administrar_roles'));

-- ── PROFILES — un usuario siempre ve su propia fila (lo necesita el login
-- para leer su propio tenant_id/rol); para ver las de OTROS del mismo
-- tenant, hace falta ver_usuarios. Nunca se le exige el permiso para ver
-- su propia fila -- si no, un usuario sin ver_usuarios no podría ni
-- cargar la sesión.
drop policy if exists "profiles_select_same_tenant" on public.profiles;
create policy "profiles_select_same_tenant" on public.profiles
  for select using (
    id = auth.uid()
    or (tenant_id = public.current_tenant_id() and public.has_permission('ver_usuarios'))
  );
