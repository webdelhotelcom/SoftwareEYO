-- ════════════════════════════════════════════════════════════════
-- 0046 — Eliminar una apertura de Caja (Modo Propietario) por completo,
-- a pedido del usuario para poder borrar los turnos de prueba que cargó.
--
-- Mismo patrón de seguridad que corregir_caja_propietario/cerrar_caja_
-- administrativo (0040): exige has_permission('administrar_operadores_caja')
-- (el mismo permiso que ya gatea "Corregir" y "Cierre administrativo")
-- Y el PIN de un operador activo — dos verificaciones independientes,
-- no una sola. Solo se puede eliminar una caja YA CERRADA (mismo
-- criterio que "Corregir": una caja abierta se cierra primero).
--
-- Efectos, en orden:
--   1. Recalcula reservations.sena_parcial de cualquier reserva que
--      tuviera cobros en esta caja, ANTES de borrar los movimientos —
--      recalculado desde cero sumando lo que quede en payment_operations
--      (no restando a mano), para no arrastrar errores de signo con
--      anulaciones/devoluciones ya registradas.
--   2. Borra cash_audit_log de esta sesión (créditos internos "correc-
--      ción"/"anulación" de ESTA caja — sin sentido sin su caja padre).
--   3. Borra payment_operations de esta sesión (ledger de idempotencia).
--   4. Borra la fila de cash_sessions — el trigger genérico de
--      auditoría (trg_audit_cash_sessions, desde 0011/0017) deja un
--      registro DELETE en el audit_log general automáticamente, así
--      que la eliminación en sí queda igual de trazable en Auditoría
--      que cualquier otra baja del sistema.
-- ════════════════════════════════════════════════════════════════

create or replace function public.eliminar_caja_propietario(
  p_session_id uuid, p_operator_id uuid, p_pin text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_sesion public.cash_sessions;
  v_check jsonb;
  v_reserva_id uuid;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('administrar_operadores_caja') then
    raise exception 'No tenés permiso para eliminar una Caja';
  end if;

  select * into v_sesion from public.cash_sessions
  where id = p_session_id and tenant_id = v_tenant and grupo = 'hostal'
  for update;
  if not found then raise exception 'Caja no encontrada'; end if;
  if v_sesion.abierta then
    raise exception 'No se puede eliminar una Caja abierta. Cerrala primero.';
  end if;

  v_check := public._verificar_pin_operador(p_operator_id, p_pin);
  if not (v_check->>'ok')::boolean then
    return v_check;
  end if;

  -- Recalcular sena_parcial de las reservas afectadas, ANTES de borrar
  -- los movimientos que las respaldan.
  for v_reserva_id in
    select distinct reserva_id from public.payment_operations
    where cash_session_id = p_session_id and reserva_id is not null
  loop
    update public.reservations
    set sena_parcial = coalesce((
      select sum(importe) from public.payment_operations
      where reserva_id = v_reserva_id and cash_session_id is distinct from p_session_id
    ), 0)
    where id = v_reserva_id;
  end loop;

  delete from public.cash_audit_log where cash_session_id = p_session_id;
  delete from public.payment_operations where cash_session_id = p_session_id;
  delete from public.cash_sessions where id = p_session_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.eliminar_caja_propietario(uuid,uuid,text) from public;
grant execute on function public.eliminar_caja_propietario(uuid,uuid,text) to authenticated;

-- ── Verificación ──
-- select proname from pg_proc where proname='eliminar_caja_propietario'; -- 1 fila
-- Después de aplicar, probar en la app real: Caja → Historial → abrir
-- una caja cerrada de prueba → Eliminar → confirmar → elegir operador +
-- PIN → Confirmar. Debe desaparecer del historial, y en Auditoría debe
-- quedar una fila "... eliminó turno de caja".

-- ── Rollback ──
-- drop function if exists public.eliminar_caja_propietario(uuid,uuid,text);
