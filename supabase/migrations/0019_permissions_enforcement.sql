-- ════════════════════════════════════════════════════════════════
-- 0019 — CIERRE DEL HALLAZGO CRÍTICO DE LA AUDITORÍA (2026-08-02):
-- un usuario con rol "limpieza" pudo editar y borrar un alojamiento
-- llamando la API de Supabase directo, porque properties (y casi
-- todas las tablas agregadas después de 0010) solo exigían
-- "tenant_id = current_tenant_id()", sin mirar el rol.
--
-- Esta migración:
--  1) Agrega al catálogo los permisos que faltaban para cubrir los
--     módulos que hoy no tienen ninguna granularidad (Alojamientos,
--     Propietarios, Huéspedes, Tareas, Habitaciones/Estadías,
--     Housekeeping, Mantenimiento, Caja, Pre-facturación, Usuarios,
--     Auditoría). Reutiliza los 23 permisos que ya existían — no los
--     renombra ni les cambia el significado — para no romper lo que
--     ya está configurado y probado (reservations, expenses insert).
--  2) Siembra defaults sensatos por rol para las claves nuevas, tanto
--     para tenants futuros (dentro de seed_default_role_permissions)
--     como para los que ya existen (backfill, sin pisar filas que un
--     admin ya haya configurado a mano).
--  3) Reescribe las políticas RLS de escritura (INSERT/UPDATE/DELETE)
--     de properties, owners, guests, tasks, room_types, rooms, stays,
--     hk_tasks, maint_tickets, cash_sessions, billing_config,
--     facturas, y completa lo que quedó pendiente de expenses
--     (0010 solo había cubierto el insert).
--  4) Agrega el vínculo profiles.owner_id → owners, para que un
--     usuario con rol "propietario" solo pueda ver sus propios
--     alojamientos y reservas, no los de todo el tenant.
-- ════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1) CATÁLOGO — permisos nuevos (idempotente: no pisa lo que ya existe)
-- ────────────────────────────────────────────────────────────────
insert into public.permissions_catalog (key,label,sort_order) values
  ('ver_alojamientos','Ver alojamientos',30),
  ('crear_alojamientos','Crear alojamientos',31),
  ('editar_alojamientos','Editar alojamientos',32),
  ('eliminar_alojamientos','Eliminar alojamientos',33),
  ('crear_propietarios','Crear propietarios',34),
  ('editar_propietarios','Editar propietarios',35),
  ('eliminar_propietarios','Eliminar propietarios',36),
  ('ver_datos_bancarios','Ver datos bancarios de propietarios',37),
  ('ver_huespedes','Ver huéspedes',38),
  ('crear_huespedes','Crear huéspedes',39),
  ('editar_huespedes','Editar huéspedes',40),
  ('eliminar_huespedes','Eliminar huéspedes',41),
  ('eliminar_reservas','Eliminar reservas',42),
  ('ver_gastos','Ver gastos',43),
  ('editar_gastos','Editar gastos',44),
  ('eliminar_gastos','Eliminar gastos',45),
  ('ver_tareas','Ver tareas',46),
  ('crear_tareas','Crear tareas',47),
  ('editar_tareas','Editar tareas',48),
  ('asignar_tareas','Asignar tareas',49),
  ('eliminar_tareas','Eliminar tareas',50),
  ('ver_habitaciones','Ver habitaciones',51),
  ('administrar_tipos_habitacion','Administrar tipos de habitación',52),
  ('ver_cuenta_huesped','Ver la cuenta del huésped',53),
  ('registrar_cargos','Registrar cargos en la cuenta del huésped',54),
  ('registrar_pagos','Registrar pagos en la cuenta del huésped',55),
  ('anular_movimientos','Anular movimientos de la cuenta del huésped',56),
  ('ver_housekeeping','Ver housekeeping',57),
  ('iniciar_limpieza','Iniciar limpieza',58),
  ('finalizar_limpieza','Finalizar limpieza',59),
  ('inspeccionar_limpieza','Inspeccionar limpieza',60),
  ('ver_mantenimiento','Ver mantenimiento',61),
  ('crear_incidencias','Crear incidencias de mantenimiento',62),
  ('editar_incidencias','Editar incidencias de mantenimiento',63),
  ('cerrar_incidencias','Cerrar incidencias de mantenimiento',64),
  ('registrar_movimientos_caja','Registrar movimientos de caja',65),
  ('modificar_turno_cerrado','Modificar un turno de caja ya cerrado',66),
  ('crear_prefacturacion','Crear comprobantes de pre-facturación',67),
  ('editar_prefacturacion','Editar configuración de comprobantes',68),
  ('anular_prefacturacion','Anular comprobantes de pre-facturación',69),
  ('administrar_configuracion_fiscal','Administrar configuración fiscal (CAE, numeración)',70),
  ('ver_usuarios','Ver usuarios',71),
  ('crear_usuarios','Crear usuarios',72),
  ('editar_usuarios','Editar usuarios',73),
  ('desactivar_usuarios','Desactivar usuarios',74),
  ('administrar_roles','Administrar roles',75),
  ('ver_auditoria','Ver auditoría',76)
on conflict (key) do nothing;

-- ────────────────────────────────────────────────────────────────
-- 2) SEED — actualizar la función para tenants futuros
-- ────────────────────────────────────────────────────────────────
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
      when r.role = 'encargado' then p.key in (
        'ver_reservas','crear_reservas','editar_reservas','checkin','checkout','registrar_cobros','registrar_gastos',
        'ver_caja','abrir_caja','cerrar_caja','administrar_habitaciones','administrar_housekeeping','administrar_mantenimiento','ver_reportes',
        'ver_alojamientos','editar_alojamientos','ver_propietarios','ver_huespedes','crear_huespedes','editar_huespedes',
        'ver_tareas','crear_tareas','editar_tareas','asignar_tareas','ver_habitaciones','administrar_tipos_habitacion',
        'ver_cuenta_huesped','registrar_cargos','registrar_pagos','ver_housekeeping','iniciar_limpieza','finalizar_limpieza','inspeccionar_limpieza',
        'ver_mantenimiento','crear_incidencias','editar_incidencias','cerrar_incidencias','registrar_movimientos_caja','ver_gastos','editar_gastos'
      )
      when r.role = 'recepcion' then p.key in (
        'ver_reservas','crear_reservas','editar_reservas','checkin','checkout','registrar_cobros','ver_caja','abrir_caja','cerrar_caja',
        'ver_alojamientos','ver_huespedes','crear_huespedes','editar_huespedes','ver_cuenta_huesped','registrar_cargos','registrar_pagos',
        'ver_habitaciones','ver_tareas','registrar_movimientos_caja'
      )
      when r.role = 'limpieza' then p.key in (
        'ver_reservas','administrar_housekeeping','ver_housekeeping','iniciar_limpieza','finalizar_limpieza','ver_tareas','ver_habitaciones'
      )
      when r.role = 'mantenimiento' then p.key in (
        'administrar_mantenimiento','ver_mantenimiento','crear_incidencias','editar_incidencias','cerrar_incidencias','ver_habitaciones','ver_tareas'
      )
      when r.role = 'contador' then p.key in (
        'ver_resultados','ver_comisiones','ver_reportes','exportar_informacion','acceder_prefacturacion',
        'ver_gastos','ver_alojamientos','ver_propietarios','ver_datos_bancarios',
        'crear_prefacturacion','editar_prefacturacion','anular_prefacturacion','administrar_configuracion_fiscal'
      )
      when r.role = 'propietario' then p.key in ('ver_resultados','ver_reportes','ver_alojamientos','editar_gastos')
      else false
    end
  from (values ('admin'),('gerencia'),('encargado'),('recepcion'),('limpieza'),('mantenimiento'),('contador'),('propietario')) as r(role)
  cross join public.permissions_catalog p
  on conflict (tenant_id, role, permission_key) do nothing;
  return new;
end;
$$;

-- ────────────────────────────────────────────────────────────────
-- 3) BACKFILL — mismos defaults para tenants que ya existían.
-- on conflict do nothing: si un admin ya tocó la grilla de un tenant,
-- esto solo agrega las claves NUEVAS que todavía no tienen fila; no
-- pisa ninguna configuración existente.
-- ────────────────────────────────────────────────────────────────
insert into public.role_permissions (tenant_id, role, permission_key, allowed)
select t.id, r.role, p.key,
  case
    when r.role = 'admin' then true
    when r.role = 'gerencia' then p.key <> 'administrar_usuarios'
    when r.role = 'encargado' then p.key in (
      'ver_reservas','crear_reservas','editar_reservas','checkin','checkout','registrar_cobros','registrar_gastos',
      'ver_caja','abrir_caja','cerrar_caja','administrar_habitaciones','administrar_housekeeping','administrar_mantenimiento','ver_reportes',
      'ver_alojamientos','editar_alojamientos','ver_propietarios','ver_huespedes','crear_huespedes','editar_huespedes',
      'ver_tareas','crear_tareas','editar_tareas','asignar_tareas','ver_habitaciones','administrar_tipos_habitacion',
      'ver_cuenta_huesped','registrar_cargos','registrar_pagos','ver_housekeeping','iniciar_limpieza','finalizar_limpieza','inspeccionar_limpieza',
      'ver_mantenimiento','crear_incidencias','editar_incidencias','cerrar_incidencias','registrar_movimientos_caja','ver_gastos','editar_gastos'
    )
    when r.role = 'recepcion' then p.key in (
      'ver_reservas','crear_reservas','editar_reservas','checkin','checkout','registrar_cobros','ver_caja','abrir_caja','cerrar_caja',
      'ver_alojamientos','ver_huespedes','crear_huespedes','editar_huespedes','ver_cuenta_huesped','registrar_cargos','registrar_pagos',
      'ver_habitaciones','ver_tareas','registrar_movimientos_caja'
    )
    when r.role = 'limpieza' then p.key in (
      'ver_reservas','administrar_housekeeping','ver_housekeeping','iniciar_limpieza','finalizar_limpieza','ver_tareas','ver_habitaciones'
    )
    when r.role = 'mantenimiento' then p.key in (
      'administrar_mantenimiento','ver_mantenimiento','crear_incidencias','editar_incidencias','cerrar_incidencias','ver_habitaciones','ver_tareas'
    )
    when r.role = 'contador' then p.key in (
      'ver_resultados','ver_comisiones','ver_reportes','exportar_informacion','acceder_prefacturacion',
      'ver_gastos','ver_alojamientos','ver_propietarios','ver_datos_bancarios',
      'crear_prefacturacion','editar_prefacturacion','anular_prefacturacion','administrar_configuracion_fiscal'
    )
    when r.role = 'propietario' then p.key in ('ver_resultados','ver_reportes','ver_alojamientos')
    else false
  end
from public.tenants t
cross join (values ('admin'),('gerencia'),('encargado'),('recepcion'),('limpieza'),('mantenimiento'),('contador'),('propietario')) as r(role)
cross join public.permissions_catalog p
on conflict (tenant_id, role, permission_key) do nothing;

-- ────────────────────────────────────────────────────────────────
-- 4) VÍNCULO propiedad ↔ usuario "propietario": para que ese rol vea
-- solo sus propios alojamientos/reservas, no los de todo el tenant.
-- ────────────────────────────────────────────────────────────────
alter table public.profiles add column if not exists owner_id uuid references public.owners(id);

comment on column public.profiles.owner_id is 'Solo se usa cuando role=propietario: a qué fila de owners corresponde este usuario, para filtrar sus datos por RLS.';

create or replace function public.current_owner_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select owner_id from public.profiles where id = auth.uid()
$$;

-- ────────────────────────────────────────────────────────────────
-- 5) PROPERTIES — dueño de esta migración: el módulo del hallazgo crítico.
-- ────────────────────────────────────────────────────────────────
drop policy if exists "properties_select_own_tenant" on public.properties;
create policy "properties_select_own_tenant" on public.properties
  for select using (
    tenant_id = public.current_tenant_id()
    and (
      public.current_owner_id() is null
      or propietario_id = public.current_owner_id()
    )
  );

alter policy "properties_insert_own_tenant" on public.properties
  with check (tenant_id = public.current_tenant_id() and public.has_permission('crear_alojamientos'));

alter policy "properties_update_own_tenant" on public.properties
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('editar_alojamientos'));

alter policy "properties_delete_own_tenant" on public.properties
  using (tenant_id = public.current_tenant_id() and public.has_permission('eliminar_alojamientos'));

-- ────────────────────────────────────────────────────────────────
-- 6) OWNERS
-- ────────────────────────────────────────────────────────────────
alter policy "owners_insert_own_tenant" on public.owners
  with check (tenant_id = public.current_tenant_id() and public.has_permission('crear_propietarios'));

alter policy "owners_update_own_tenant" on public.owners
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('editar_propietarios'));

alter policy "owners_delete_own_tenant" on public.owners
  using (tenant_id = public.current_tenant_id() and public.has_permission('eliminar_propietarios'));

-- ────────────────────────────────────────────────────────────────
-- 7) GUESTS
-- ────────────────────────────────────────────────────────────────
alter policy "guests_insert_own_tenant" on public.guests
  with check (tenant_id = public.current_tenant_id() and public.has_permission('crear_huespedes'));

alter policy "guests_update_own_tenant" on public.guests
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('editar_huespedes'));

alter policy "guests_delete_own_tenant" on public.guests
  using (tenant_id = public.current_tenant_id() and public.has_permission('eliminar_huespedes'));

-- ────────────────────────────────────────────────────────────────
-- 8) RESERVATIONS — 0010 ya dejó insert/update protegidos por permiso,
-- y el delete reservado a is_admin(). Ahora que "eliminar_reservas"
-- existe como permiso propio en el catálogo, se lo habilita como vía
-- alternativa a is_admin() (para roles como "gerencia" que no son
-- admin pero sí deberían poder borrar una reserva mal cargada).
-- ────────────────────────────────────────────────────────────────
alter policy "reservations_delete_own_tenant" on public.reservations
  using (tenant_id = public.current_tenant_id() and (public.is_admin() or public.has_permission('eliminar_reservas')));

-- Un usuario "propietario" solo ve las reservas de SUS alojamientos,
-- igual que en properties (mismo criterio: current_owner_id() null
-- para cualquier otro rol = sin cambio de comportamiento).
drop policy if exists "reservations_select_own_tenant" on public.reservations;
create policy "reservations_select_own_tenant" on public.reservations
  for select using (
    tenant_id = public.current_tenant_id()
    and (
      public.current_owner_id() is null
      or propiedad_id in (select id from public.properties where propietario_id = public.current_owner_id())
    )
  );

-- ────────────────────────────────────────────────────────────────
-- 9) EXPENSES — 0010 solo había cubierto el insert.
-- ────────────────────────────────────────────────────────────────
alter policy "expenses_update_own_tenant" on public.expenses
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('editar_gastos'));

alter policy "expenses_delete_own_tenant" on public.expenses
  using (tenant_id = public.current_tenant_id() and public.has_permission('eliminar_gastos'));

-- ────────────────────────────────────────────────────────────────
-- 10) TASKS
-- ────────────────────────────────────────────────────────────────
alter policy "tasks_insert_own_tenant" on public.tasks
  with check (tenant_id = public.current_tenant_id() and public.has_permission('crear_tareas'));

alter policy "tasks_update_own_tenant" on public.tasks
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and (public.has_permission('editar_tareas') or public.has_permission('asignar_tareas')));

alter policy "tasks_delete_own_tenant" on public.tasks
  using (tenant_id = public.current_tenant_id() and public.has_permission('eliminar_tareas'));

-- ────────────────────────────────────────────────────────────────
-- 11) ROOM_TYPES / ROOMS
-- ────────────────────────────────────────────────────────────────
alter policy "room_types_insert_own_tenant" on public.room_types
  with check (tenant_id = public.current_tenant_id() and public.has_permission('administrar_tipos_habitacion'));

alter policy "room_types_update_own_tenant" on public.room_types
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('administrar_tipos_habitacion'));

alter policy "room_types_delete_own_tenant" on public.room_types
  using (tenant_id = public.current_tenant_id() and public.has_permission('administrar_tipos_habitacion'));

alter policy "rooms_insert_own_tenant" on public.rooms
  with check (tenant_id = public.current_tenant_id() and public.has_permission('administrar_habitaciones'));

alter policy "rooms_update_own_tenant" on public.rooms
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('administrar_habitaciones'));

alter policy "rooms_delete_own_tenant" on public.rooms
  using (tenant_id = public.current_tenant_id() and public.has_permission('administrar_habitaciones'));

-- ────────────────────────────────────────────────────────────────
-- 12) STAYS — check-in/check-out/cuenta del huésped.
-- Igual que "cancelar_reservas" en 0010: RLS no puede distinguir un
-- UPDATE de check-in de uno de "editar notas", así que el UPDATE
-- exige cualquiera de los permisos relacionados con la operativa de
-- estadías. El insert (abrir una estadía) exige "checkin" tal cual
-- ya se llama esa clave en el catálogo.
-- ────────────────────────────────────────────────────────────────
alter policy "stays_insert_own_tenant" on public.stays
  with check (tenant_id = public.current_tenant_id() and public.has_permission('checkin'));

alter policy "stays_update_own_tenant" on public.stays
  using (tenant_id = public.current_tenant_id())
  with check (
    tenant_id = public.current_tenant_id()
    and (
      public.has_permission('checkin') or public.has_permission('checkout')
      or public.has_permission('registrar_cargos') or public.has_permission('registrar_pagos')
      or public.has_permission('anular_movimientos')
    )
  );

alter policy "stays_delete_own_tenant" on public.stays
  using (tenant_id = public.current_tenant_id() and public.is_admin());

-- ────────────────────────────────────────────────────────────────
-- 13) HK_TASKS
-- ────────────────────────────────────────────────────────────────
alter policy "hk_tasks_insert_own_tenant" on public.hk_tasks
  with check (tenant_id = public.current_tenant_id() and (public.has_permission('administrar_housekeeping') or public.has_permission('iniciar_limpieza')));

alter policy "hk_tasks_update_own_tenant" on public.hk_tasks
  using (tenant_id = public.current_tenant_id())
  with check (
    tenant_id = public.current_tenant_id()
    and (public.has_permission('administrar_housekeeping') or public.has_permission('iniciar_limpieza') or public.has_permission('finalizar_limpieza') or public.has_permission('inspeccionar_limpieza'))
  );

alter policy "hk_tasks_delete_own_tenant" on public.hk_tasks
  using (tenant_id = public.current_tenant_id() and public.has_permission('administrar_housekeeping'));

-- ────────────────────────────────────────────────────────────────
-- 14) MAINT_TICKETS
-- ────────────────────────────────────────────────────────────────
alter policy "maint_tickets_insert_own_tenant" on public.maint_tickets
  with check (tenant_id = public.current_tenant_id() and (public.has_permission('administrar_mantenimiento') or public.has_permission('crear_incidencias')));

alter policy "maint_tickets_update_own_tenant" on public.maint_tickets
  using (tenant_id = public.current_tenant_id())
  with check (
    tenant_id = public.current_tenant_id()
    and (public.has_permission('administrar_mantenimiento') or public.has_permission('editar_incidencias') or public.has_permission('cerrar_incidencias'))
  );

alter policy "maint_tickets_delete_own_tenant" on public.maint_tickets
  using (tenant_id = public.current_tenant_id() and public.has_permission('administrar_mantenimiento'));

-- ────────────────────────────────────────────────────────────────
-- 15) CASH_SESSIONS
-- ────────────────────────────────────────────────────────────────
alter policy "cash_sessions_insert_own_tenant" on public.cash_sessions
  with check (tenant_id = public.current_tenant_id() and public.has_permission('abrir_caja'));

alter policy "cash_sessions_update_own_tenant" on public.cash_sessions
  using (
    tenant_id = public.current_tenant_id()
    and (
      abierta = true
      or (public.has_permission('modificar_turno_cerrado') and public.is_admin())
    )
  )
  with check (
    tenant_id = public.current_tenant_id()
    and (public.has_permission('registrar_movimientos_caja') or public.has_permission('cerrar_caja'))
  );

alter policy "cash_sessions_delete_own_tenant" on public.cash_sessions
  using (tenant_id = public.current_tenant_id() and public.is_admin());

-- ────────────────────────────────────────────────────────────────
-- 16) BILLING_CONFIG / FACTURAS
-- ────────────────────────────────────────────────────────────────
alter policy "billing_config_insert_own_tenant" on public.billing_config
  with check (tenant_id = public.current_tenant_id() and public.has_permission('administrar_configuracion_fiscal'));

alter policy "billing_config_update_own_tenant" on public.billing_config
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('administrar_configuracion_fiscal'));

alter policy "facturas_insert_own_tenant" on public.facturas
  with check (tenant_id = public.current_tenant_id() and public.has_permission('crear_prefacturacion'));

alter policy "facturas_update_own_tenant" on public.facturas
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('editar_prefacturacion'));

alter policy "facturas_delete_own_tenant" on public.facturas
  using (tenant_id = public.current_tenant_id() and public.has_permission('anular_prefacturacion'));
