-- ════════════════════════════════════════════════════════════════
-- 0031 — TRIGGER DE NO-SOLAPAMIENTO DE FECHAS, SOLO MODO PROPIETARIO
-- (grupo='hostal'). El Modo Administrador (grupo='propiedades') no
-- cambia de comportamiento en absoluto: la función retorna sin validar
-- nada apenas ve que new.grupo <> 'hostal'.
--
-- Nota de preflight: propiedad_id/checkin/checkout ya son NOT NULL a
-- nivel de columna en reservations desde 0006 (para TODAS las reservas,
-- cualquier grupo/estado) — así que nunca puede existir una fila con
-- esos campos vacíos. Por eso este trigger no necesita (ni tiene)
-- un chequeo de "es null" — sería código muerto. Lo que sí faltaba y
-- se agrega acá: checkout>checkin, y que el alojamiento exista/sea del
-- mismo tenant/sea de Modo Propietario/esté activo, exigido SOLO
-- cuando el estado de la reserva compromete la fecha (evita bloquear
-- una "consulta" con datos todavía tentativos).
-- ════════════════════════════════════════════════════════════════

create or replace function public.estados_bloqueantes_hostal()
returns text[]
language sql
immutable
as $$
  select array['sena-parcial','sena-confirmada','confirmada','checkin-pendiente',
               'alojado','checkout-realizado','saldo-pendiente','finalizada']
$$;

comment on function public.estados_bloqueantes_hostal() is
  'Estados de reservations.estado que comprometen una fecha en Modo Propietario. '
  'No bloquean: consulta, esperando-sena, cancelada, no-presentada. '
  'Fuente de verdad única — el frontend mantiene una constante JS espejo '
  '(ESTADOS_BLOQUEANTES_HOSTAL) y hay una prueba que compara ambas listas.';

create or replace function public.check_reservation_overlap()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_bloqueantes text[] := public.estados_bloqueantes_hostal();
begin
  if new.grupo is distinct from 'hostal' then
    return new; -- Modo Administrador: sin cambios de comportamiento
  end if;

  if new.checkout <= new.checkin then
    raise exception 'La fecha de checkout debe ser posterior al checkin';
  end if;

  if new.estado <> all (v_bloqueantes) then
    return new; -- estado no bloqueante (consulta/esperando-sena/cancelada/no-presentada): no valida solapamiento
  end if;

  if not exists (
    select 1 from public.properties p
    where p.id = new.propiedad_id and p.tenant_id = new.tenant_id
      and p.grupo = 'hostal' and p.estado = 'activo'
  ) then
    raise exception 'El alojamiento no existe, no pertenece a esta cuenta, no es de Modo Propietario, o no está activo';
  end if;

  if exists (
    select 1 from public.reservations r
    where r.tenant_id = new.tenant_id
      and r.propiedad_id = new.propiedad_id
      and r.grupo = 'hostal'
      and r.id is distinct from new.id
      and r.estado = any (v_bloqueantes)
      and daterange(r.checkin, r.checkout, '[)') && daterange(new.checkin, new.checkout, '[)')
  ) then
    raise exception 'Superposición de fechas para este alojamiento' using errcode = '23P01';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_check_reservation_overlap on public.reservations;
create trigger trg_check_reservation_overlap
  before insert or update of propiedad_id, checkin, checkout, estado, grupo, tenant_id
  on public.reservations
  for each row
  execute function public.check_reservation_overlap();

-- ── Verificación (correr después de aplicar, contra datos de prueba
--    en local — NUNCA probar el rechazo insertando basura en producción) ──
-- select public.estados_bloqueantes_hostal();
-- select tgname from pg_trigger where tgrelid = 'public.reservations'::regclass and not tgisinternal;

-- ── Rollback ──
-- drop trigger if exists trg_check_reservation_overlap on public.reservations;
-- drop function if exists public.check_reservation_overlap();
-- drop function if exists public.estados_bloqueantes_hostal();
