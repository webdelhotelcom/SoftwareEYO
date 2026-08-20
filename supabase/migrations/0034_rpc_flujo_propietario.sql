-- ════════════════════════════════════════════════════════════════
-- 0034 — RPC del flujo de Modo Propietario: check-in, check-out,
-- limpieza automática y pagos de Caja, todo seguro y transaccional.
--
-- Reutiliza el motor de permisos YA EXISTENTE del sistema (0002, 0009,
-- 0020) en vez de inventar uno paralelo: current_tenant_id() (ya
-- devuelve null si el usuario está inactivo), has_permission(key)
-- contra permissions_catalog/role_permissions. Las claves 'checkin',
-- 'checkout', 'registrar_cobros' y 'anular_cobros' ya existen en el
-- catálogo desde 0009 — no hace falta agregar ninguna.
-- ════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- registrar_checkin: check-in real. Solo desde sena-confirmada,
-- confirmada o checkin-pendiente. Idempotente.
-- ────────────────────────────────────────────────────────────────
create or replace function public.registrar_checkin(p_reserva_id uuid)
returns public.reservations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_res public.reservations;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Usuario no autenticado o inactivo';
  end if;
  if not public.has_permission('checkin') then
    raise exception 'No tenés permiso para hacer check-in';
  end if;

  select * into v_res from public.reservations
  where id = p_reserva_id and tenant_id = v_tenant
  for update;
  if not found then
    raise exception 'Reserva no encontrada o no pertenece a esta cuenta';
  end if;
  if v_res.grupo <> 'hostal' then
    raise exception 'Esta operación es solo para Modo Propietario';
  end if;
  if v_res.estado not in ('sena-confirmada','confirmada','checkin-pendiente') then
    raise exception 'Estado inválido para check-in: %', v_res.estado;
  end if;

  if v_res.checkin_real_at is not null then
    return v_res; -- idempotente: ya se hizo, no repite nada
  end if;

  update public.reservations
  set estado = 'alojado', checkin_real_at = now(), checkin_by = auth.uid()
  where id = p_reserva_id
  returning * into v_res;

  return v_res;
end;
$$;

revoke all on function public.registrar_checkin(uuid) from public;
grant execute on function public.registrar_checkin(uuid) to authenticated;

-- ────────────────────────────────────────────────────────────────
-- saldo_pendiente_reserva: réplica exacta, en el servidor, de la
-- fórmula que YA usa el frontend (calcRes().cobrado - senaParcial,
-- panel.html líneas 2952 / 3335-3336 / 3843). SIN NINGÚN GRANT: no
-- es invocable directo por ningún usuario, solo desde el interior de
-- otras funciones security definer (que corren como el dueño de este
-- objeto, y por lo tanto la pueden llamar igual pese al revoke).
-- ────────────────────────────────────────────────────────────────
create or replace function public.saldo_pendiente_reserva(p_reserva_id uuid)
returns numeric
language sql
stable
set search_path = public
as $$
  select greatest(
    (r.precio - coalesce(r.descuento,0)
       - case when r.tiene_comision_plat = 'si'
              then round(r.precio * coalesce(r.comision_plat_pct,0) / 100.0)
              else 0 end)
    - coalesce(r.sena_parcial,0)
  , 0)
  from public.reservations r where r.id = p_reserva_id
$$;

revoke all on function public.saldo_pendiente_reserva(uuid) from public;
revoke all on function public.saldo_pendiente_reserva(uuid) from authenticated;

-- ────────────────────────────────────────────────────────────────
-- intentar_finalizar_reserva: única vía para pasar a 'finalizada'.
-- Nunca decide con un número que mande el navegador. Sin grant,
-- igual que la anterior.
-- ────────────────────────────────────────────────────────────────
create or replace function public.intentar_finalizar_reserva(p_reserva_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res public.reservations;
  v_saldo numeric;
begin
  select * into v_res from public.reservations where id = p_reserva_id for update;
  if not found then return; end if;
  if v_res.estado <> 'checkout-realizado' then return; end if;

  v_saldo := public.saldo_pendiente_reserva(p_reserva_id);
  if v_saldo <= 0 then
    update public.reservations set estado = 'finalizada' where id = p_reserva_id;
  end if;
end;
$$;

revoke all on function public.intentar_finalizar_reserva(uuid) from public;
revoke all on function public.intentar_finalizar_reserva(uuid) from authenticated;

-- ────────────────────────────────────────────────────────────────
-- registrar_movimiento_caja: idempotencia real (payment_operations,
-- primary key), validación de tipo/importe, anulaciones que calculan
-- su propio importe inverso en el servidor, protección contra
-- sobrepago y contra sena_parcial negativo.
-- ────────────────────────────────────────────────────────────────
create or replace function public.registrar_movimiento_caja(
  p_reserva_id uuid,
  p_propiedad_id uuid,
  p_huesped_id uuid,
  p_importe numeric,
  p_tipo text,
  p_metodo text,
  p_payment_operation_id uuid,
  p_sesion_id uuid default null,
  p_reversa_de uuid default null
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
  if p_tipo not in ('sena','pago-parcial','pago-final','cobro-checkin','cobro-checkout','anulacion','devolucion') then
    raise exception 'Tipo de movimiento inválido: %', p_tipo;
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
    v_importe_final := p_importe;
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

  -- Sobrepago: solo para cobros (no anulaciones), tolerancia de
  -- redondeo ±1 porque calcRes() usa Math.round en varios pasos.
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

revoke all on function public.registrar_movimiento_caja(uuid,uuid,uuid,numeric,text,text,uuid,uuid,uuid) from public;
grant execute on function public.registrar_movimiento_caja(uuid,uuid,uuid,numeric,text,text,uuid,uuid,uuid) to authenticated;

-- ────────────────────────────────────────────────────────────────
-- registrar_checkout_propietario: una sola función transaccional —
-- checkout + tarea de limpieza + (si hay cobro) el movimiento de
-- Caja, todo o nada. p_cobro es opcional: sin cobro, igual completa
-- el checkout y la limpieza.
-- ────────────────────────────────────────────────────────────────
create or replace function public.registrar_checkout_propietario(
  p_reserva_id uuid,
  p_cobro jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_res public.reservations;
  v_mov jsonb;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Usuario no autenticado o inactivo';
  end if;
  if not public.has_permission('checkout') then
    raise exception 'No tenés permiso para hacer check-out';
  end if;

  select * into v_res from public.reservations
  where id = p_reserva_id and tenant_id = v_tenant
  for update;
  if not found then
    raise exception 'Reserva no encontrada o no pertenece a esta cuenta';
  end if;
  if v_res.grupo <> 'hostal' then
    raise exception 'Esta operación es solo para Modo Propietario';
  end if;

  if v_res.checkout_real_at is null then
    if v_res.estado <> 'alojado' then
      raise exception 'Estado inválido para check-out: %', v_res.estado;
    end if;

    update public.reservations
    set estado = 'checkout-realizado', checkout_real_at = now(), checkout_by = auth.uid()
    where id = p_reserva_id;

    -- Única tarea automática por reserva en toda su vida (índice único
    -- parcial de 0029 + este "where not exists" son dos capas independientes).
    insert into public.hk_tasks (tenant_id, propiedad_id, reserva_id, grupo, estado, ts, created_at)
    select v_res.tenant_id, v_res.propiedad_id, p_reserva_id, 'hostal', 'pendiente', current_date, now()
    where not exists (select 1 from public.hk_tasks h where h.reserva_id = p_reserva_id);
  end if;

  if p_cobro is not null then
    v_mov := public.registrar_movimiento_caja(
      p_reserva_id            => p_reserva_id,
      p_propiedad_id          => v_res.propiedad_id,
      p_huesped_id            => v_res.guest_id,
      p_importe               => (p_cobro->>'importe')::numeric,
      p_tipo                  => coalesce(p_cobro->>'tipo','cobro-checkout'),
      p_metodo                => p_cobro->>'metodo',
      p_payment_operation_id  => (p_cobro->>'payment_operation_id')::uuid,
      p_sesion_id             => nullif(p_cobro->>'sesion_id','')::uuid,
      p_reversa_de            => nullif(p_cobro->>'reversa_de','')::uuid
    );
  end if;

  perform public.intentar_finalizar_reserva(p_reserva_id);

  select * into v_res from public.reservations where id = p_reserva_id;
  return jsonb_build_object('reserva', to_jsonb(v_res), 'movimiento', v_mov);
end;
$$;

revoke all on function public.registrar_checkout_propietario(uuid, jsonb) from public;
grant execute on function public.registrar_checkout_propietario(uuid, jsonb) to authenticated;

-- ── Pruebas SQL comentadas (correr a mano en local, NUNCA contra
--    producción, con datos de prueba propios) ──
--
-- (a) dos movimientos distintos quedan ambos en el array:
--   select registrar_movimiento_caja(null,null,null,1000,'sena','efectivo',gen_random_uuid(),null,null);
--   select registrar_movimiento_caja(null,null,null,2000,'sena','efectivo',gen_random_uuid(),null,null);
--   select jsonb_array_length(movimientos) from cash_sessions where abierta limit 1; -- debe ser 2
--
-- (b) saldo_pendiente_reserva() contra calcRes() del frontend para
--     varias reservas reales representativas — comparar a mano.
--
-- (c) idempotencia real: correr DOS VECES la misma llamada con el
--     MISMO payment_operation_id -> debe devolver el mismo movimiento
--     las dos veces, sena_parcial solo se mueve una vez.
--
-- (d) anulación con importe positivo elegido a mano en p_importe:
--     confirmar que la función lo ignora y usa -importe_original.

-- ── Verificación ──
-- select proname, prosecdef from pg_proc where proname in
--   ('registrar_checkin','saldo_pendiente_reserva','intentar_finalizar_reserva',
--    'registrar_movimiento_caja','registrar_checkout_propietario');
-- select routine_name, grantee, privilege_type from information_schema.routine_privileges
--   where routine_name in ('saldo_pendiente_reserva','intentar_finalizar_reserva');
--   -- NO debe aparecer 'authenticated' ni 'PUBLIC' en ninguna fila.

-- ── Rollback ──
-- drop function if exists public.registrar_checkout_propietario(uuid, jsonb);
-- drop function if exists public.registrar_movimiento_caja(uuid,uuid,uuid,numeric,text,text,uuid,uuid,uuid);
-- drop function if exists public.intentar_finalizar_reserva(uuid);
-- drop function if exists public.saldo_pendiente_reserva(uuid);
-- drop function if exists public.registrar_checkin(uuid);
