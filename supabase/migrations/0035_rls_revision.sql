-- ════════════════════════════════════════════════════════════════
-- 0035 — REVISIÓN DE RLS de las tablas tocadas en esta etapa
-- (reservations, properties, hk_tasks, maint_tickets, cash_sessions,
-- payment_operations). Resultado, leído en vivo con pg_policies antes
-- de escribir esto (no supuesto):
--
--   - Las 5 tablas preexistentes ya tenían RLS habilitada y CADA
--     política ya filtraba por "tenant_id = current_tenant_id()"
--     (más permisos granulares en insert/update/delete desde 0019).
--     Esto cubre automáticamente las columnas nuevas de 0028/0029/0030
--     porque el filtro es por FILA, no por columna — no hacía falta
--     ningún cambio de política ahí.
--   - payment_operations (0033) quedó con RLS habilitada y CERO
--     políticas para "authenticated": solo la tocan las funciones
--     security definer de 0034. Ya es el estado más restrictivo
--     posible, no requiere ajuste.
--
-- GAP REAL encontrado (y corregido acá): las políticas RLS de
-- hk_tasks/maint_tickets solo validan que la FILA sea del tenant
-- correcto — no validan que el propiedad_id/reserva_id NUEVOS (0029)
-- apunten a un alojamiento/reserva del MISMO tenant. Un FK normal no
-- puede expresar "misma fila Y mismo tenant" a la vez, así que un
-- update directo a la tabla (con permiso de housekeeping/mantenimiento
-- pero sin pasar por las RPC) podría en teoría vincular una tarea con
-- un alojamiento de OTRA cuenta. Se cierra con un trigger de
-- validación, mismo espíritu que check_reservation_overlap.
-- ════════════════════════════════════════════════════════════════

create or replace function public.check_propiedad_reserva_same_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.propiedad_id is not null and not exists (
    select 1 from public.properties p where p.id = new.propiedad_id and p.tenant_id = new.tenant_id
  ) then
    raise exception 'El alojamiento indicado no pertenece a esta cuenta';
  end if;

  if tg_table_name = 'hk_tasks' and new.reserva_id is not null and not exists (
    select 1 from public.reservations r where r.id = new.reserva_id and r.tenant_id = new.tenant_id
  ) then
    raise exception 'La reserva indicada no pertenece a esta cuenta';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_hk_tasks_check_tenant on public.hk_tasks;
create trigger trg_hk_tasks_check_tenant
  before insert or update of propiedad_id, reserva_id, tenant_id
  on public.hk_tasks
  for each row
  execute function public.check_propiedad_reserva_same_tenant();

drop trigger if exists trg_maint_tickets_check_tenant on public.maint_tickets;
create trigger trg_maint_tickets_check_tenant
  before insert or update of propiedad_id, tenant_id
  on public.maint_tickets
  for each row
  execute function public.check_propiedad_reserva_same_tenant();

-- Nota, a propósito NO tocado en esta migración: el mismo patrón de
-- gap (FK sin validación de tenant) ya existía antes de esta etapa en
-- reservations.propiedad_id -> properties, y no es parte del alcance
-- aprobado (que es no tocar nada del comportamiento existente de
-- Modo Administrador ni de Reservas fuera de lo pedido). Queda
-- documentado como hallazgo para una futura revisión de seguridad
-- general, no se corrige acá.

-- ── Verificación ──
-- select tgname from pg_trigger where tgrelid = 'public.hk_tasks'::regclass and not tgisinternal;
-- select tgname from pg_trigger where tgrelid = 'public.maint_tickets'::regclass and not tgisinternal;
-- Intentar (en local, con datos de prueba de DOS tenants distintos) vincular
-- una hk_task de un tenant a una propiedad de otro tenant -> debe fallar.

-- ── Rollback ──
-- drop trigger if exists trg_hk_tasks_check_tenant on public.hk_tasks;
-- drop trigger if exists trg_maint_tickets_check_tenant on public.maint_tickets;
-- drop function if exists public.check_propiedad_reserva_same_tenant();
