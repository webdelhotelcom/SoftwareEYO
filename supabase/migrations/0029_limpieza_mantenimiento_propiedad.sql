-- ════════════════════════════════════════════════════════════════
-- 0029 — LIMPIEZA (hk_tasks) Y MANTENIMIENTO (maint_tickets): agrega
-- la relación a Alojamientos/Reservas para Modo Propietario, SIN
-- tocar room_id (que sigue siendo lo que usa Modo Administrador,
-- sin ningún cambio). Columnas nuevas nullable — cero impacto en
-- las 0 filas que hoy tienen ambas tablas.
--
-- No se agregan fecha_inicio/fecha_fin: hk_tasks ya tiene "ts" (date,
-- la fecha de la tarea) y "created_at"/"updated_at" — se reutilizan.
-- Lo que sí falta y se agrega son los timestamps reales de cada etapa
-- del ciclo de limpieza (inicio real, fin real, revisión), que hoy no
-- existen como columnas propias.
--
-- Vocabulario de estado (ya en uso por Modo Administrador, se reutiliza
-- tal cual para Modo Propietario en la misma tabla/columna):
--   hk_tasks.estado:      pendiente → proceso → terminada → inspeccionada
--   maint_tickets.estado: abierta → cerrada
-- ════════════════════════════════════════════════════════════════

alter table public.hk_tasks
  add column if not exists propiedad_id uuid references public.properties(id),
  add column if not exists reserva_id uuid references public.reservations(id),
  add column if not exists grupo text,
  add column if not exists started_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists reviewed_at timestamptz;

alter table public.maint_tickets
  add column if not exists propiedad_id uuid references public.properties(id);

-- Anti-duplicados: como mucho UNA tarea automática de limpieza por
-- reserva, en toda la vida de esa reserva (no "por checkout" — en este
-- modelo una reserva hace checkout una sola vez). Cancelar esa tarea
-- NO habilita crear otra automática para la misma reserva; una tarea
-- manual sin reserva_id es el camino para ese caso administrativo.
create unique index if not exists hk_tasks_reserva_unica
  on public.hk_tasks (reserva_id) where reserva_id is not null;

-- Índices de performance para las consultas nuevas de Recepción/Habitaciones.
create index if not exists idx_reservations_prop_fechas
  on public.reservations (propiedad_id, checkin, checkout);
create index if not exists idx_reservations_grupo_estado
  on public.reservations (grupo, estado);
create index if not exists idx_hk_tasks_propiedad
  on public.hk_tasks (propiedad_id);
create index if not exists idx_hk_tasks_activas
  on public.hk_tasks (propiedad_id) where estado not in ('terminada','inspeccionada');
create index if not exists idx_maint_tickets_propiedad
  on public.maint_tickets (propiedad_id);
create index if not exists idx_maint_tickets_abiertas
  on public.maint_tickets (propiedad_id) where estado <> 'cerrada';

-- ── Verificación ──
-- select indexname from pg_indexes where tablename in ('hk_tasks','maint_tickets','reservations')
--   and indexname like 'idx_%' or indexname='hk_tasks_reserva_unica';
-- Debe devolver 6 filas nuevas. Y esto debe seguir dando 0 (nada se creó todavía):
-- select count(*) from public.hk_tasks where propiedad_id is not null;

-- ── Rollback ──
-- drop index if exists hk_tasks_reserva_unica;
-- drop index if exists idx_reservations_prop_fechas;
-- drop index if exists idx_reservations_grupo_estado;
-- drop index if exists idx_hk_tasks_propiedad;
-- drop index if exists idx_hk_tasks_activas;
-- drop index if exists idx_maint_tickets_propiedad;
-- drop index if exists idx_maint_tickets_abiertas;
-- alter table public.hk_tasks drop column if exists propiedad_id, drop column if exists reserva_id,
--   drop column if exists grupo, drop column if exists started_at, drop column if exists completed_at,
--   drop column if exists reviewed_at;
-- alter table public.maint_tickets drop column if exists propiedad_id;
