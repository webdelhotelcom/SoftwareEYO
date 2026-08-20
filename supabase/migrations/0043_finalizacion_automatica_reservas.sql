-- ════════════════════════════════════════════════════════════════
-- 0043 — Finalización automática de reservas vencidas. Hoy una reserva
-- se pasa a mano a "Finalizada" cuando termina la estadía — sobre todo
-- en Modo Administrador (Alojamientos/Propietarios), que no tiene
-- ningún flujo de Recepción/Checkout como Modo Propietario/Hostal y
-- por lo tanto ningún mecanismo automático existente la mueve de estado.
--
-- Reglas confirmadas explícitamente por el usuario (no asumidas):
--   - Se finaliza SIN chequear saldo pendiente: en la operación real de
--     EYO siempre se cobra todo antes de que el huésped se vaya, así
--     que no hace falta el freno que sí tiene intentar_finalizar_reserva()
--     (que exige checkout-realizado + saldo en cero — ese es un
--     mecanismo distinto, para el flujo de Recepción, y NO se toca acá).
--   - Se finaliza DESDE CUALQUIER estado no-cancelado (incluidas
--     Consulta/Esperando seña): si una reserva quedó en un estado
--     temprano con el checkout ya vencido, es porque el huésped
--     realmente estuvo. Única exclusión explícita: 'cancelada'.
--     'finalizada' tampoco se reprocesa (ya es el estado final).
--   - Mismo día del checkout (no al día siguiente): el check-out de EYO
--     es a las 10:00, la automatización corre a las 11:00 hora Uruguay
--     (una hora de margen) y usa checkout <= hoy, no checkout < hoy.
--
-- No toca información financiera: es un UPDATE de una sola columna
-- (estado). No escribe sena_parcial, no llama a registrar_movimiento_caja,
-- no crea ni modifica payment_operations ni cash_sessions.
--
-- Sin costo nuevo: pg_cron es una extensión de Postgres incluida en
-- Supabase (incluso en el plan free), no es un servicio de terceros.
-- ════════════════════════════════════════════════════════════════

create extension if not exists pg_cron;

-- Schema "private": funciones internas de mantenimiento que NO deben
-- quedar expuestas al cliente/frontend. Supabase/PostgREST solo expone
-- vía API los schemas listados explícitamente en la configuración del
-- proyecto (normalmente solo "public") — una función acá adentro no es
-- alcanzable por REST aunque alguien tuviera el nombre exacto.
create schema if not exists private;

-- TODO futuro: tanto 'America/Montevideo' como la hora de check-out
-- (10:00, de ahí la ejecución a las 11:00) están hardcodeados acá — el
-- día que Software EYO tenga clientes fuera de Uruguay o con otro
-- horario de check-out, ambos valores deberían salir de columnas
-- configurables por tenant/establecimiento (ej. tenants.timezone,
-- tenants.checkout_hour), no seguir hardcodeados. No se resuelve en
-- esta ronda — queda documentado acá para cuando haga falta.
--
-- search_path = '' + todo objeto con schema explícito (public.reservations,
-- no solo reservations): práctica actual recomendada por Supabase para
-- funciones SECURITY DEFINER — evita que alguien pueda "interceptar" la
-- función creando un objeto con el mismo nombre en un schema que quede
-- antes en el search_path de quien la ejecuta.
create or replace function private.finalizar_reservas_vencidas()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.reservations
  set estado = 'finalizada'
  where estado not in ('cancelada','finalizada')
    and checkout <= (now() at time zone 'America/Montevideo')::date;
end;
$$;

revoke all on function private.finalizar_reservas_vencidas() from public;
revoke all on function private.finalizar_reservas_vencidas() from authenticated;

-- Si ya existiera un job con este nombre de una corrida anterior de esta
-- migración, se reemplaza en vez de duplicarlo.
select cron.unschedule('finalizar-reservas-vencidas')
where exists (select 1 from cron.job where jobname = 'finalizar-reservas-vencidas');

select cron.schedule(
  'finalizar-reservas-vencidas',
  '0 14 * * *',  -- 14:00 UTC = 11:00 Uruguay (UTC-3 todo el año, sin horario de verano)
  $$select private.finalizar_reservas_vencidas();$$
);

-- ── Verificación (solo lectura, segura de correr en producción) ──
-- select * from cron.job where jobname = 'finalizar-reservas-vencidas';
-- select proname, pronamespace::regnamespace, prosecdef from pg_proc
--   where proname = 'finalizar_reservas_vencidas'; -- pronamespace debe ser "private", prosecdef debe ser true

-- ── Prueba de comportamiento (SOLO en local/staging, NUNCA en
--    producción — la función procesa todos los tenants de una sola vez,
--    no se puede acotar a "una reserva de prueba" sin editarla) ──
-- 1) select private.finalizar_reservas_vencidas();
-- 2) Confirmar: una reserva de prueba con checkout de hoy (después de las
--    11:00) y estado 'confirmada' pasó a 'finalizada'.
-- 3) Confirmar: una reserva 'cancelada' con checkout vencido NO cambió.
-- 4) Confirmar: sena_parcial/checkout_real_at/movimientos de Caja de esas
--    reservas quedaron exactamente iguales antes y después.
-- 5) select * from audit_log where table_name='reservations' order by
--    created_at desc limit 5; -- el cambio debe aparecer ahí

-- ── Rollback ──
-- select cron.unschedule('finalizar-reservas-vencidas');
-- drop function if exists private.finalizar_reservas_vencidas();
-- drop schema if exists private; -- solo si no se usa para nada más
