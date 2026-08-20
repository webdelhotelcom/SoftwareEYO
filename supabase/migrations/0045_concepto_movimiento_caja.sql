-- ════════════════════════════════════════════════════════════════
-- 0045 — Agrega "concepto" (texto libre, ej. nombre de quién pagó) a los
-- movimientos manuales de Caja en Modo Propietario. El modal ya tenía el
-- campo en pantalla (input #cmp-concepto) pero nunca se mandaba al
-- servidor ni se guardaba: registrar_movimiento_caja() no tenía parámetro
-- para recibirlo, así que se perdía apenas se cerraba el modal.
--
-- Se guarda solo en el jsonb cash_sessions.movimientos (igual que ya
-- pasa con metodo_pago, que tampoco vive en payment_operations) — no en
-- payment_operations, para no romper el patrón ya establecido de esa
-- tabla como ledger de idempotencia, no de despliegue de UI.
--
-- Se agrega como un parámetro NUEVO al final, con default null, así que
-- reutiliza la MISMA función (no crea un overload): los dos llamadores
-- internos que la invocan posicionalmente con 9 argumentos (registrar_checkin/
-- registrar_checkout_propietario en 0034, y el trigger de checkout en 0041)
-- siguen funcionando sin cambios — Postgres permite omitir parámetros
-- finales que tienen default.
-- ════════════════════════════════════════════════════════════════

drop function if exists public.registrar_movimiento_caja(uuid,uuid,uuid,numeric,text,text,uuid,uuid,uuid);

create or replace function public.registrar_movimiento_caja(
  p_reserva_id uuid,
  p_propiedad_id uuid,
  p_huesped_id uuid,
  p_importe numeric,
  p_tipo text,
  p_metodo text,
  p_payment_operation_id uuid,
  p_sesion_id uuid default null,
  p_reversa_de uuid default null,
  p_concepto text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_sesion public.cash_sessions;
  v_orig public.payment_operations;
  v_op public.payment_operations;
  v_importe_final numeric;
  v_saldo numeric;
  v_sena_actual numeric;
  v_sena_nueva numeric;
  v_mov jsonb;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Usuario no autenticado o inactivo';
  end if;
  if p_payment_operation_id is null then
    raise exception 'Falta identificador de operación';
  end if;
  if p_tipo not in ('sena','pago-parcial','pago-final','cobro-checkin','cobro-checkout',
                     'anulacion','devolucion','ingreso-manual','egreso-manual') then
    raise exception 'Tipo de movimiento inválido: %', p_tipo;
  end if;
  -- metodo_pago server-side, lista cerrada — nunca texto libre del
  -- navegador (calcular_expected_cash de 0040 depende de este valor).
  -- 'tarjeta' queda solo por compatibilidad con datos ya guardados.
  if p_metodo is not null and p_metodo not in ('efectivo','transferencia','tarjeta','pos','otro') then
    raise exception 'Método de pago inválido: %', p_metodo;
  end if;

  if p_tipo in ('anulacion','devolucion') then
    if not public.has_permission('anular_cobros') then
      raise exception 'No tenés permiso para anular cobros';
    end if;
    if p_reversa_de is null then
      raise exception 'Una anulación requiere indicar la operación original';
    end if;
    select * into v_orig from public.payment_operations
    where payment_operation_id = p_reversa_de and tenant_id = v_tenant;
    if not found then
      raise exception 'Operación original no encontrada o no pertenece a esta cuenta';
    end if;
    if v_orig.tipo in ('anulacion','devolucion') then
      raise exception 'No se puede anular una anulación';
    end if;
    if p_reserva_id is not null and v_orig.reserva_id is distinct from p_reserva_id then
      raise exception 'La operación original pertenece a otra reserva';
    end if;
    if exists (select 1 from public.payment_operations where reversa_de = p_reversa_de) then
      raise exception 'Esa operación ya fue anulada';
    end if;
    -- El importe de la anulación NO lo elige el navegador: se calcula acá.
    v_importe_final := -v_orig.importe;
  else
    if not public.has_permission('registrar_cobros') then
      raise exception 'No tenés permiso para registrar cobros';
    end if;
    if p_importe is null or p_importe <= 0 then
      raise exception 'El importe debe ser mayor a cero';
    end if;
    -- El signo lo decide el servidor según el tipo, nunca el navegador:
    -- ingresos (incluido ingreso-manual) quedan positivos; egreso-manual
    -- se guarda negativo, así sumar movimientos[].importe directo ya da
    -- el efecto neto real (lo usa calcular_expected_cash en 0040).
    v_importe_final := case when p_tipo = 'egreso-manual' then -p_importe else p_importe end;
  end if;

  -- Resolver y bloquear la sesión de Caja.
  if p_sesion_id is null then
    select * into v_sesion from public.cash_sessions
    where tenant_id = v_tenant and abierta = true
    order by created_at desc limit 1
    for update;
  else
    select * into v_sesion from public.cash_sessions
    where id = p_sesion_id and tenant_id = v_tenant
    for update;
  end if;
  if not found then
    raise exception 'No hay una sesión de Caja abierta para esta cuenta';
  end if;
  if not v_sesion.abierta then
    raise exception 'La sesión de Caja no está abierta';
  end if;

  -- Reserva/alojamiento/huésped deben corresponder entre sí, mismo tenant.
  if p_reserva_id is not null then
    if not exists (
      select 1 from public.reservations r
      where r.id = p_reserva_id and r.tenant_id = v_tenant
        and (p_propiedad_id is null or r.propiedad_id = p_propiedad_id)
        and (p_huesped_id is null or r.guest_id = p_huesped_id)
    ) then
      raise exception 'La reserva, el alojamiento y/o el huésped no corresponden entre sí en esta cuenta';
    end if;
  end if;

  -- Sobrepago: solo para cobros ligados a una reserva (no anulaciones,
  -- no movimientos manuales, que nunca tienen p_reserva_id), tolerancia
  -- de redondeo ±1 porque calcRes() usa Math.round en varios pasos.
  if p_tipo not in ('anulacion','devolucion') and p_reserva_id is not null then
    v_saldo := public.saldo_pendiente_reserva(p_reserva_id);
    if v_importe_final > v_saldo + 1 then
      raise exception 'El importe (%) supera el saldo pendiente de la reserva (%)', v_importe_final, v_saldo;
    end if;
  end if;

  -- Idempotencia GLOBAL real: primary key a nivel de motor. Si dos
  -- requests simultáneas mandan el mismo payment_operation_id, solo
  -- una inserta; la otra ve "not found" y devuelve el resultado ya
  -- guardado sin tocar sena_parcial ni el jsonb una segunda vez.
  insert into public.payment_operations
    (payment_operation_id, tenant_id, reserva_id, cash_session_id, tipo, importe, reversa_de, created_by)
  values
    (p_payment_operation_id, v_tenant, p_reserva_id, v_sesion.id, p_tipo, v_importe_final, p_reversa_de, auth.uid())
  on conflict (payment_operation_id) do nothing
  returning * into v_op;

  if not found then
    -- Reintento: ya existía (en esta sesión o en cualquier otra del
    -- tenant — la clave es global). Se busca el movimiento ya
    -- guardado en cash_sessions y se devuelve tal cual.
    select m into v_mov
    from public.cash_sessions cs, jsonb_array_elements(cs.movimientos) m
    where cs.tenant_id = v_tenant
      and m->>'payment_operation_id' = p_payment_operation_id::text
    limit 1;
    return v_mov;
  end if;

  -- Operación genuinamente nueva: actualizar sena_parcial (sin bajar de cero).
  if p_reserva_id is not null then
    select coalesce(sena_parcial,0) into v_sena_actual
    from public.reservations where id = p_reserva_id for update;
    v_sena_nueva := v_sena_actual + v_importe_final;
    if v_sena_nueva < 0 then
      raise exception 'La operación dejaría el saldo de pagos por debajo de cero';
    end if;
    update public.reservations set sena_parcial = v_sena_nueva where id = p_reserva_id;
  end if;

  v_mov := jsonb_build_object(
    'payment_operation_id', p_payment_operation_id,
    'reversa_de', p_reversa_de,
    'reserva_id', p_reserva_id,
    'propiedad_id', p_propiedad_id,
    'huesped_id', p_huesped_id,
    'importe', v_importe_final,
    'tipo_movimiento', p_tipo,
    'metodo_pago', p_metodo,
    'concepto', p_concepto,
    'fecha_hora', now(),
    'usuario_responsable', auth.uid()
  );

  update public.cash_sessions
  set movimientos = coalesce(movimientos,'[]'::jsonb) || jsonb_build_array(v_mov)
  where id = v_sesion.id;

  if p_tipo not in ('anulacion','devolucion') and p_reserva_id is not null then
    perform public.intentar_finalizar_reserva(p_reserva_id);
  end if;

  return v_mov;
end;
$$;

revoke all on function public.registrar_movimiento_caja(uuid,uuid,uuid,numeric,text,text,uuid,uuid,uuid,text) from public;
grant execute on function public.registrar_movimiento_caja(uuid,uuid,uuid,numeric,text,text,uuid,uuid,uuid,text) to authenticated;

-- ── Verificación ──
-- select pg_get_function_identity_arguments(oid) from pg_proc
--   where proname='registrar_movimiento_caja'; -- debe haber UNA sola fila, con p_concepto al final
-- Después de aplicar, probar en la app real: Caja (Modo Propietario) →
-- Movimiento → cargar un ingreso con Concepto="Juan Pérez" → Registrar.
-- Debe aparecer "Juan Pérez" en Movimientos (Caja actual y en el
-- detalle del historial), no solo "ingreso-manual · efectivo".

-- ── Rollback ──
-- Volver a aplicar el CREATE OR REPLACE de 0042 tal cual estaba (sin
-- p_concepto), después de un DROP FUNCTION del de 10 argumentos.
