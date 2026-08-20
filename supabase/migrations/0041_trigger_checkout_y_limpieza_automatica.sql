-- ════════════════════════════════════════════════════════════════
-- 0041 — Causa real de "Salidas de hoy" vacío y de que Limpieza no
-- generaba tarea: checkout_real_at y la tarea de limpieza SOLO se
-- escribían dentro de registrar_checkout_propietario() (el botón de
-- Recepción). Editar la reserva directamente y cambiar el estado a
-- mano (un camino que ya existía antes de esta etapa y sigue siendo
-- válido) nunca pasaba por esa función. Confirmado con datos reales:
-- reservas ya en 'finalizada' con checkout_real_at=null y sin tarea.
--
-- Solución: DOS triggers en reservations, no un parche en Recepción —
-- así cualquier camino que lleve a un estado de salida queda cubierto,
-- tal como pidió el usuario ("centralizar... mediante trigger").
--   BEFORE UPDATE OF estado -> completa checkout_real_at si está null
--   AFTER  UPDATE OF estado -> crea la tarea de limpieza si no existe
-- Ambos exigen evidencia real de estadía (estaba 'alojado' antes, o
-- tiene checkin_real_at) para no generar una hora de salida falsa ni
-- una limpieza fantasma por un cambio de estado mal hecho a mano.
-- No retroactivo: son triggers de UPDATE, nunca se disparan para una
-- fila que no se vuelva a tocar — las 817 reservas históricas no
-- generan nada solas.
-- ════════════════════════════════════════════════════════════════

create or replace function public.hubo_estadia_real(p_old_estado text, p_checkin_real_at timestamptz)
returns boolean language sql immutable as $$
  select p_old_estado = 'alojado' or p_checkin_real_at is not null
$$;

-- BEFORE: no toca otra tabla -> no necesita security definer. Nunca
-- pisa una hora ya registrada (idempotente ante reintentos).
create or replace function public.completar_checkout_real_en_transicion()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.grupo is distinct from 'hostal' then return new; end if;
  if new.estado not in ('checkout-realizado','saldo-pendiente','finalizada') then return new; end if;
  if old.estado = new.estado then return new; end if;
  if old.estado in ('checkout-realizado','saldo-pendiente','finalizada') then return new; end if;
  if not public.hubo_estadia_real(old.estado, new.checkin_real_at) then return new; end if;
  if new.checkout_real_at is null then
    new.checkout_real_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reservations_completar_checkout on public.reservations;
create trigger trg_reservations_completar_checkout
  before update of estado on public.reservations
  for each row execute function public.completar_checkout_real_en_transicion();

-- AFTER: SÍ necesita security definer. Un rol como "recepción" puede
-- editar la reserva (tiene 'editar_reservas') pero no necesariamente
-- tiene permiso de INSERT en hk_tasks (hk_tasks_insert_own_tenant
-- exige 'administrar_housekeeping' o 'iniciar_limpieza') — sin esto,
-- la UPDATE de la reserva fallaría entera por un permiso que no tiene
-- nada que ver con lo que el usuario quería hacer. Sin riesgo entre
-- tenants: solo usa new.tenant_id/new.propiedad_id/new.id, que ya
-- pertenecen a la fila que la política RLS de reservations validó.
create or replace function public.crear_tarea_limpieza_en_checkout()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.grupo is distinct from 'hostal' then return new; end if;
  if new.estado not in ('checkout-realizado','saldo-pendiente','finalizada') then return new; end if;
  if old.estado = new.estado then return new; end if;
  if old.estado in ('checkout-realizado','saldo-pendiente','finalizada') then return new; end if;
  if new.propiedad_id is null then return new; end if;
  if not public.hubo_estadia_real(old.estado, new.checkin_real_at) then return new; end if;

  -- created_by/created_at los completa solo trg_hk_tasks_insert_audit
  -- (set_audit_fields), que ya corre en cualquier insert a hk_tasks.
  insert into public.hk_tasks (tenant_id, propiedad_id, reserva_id, grupo, estado, ts)
  select new.tenant_id, new.propiedad_id, new.id, 'hostal', 'pendiente',
         (now() at time zone 'America/Montevideo')::date
  where not exists (select 1 from public.hk_tasks h where h.reserva_id = new.id);

  return new;
end;
$$;

drop trigger if exists trg_reservations_checkout_limpieza on public.reservations;
create trigger trg_reservations_checkout_limpieza
  after update of estado on public.reservations
  for each row execute function public.crear_tarea_limpieza_en_checkout();

-- registrar_checkout_propietario: se le quita el insert manual a
-- hk_tasks (el trigger AFTER ya lo cubre, para no tener dos mecanismos
-- haciendo lo mismo) — el resto queda igual. Su propio checkout_real_at
-- =now() sigue ahí; como el trigger BEFORE solo completa cuando está
-- null, no hay conflicto entre los dos caminos.
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

-- ── Verificación ──
-- select tgname from pg_trigger where tgrelid='public.reservations'::regclass and not tgisinternal
--   and tgname in ('trg_reservations_completar_checkout','trg_reservations_checkout_limpieza'); -- 2 filas
-- select proname, prosecdef from pg_proc where proname in
--   ('completar_checkout_real_en_transicion','crear_tarea_limpieza_en_checkout');
--   -- prosecdef debe ser false para la primera, true para la segunda.
--
-- Prueba en vivo recomendada (con una reserva de prueba, no una real):
-- 1) Reserva en 'alojado' -> editarla a mano y poner estado 'finalizada'
--    desde el formulario normal (NO desde el botón de Recepción).
-- 2) select checkout_real_at, estado from reservations where id='...'; -- debe tener hora
-- 3) select * from hk_tasks where reserva_id='...'; -- debe existir, estado='pendiente'
-- 4) Reserva en 'confirmada' (nunca alojada, checkin_real_at null) -> cambiarla a mano a 'finalizada'
-- 5) Confirmar que NO se generó checkout_real_at ni tarea de limpieza (caso negativo).

-- ── Rollback ──
-- drop trigger if exists trg_reservations_checkout_limpieza on public.reservations;
-- drop trigger if exists trg_reservations_completar_checkout on public.reservations;
-- drop function if exists public.crear_tarea_limpieza_en_checkout();
-- drop function if exists public.completar_checkout_real_en_transicion();
-- drop function if exists public.hubo_estadia_real(text,timestamptz);
-- (registrar_checkout_propietario queda como en 0034/0039 si se revierte a mano)
