-- ════════════════════════════════════════════════════════════════
-- 0040 — RPC de Caja profesional (Modo Propietario): operadores, PIN,
-- apertura/cierre/cierre administrativo, corrección, anulación en
-- caja cerrada. Todas security definer, set search_path=public,
-- resuelven tenant con current_tenant_id(). Ninguna de las que
-- verifican PIN lanza excepción por "PIN incorrecto" — el update de
-- intentos_fallidos tiene que quedar grabado pase lo que pase después.
-- ════════════════════════════════════════════════════════════════

-- pgcrypto en Supabase suele vivir en el esquema "extensions", no en
-- "public" — un search_path de solo "public" no encuentra crypt()/
-- gen_salt() y CREATE FUNCTION falla de entrada (a diferencia de
-- plpgsql, una función "language sql" valida las funciones que
-- referencia ya en el CREATE, no recién al primer uso). Se incluyen
-- ambos esquemas para que funcione sin importar dónde quedó instalada.
create or replace function public.hash_pin(p_pin text)
returns text
language sql
stable
set search_path = public, extensions
as $$
  select crypt(p_pin, gen_salt('bf'))
$$;
revoke all on function public.hash_pin(text) from public;
revoke all on function public.hash_pin(text) from authenticated;

-- ────────────────────────────────────────────────────────────────
-- Gestión de operadores. Alta/PIN/activación exigen
-- administrar_operadores_caja. Ninguna vía directa a la tabla (0036
-- no tiene policies de insert/update) — solo estas RPC.
-- ────────────────────────────────────────────────────────────────
create or replace function public.crear_operador_caja(p_nombre text, p_pin text, p_notas text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_id uuid;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('administrar_operadores_caja') then
    raise exception 'No tenés permiso para administrar operadores de Caja';
  end if;
  if p_nombre is null or trim(p_nombre) = '' then raise exception 'El nombre es obligatorio'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'El PIN debe ser de 4 dígitos'; end if;

  insert into public.cash_operators (tenant_id, nombre, notas, created_by, updated_by)
  values (v_tenant, trim(p_nombre), p_notas, auth.uid(), auth.uid())
  returning id into v_id;

  insert into public.cash_operator_secrets (operator_id, tenant_id, pin_hash)
  values (v_id, v_tenant, public.hash_pin(p_pin));

  insert into public.cash_audit_log (tenant_id, operator_id, user_id, accion)
  values (v_tenant, v_id, auth.uid(), 'operador_creado');

  return v_id;
end;
$$;
revoke all on function public.crear_operador_caja(text,text,text) from public;
grant execute on function public.crear_operador_caja(text,text,text) to authenticated;

create or replace function public.cambiar_pin_operador(p_operator_id uuid, p_pin_nuevo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('administrar_operadores_caja') then
    raise exception 'No tenés permiso para administrar operadores de Caja';
  end if;
  if p_pin_nuevo !~ '^[0-9]{4}$' then raise exception 'El PIN debe ser de 4 dígitos'; end if;
  if not exists (select 1 from public.cash_operators where id=p_operator_id and tenant_id=v_tenant) then
    raise exception 'Operador no encontrado';
  end if;

  update public.cash_operator_secrets set pin_hash = public.hash_pin(p_pin_nuevo) where operator_id = p_operator_id;
  update public.cash_operators set intentos_fallidos=0, bloqueado_hasta=null, updated_by=auth.uid() where id = p_operator_id;

  -- Nunca se guarda el PIN ni el hash en la auditoría — solo que pasó.
  insert into public.cash_audit_log (tenant_id, operator_id, user_id, accion)
  values (v_tenant, p_operator_id, auth.uid(), 'pin_cambiado');
end;
$$;
revoke all on function public.cambiar_pin_operador(uuid,text) from public;
grant execute on function public.cambiar_pin_operador(uuid,text) to authenticated;

create or replace function public.set_operador_activo(p_operator_id uuid, p_activo boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('administrar_operadores_caja') then
    raise exception 'No tenés permiso para administrar operadores de Caja';
  end if;

  update public.cash_operators
  set activo = p_activo, updated_by = auth.uid()
  where id = p_operator_id and tenant_id = v_tenant;
  if not found then raise exception 'Operador no encontrado'; end if;

  insert into public.cash_audit_log (tenant_id, operator_id, user_id, accion)
  values (v_tenant, p_operator_id, auth.uid(), case when p_activo then 'operador_reactivado' else 'operador_desactivado' end);
end;
$$;
revoke all on function public.set_operador_activo(uuid,boolean) from public;
grant execute on function public.set_operador_activo(uuid,boolean) to authenticated;

-- ────────────────────────────────────────────────────────────────
-- _verificar_pin_operador: INTERNA. Sin ningún grant — el cliente no
-- puede llamarla directo ni para "probar" un PIN. Nunca lanza
-- excepción por PIN incorrecto/operador bloqueado: siempre hace su
-- update de intentos_fallidos/bloqueado_hasta y retorna {ok,...}
-- normalmente, así ese update queda confirmado sin importar qué haga
-- después la función que la llamó.
-- ────────────────────────────────────────────────────────────────
create or replace function public._verificar_pin_operador(p_operator_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tenant uuid;
  v_op public.cash_operators;
  v_hash text;
  v_intentos int;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    return jsonb_build_object('ok', false, 'reason', 'no_autenticado');
  end if;

  select * into v_op from public.cash_operators
  where id = p_operator_id and tenant_id = v_tenant
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'operador_no_encontrado');
  end if;
  if not v_op.activo then
    return jsonb_build_object('ok', false, 'reason', 'operador_inactivo');
  end if;
  if v_op.bloqueado_hasta is not null and v_op.bloqueado_hasta > now() then
    return jsonb_build_object('ok', false, 'reason', 'operador_bloqueado', 'bloqueado_hasta', v_op.bloqueado_hasta);
  end if;

  select pin_hash into v_hash from public.cash_operator_secrets where operator_id = p_operator_id;
  if v_hash is null then
    return jsonb_build_object('ok', false, 'reason', 'sin_pin_configurado');
  end if;

  if v_hash = crypt(p_pin, v_hash) then
    update public.cash_operators
    set intentos_fallidos = 0, bloqueado_hasta = null, last_used_at = now()
    where id = p_operator_id;
    return jsonb_build_object('ok', true);
  else
    v_intentos := v_op.intentos_fallidos + 1;
    update public.cash_operators
    set intentos_fallidos = v_intentos,
        bloqueado_hasta = case when v_intentos >= 5 then now() + interval '15 minutes' else bloqueado_hasta end
    where id = p_operator_id;
    return jsonb_build_object('ok', false, 'reason', 'pin_incorrecto', 'intentos_restantes', greatest(5 - v_intentos, 0));
  end if;
end;
$$;
revoke all on function public._verificar_pin_operador(uuid,text) from public;
revoke all on function public._verificar_pin_operador(uuid,text) from authenticated;

-- ────────────────────────────────────────────────────────────────
-- calcular_expected_cash: fórmula única de "efectivo esperado", usada
-- por todas las RPC de abajo. Efectivo inicial + movimientos cuyo
-- metodo_pago='efectivo' (ya vienen con signo correcto: ingresos
-- positivos, egresos negativos) — transferencia/tarjeta/otro NUNCA
-- suman acá, aunque sí cuenten como "ingresos del turno" en la UI.
-- Interna: el frontend tiene un espejo JS idéntico, no necesita llamar
-- esta RPC para mostrar el número (igual que saldo_pendiente_reserva).
-- ────────────────────────────────────────────────────────────────
create or replace function public.calcular_expected_cash(p_session_id uuid)
returns numeric
language sql
stable
set search_path = public
as $$
  select coalesce(cs.opening_amount,0) + coalesce((
    select sum((m->>'importe')::numeric)
    from jsonb_array_elements(coalesce(cs.movimientos,'[]'::jsonb)) m
    where m->>'metodo_pago' = 'efectivo'
  ),0)
  from public.cash_sessions cs
  where cs.id = p_session_id
$$;
revoke all on function public.calcular_expected_cash(uuid) from public;
revoke all on function public.calcular_expected_cash(uuid) from authenticated;

-- ────────────────────────────────────────────────────────────────
-- abrir_caja_propietario
-- ────────────────────────────────────────────────────────────────
create or replace function public.abrir_caja_propietario(p_operator_id uuid, p_pin text, p_opening_amount numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_check jsonb;
  v_numero int;
  v_operador_nombre text;
  v_fecha_uy date;
  v_sesion public.cash_sessions;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('abrir_caja') then raise exception 'No tenés permiso para abrir Caja'; end if;
  if p_opening_amount is null or p_opening_amount < 0 then raise exception 'El efectivo inicial no puede ser negativo'; end if;

  if exists (select 1 from public.cash_sessions where tenant_id=v_tenant and grupo='hostal' and status='abierta') then
    return jsonb_build_object('ok', false, 'reason', 'ya_hay_caja_abierta');
  end if;

  v_check := public._verificar_pin_operador(p_operator_id, p_pin);
  if not (v_check->>'ok')::boolean then
    return v_check;
  end if;

  select nombre into v_operador_nombre from public.cash_operators where id = p_operator_id;
  v_fecha_uy := (now() at time zone 'America/Montevideo')::date;

  insert into public.cash_session_counters(tenant_id, prox)
  values (v_tenant, coalesce((select max(numero) from public.cash_sessions where tenant_id=v_tenant),0) + 1)
  on conflict (tenant_id) do update set prox = cash_session_counters.prox + 1
  returning prox into v_numero;

  begin
    insert into public.cash_sessions (
      tenant_id, grupo, operator_id, numero, status, opened_at, opened_by, opening_amount, movimientos,
      responsable, efectivo_inicial, abierta, apertura, created_by, updated_by
    ) values (
      v_tenant, 'hostal', p_operator_id, v_numero, 'abierta', now(), auth.uid(), p_opening_amount, '[]'::jsonb,
      v_operador_nombre, p_opening_amount, true, v_fecha_uy, auth.uid(), auth.uid()
    ) returning * into v_sesion;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'ya_hay_caja_abierta');
  end;

  return jsonb_build_object('ok', true, 'session', to_jsonb(v_sesion));
end;
$$;
revoke all on function public.abrir_caja_propietario(uuid,text,numeric) from public;
grant execute on function public.abrir_caja_propietario(uuid,text,numeric) to authenticated;

-- ────────────────────────────────────────────────────────────────
-- cerrar_caja_propietario: exige que sea el MISMO operador que abrió.
-- ────────────────────────────────────────────────────────────────
create or replace function public.cerrar_caja_propietario(
  p_session_id uuid, p_operator_id uuid, p_pin text, p_declared_cash numeric, p_observacion text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_sesion public.cash_sessions;
  v_check jsonb;
  v_expected numeric;
  v_diff numeric;
  v_fecha_uy date;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('cerrar_caja') then raise exception 'No tenés permiso para cerrar Caja'; end if;

  select * into v_sesion from public.cash_sessions
  where id = p_session_id and tenant_id = v_tenant and grupo = 'hostal'
  for update;
  if not found then raise exception 'Caja no encontrada'; end if;
  if v_sesion.status <> 'abierta' then raise exception 'Esta Caja ya está cerrada'; end if;
  if v_sesion.operator_id is distinct from p_operator_id then
    return jsonb_build_object('ok', false, 'reason', 'operador_no_coincide');
  end if;

  v_check := public._verificar_pin_operador(p_operator_id, p_pin);
  if not (v_check->>'ok')::boolean then
    return v_check;
  end if;

  v_expected := public.calcular_expected_cash(p_session_id);
  v_diff := p_declared_cash - v_expected;
  if v_diff <> 0 and (p_observacion is null or trim(p_observacion) = '') then
    return jsonb_build_object('ok', false, 'reason', 'observacion_requerida', 'expected_cash', v_expected, 'difference', v_diff);
  end if;

  v_fecha_uy := (now() at time zone 'America/Montevideo')::date;

  update public.cash_sessions
  set status='cerrada', closed_at=now(), closed_by=auth.uid(),
      declared_cash=p_declared_cash, expected_cash=v_expected, difference=v_diff, closing_note=p_observacion,
      abierta=false, cierre=v_fecha_uy, updated_by=auth.uid()
  where id = p_session_id
  returning * into v_sesion;

  insert into public.cash_audit_log (tenant_id, cash_session_id, operator_id, user_id, accion, campo, valor_nuevo, motivo)
  values (v_tenant, p_session_id, p_operator_id, auth.uid(), 'cerrar', 'declared_cash', p_declared_cash::text, p_observacion);

  return jsonb_build_object('ok', true, 'session', to_jsonb(v_sesion));
end;
$$;
revoke all on function public.cerrar_caja_propietario(uuid,uuid,text,numeric,text) from public;
grant execute on function public.cerrar_caja_propietario(uuid,uuid,text,numeric,text) to authenticated;

-- ────────────────────────────────────────────────────────────────
-- cerrar_caja_administrativo: para cuando el operador que abrió no
-- está disponible. NO inventa un arqueo — sin p_declared_cash, queda
-- declared_cash/difference en null (nunca "declared=expected" como si
-- alguien hubiese contado). El operador original de la sesión no se
-- toca; queda registrado quién intervino en cash_audit_log.
-- ────────────────────────────────────────────────────────────────
create or replace function public.cerrar_caja_administrativo(
  p_session_id uuid, p_operator_id uuid, p_pin text, p_motivo text, p_declared_cash numeric default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_sesion public.cash_sessions;
  v_check jsonb;
  v_expected numeric;
  v_diff numeric;
  v_fecha_uy date;
  v_accion text;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('administrar_operadores_caja') then
    raise exception 'No tenés permiso para hacer un cierre administrativo';
  end if;
  if not public.has_permission('cerrar_caja') then raise exception 'No tenés permiso para cerrar Caja'; end if;
  if p_motivo is null or trim(p_motivo) = '' then raise exception 'El motivo es obligatorio'; end if;

  select * into v_sesion from public.cash_sessions
  where id = p_session_id and tenant_id = v_tenant and grupo = 'hostal'
  for update;
  if not found then raise exception 'Caja no encontrada'; end if;
  if v_sesion.status <> 'abierta' then raise exception 'Esta Caja ya está cerrada'; end if;

  v_check := public._verificar_pin_operador(p_operator_id, p_pin);
  if not (v_check->>'ok')::boolean then
    return v_check;
  end if;

  v_expected := public.calcular_expected_cash(p_session_id);
  v_fecha_uy := (now() at time zone 'America/Montevideo')::date;

  if p_declared_cash is null then
    v_diff := null;
    v_accion := 'cierre_administrativo_sin_arqueo';
  else
    v_diff := p_declared_cash - v_expected;
    v_accion := 'cierre_administrativo_con_arqueo';
  end if;

  -- operator_id NO se toca: sigue siendo quien abrió la caja.
  update public.cash_sessions
  set status='cerrada', closed_at=now(), closed_by=auth.uid(),
      declared_cash=p_declared_cash, expected_cash=v_expected, difference=v_diff, closing_note=p_motivo,
      abierta=false, cierre=v_fecha_uy, updated_by=auth.uid()
  where id = p_session_id
  returning * into v_sesion;

  insert into public.cash_audit_log (tenant_id, cash_session_id, operator_id, user_id, accion, motivo)
  values (v_tenant, p_session_id, p_operator_id, auth.uid(), v_accion, p_motivo);

  return jsonb_build_object('ok', true, 'session', to_jsonb(v_sesion));
end;
$$;
revoke all on function public.cerrar_caja_administrativo(uuid,uuid,text,text,numeric) from public;
grant execute on function public.cerrar_caja_administrativo(uuid,uuid,text,text,numeric) to authenticated;

-- ────────────────────────────────────────────────────────────────
-- corregir_caja_propietario: lista blanca SIN expected_cash (siempre
-- calculado, nunca editable a mano). Corregir declared_cash recalcula
-- difference sola y deja dos filas de auditoría (una por campo).
-- ────────────────────────────────────────────────────────────────
create or replace function public.corregir_caja_propietario(
  p_session_id uuid, p_operator_id uuid, p_pin text, p_campo text, p_valor_nuevo text, p_motivo text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_sesion public.cash_sessions;
  v_check jsonb;
  v_valor_anterior text;
  v_expected numeric;
  v_diff_anterior numeric;
  v_diff_nueva numeric;
  v_declared numeric;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('administrar_operadores_caja') then
    raise exception 'No tenés permiso para corregir una Caja';
  end if;
  if p_motivo is null or trim(p_motivo) = '' then raise exception 'El motivo es obligatorio'; end if;
  if p_campo not in ('declared_cash','closing_note') then
    raise exception 'Campo no corregible: %', p_campo;
  end if;

  select * into v_sesion from public.cash_sessions
  where id=p_session_id and tenant_id=v_tenant and grupo='hostal'
  for update;
  if not found then raise exception 'Caja no encontrada'; end if;

  v_check := public._verificar_pin_operador(p_operator_id, p_pin);
  if not (v_check->>'ok')::boolean then
    return v_check;
  end if;

  if p_campo = 'declared_cash' then
    v_valor_anterior := v_sesion.declared_cash::text;
    v_declared := p_valor_nuevo::numeric;
    v_expected := coalesce(v_sesion.expected_cash, public.calcular_expected_cash(p_session_id));
    v_diff_anterior := v_sesion.difference;
    v_diff_nueva := v_declared - v_expected;

    update public.cash_sessions
    set declared_cash = v_declared, difference = v_diff_nueva, expected_cash = v_expected, updated_by = auth.uid()
    where id = p_session_id;

    insert into public.cash_audit_log (tenant_id, cash_session_id, operator_id, user_id, accion, campo, valor_anterior, valor_nuevo, motivo)
    values (v_tenant, p_session_id, p_operator_id, auth.uid(), 'correccion', 'declared_cash', v_valor_anterior, p_valor_nuevo, p_motivo);

    insert into public.cash_audit_log (tenant_id, cash_session_id, operator_id, user_id, accion, campo, valor_anterior, valor_nuevo, motivo)
    values (v_tenant, p_session_id, p_operator_id, auth.uid(), 'correccion', 'difference',
            coalesce(v_diff_anterior::text,''), v_diff_nueva::text, p_motivo || ' (recálculo automático de difference)');
  else
    v_valor_anterior := v_sesion.closing_note;
    update public.cash_sessions set closing_note = p_valor_nuevo, updated_by = auth.uid() where id = p_session_id;
    insert into public.cash_audit_log (tenant_id, cash_session_id, operator_id, user_id, accion, campo, valor_anterior, valor_nuevo, motivo)
    values (v_tenant, p_session_id, p_operator_id, auth.uid(), 'correccion', 'closing_note', v_valor_anterior, p_valor_nuevo, p_motivo);
  end if;

  select * into v_sesion from public.cash_sessions where id = p_session_id;
  return jsonb_build_object('ok', true, 'session', to_jsonb(v_sesion));
end;
$$;
revoke all on function public.corregir_caja_propietario(uuid,uuid,text,text,text,text) from public;
grant execute on function public.corregir_caja_propietario(uuid,uuid,text,text,text,text) to authenticated;

-- ────────────────────────────────────────────────────────────────
-- anular_movimiento_caja_cerrada: registrar_movimiento_caja exige
-- abierta=true a propósito (protege el flujo normal) — para anular un
-- movimiento de una caja YA CERRADA hace falta esta RPC aparte. Nunca
-- reabre la sesión (sigue 'cerrada' todo el tiempo).
-- ────────────────────────────────────────────────────────────────
create or replace function public.anular_movimiento_caja_cerrada(
  p_session_id uuid, p_operator_id uuid, p_pin text, p_payment_operation_id uuid, p_motivo text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_sesion public.cash_sessions;
  v_check jsonb;
  v_orig public.payment_operations;
  v_nuevo_op uuid;
  v_importe_inverso numeric;
  v_mov_original jsonb;
  v_sena_actual numeric;
  v_sena_nueva numeric;
  v_expected numeric;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'Usuario no autenticado o inactivo'; end if;
  if not public.has_permission('administrar_operadores_caja') then
    raise exception 'No tenés permiso para anular un movimiento de una Caja cerrada';
  end if;
  if p_motivo is null or trim(p_motivo) = '' then raise exception 'El motivo es obligatorio'; end if;

  select * into v_sesion from public.cash_sessions
  where id=p_session_id and tenant_id=v_tenant and grupo='hostal'
  for update;
  if not found then raise exception 'Caja no encontrada'; end if;
  if v_sesion.status <> 'cerrada' then
    raise exception 'Esta función es solo para Cajas cerradas — la Caja abierta usa la anulación normal';
  end if;

  v_check := public._verificar_pin_operador(p_operator_id, p_pin);
  if not (v_check->>'ok')::boolean then
    return v_check;
  end if;

  select * into v_orig from public.payment_operations
  where payment_operation_id = p_payment_operation_id and tenant_id = v_tenant and cash_session_id = p_session_id;
  if not found then raise exception 'Movimiento original no encontrado en esta Caja'; end if;
  if v_orig.tipo in ('anulacion','devolucion') then raise exception 'No se puede anular una anulación'; end if;
  if exists (select 1 from public.payment_operations where reversa_de = p_payment_operation_id) then
    raise exception 'Ese movimiento ya fue anulado';
  end if;

  v_importe_inverso := -v_orig.importe;
  v_nuevo_op := gen_random_uuid();

  insert into public.payment_operations (payment_operation_id, tenant_id, reserva_id, cash_session_id, tipo, importe, reversa_de, created_by)
  values (v_nuevo_op, v_tenant, v_orig.reserva_id, p_session_id, 'anulacion', v_importe_inverso, p_payment_operation_id, auth.uid());

  if v_orig.reserva_id is not null then
    select coalesce(sena_parcial,0) into v_sena_actual from public.reservations where id = v_orig.reserva_id for update;
    v_sena_nueva := greatest(v_sena_actual + v_importe_inverso, 0);
    update public.reservations set sena_parcial = v_sena_nueva where id = v_orig.reserva_id;
  end if;

  select m into v_mov_original
  from jsonb_array_elements(v_sesion.movimientos) m
  where m->>'payment_operation_id' = p_payment_operation_id::text
  limit 1;

  update public.cash_sessions
  set movimientos = coalesce(movimientos,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
        'payment_operation_id', v_nuevo_op,
        'reversa_de', p_payment_operation_id,
        'reserva_id', v_orig.reserva_id,
        'importe', v_importe_inverso,
        'tipo_movimiento', 'anulacion',
        'metodo_pago', v_mov_original->>'metodo_pago',
        'fecha_hora', now(),
        'usuario_responsable', auth.uid()
      ))
  where id = p_session_id;

  v_expected := public.calcular_expected_cash(p_session_id);
  update public.cash_sessions
  set expected_cash = v_expected,
      difference = case when declared_cash is not null then declared_cash - v_expected else null end,
      updated_by = auth.uid()
  where id = p_session_id
  returning * into v_sesion;

  insert into public.cash_audit_log (tenant_id, cash_session_id, operator_id, user_id, accion, campo, motivo)
  values (v_tenant, p_session_id, p_operator_id, auth.uid(), 'anular_movimiento', 'movimientos', p_motivo);

  return jsonb_build_object('ok', true, 'session', to_jsonb(v_sesion));
end;
$$;
revoke all on function public.anular_movimiento_caja_cerrada(uuid,uuid,text,uuid,text) from public;
grant execute on function public.anular_movimiento_caja_cerrada(uuid,uuid,text,uuid,text) to authenticated;

-- ── Verificación ──
-- select routine_name, grantee, privilege_type from information_schema.routine_privileges
--   where routine_name in ('hash_pin','_verificar_pin_operador','calcular_expected_cash');
--   -- NO debe aparecer 'authenticated' ni 'PUBLIC' en ninguna fila.
-- select routine_name, grantee from information_schema.routine_privileges
--   where routine_name in ('crear_operador_caja','cambiar_pin_operador','set_operador_activo',
--   'abrir_caja_propietario','cerrar_caja_propietario','cerrar_caja_administrativo',
--   'corregir_caja_propietario','anular_movimiento_caja_cerrada') and grantee='authenticated';
--   -- debe haber 1 fila por cada una.

-- ── Rollback ──
-- drop function if exists public.anular_movimiento_caja_cerrada(uuid,uuid,text,uuid,text);
-- drop function if exists public.corregir_caja_propietario(uuid,uuid,text,text,text,text);
-- drop function if exists public.cerrar_caja_administrativo(uuid,uuid,text,text,numeric);
-- drop function if exists public.cerrar_caja_propietario(uuid,uuid,text,numeric,text);
-- drop function if exists public.abrir_caja_propietario(uuid,text,numeric);
-- drop function if exists public.calcular_expected_cash(uuid);
-- drop function if exists public._verificar_pin_operador(uuid,text);
-- drop function if exists public.set_operador_activo(uuid,boolean);
-- drop function if exists public.cambiar_pin_operador(uuid,text);
-- drop function if exists public.crear_operador_caja(text,text,text);
-- drop function if exists public.hash_pin(text);
