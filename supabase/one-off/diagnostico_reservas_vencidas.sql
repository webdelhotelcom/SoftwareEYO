-- Diagnóstico de SOLO LECTURA. No modifica nada.
-- Mismo WHERE que va a usar private.finalizar_reservas_vencidas() (migración
-- 0043) — corriendo esto ANTES de aplicar la migración, se ve exactamente
-- qué reservas cambiarían de estado a "Finalizada" la primera vez que
-- corra el job automático, sin tocar ningún dato todavía.

select jsonb_pretty(jsonb_build_object(
  'hoy_uy', (now() at time zone 'America/Montevideo')::date,
  'total_reservas_que_finalizarian', (
    select count(*) from public.reservations
    where estado not in ('cancelada','finalizada')
      and checkout <= (now() at time zone 'America/Montevideo')::date
  ),
  'detalle', (
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'tenant_id', r.tenant_id,
      'huesped', r.huesped,
      'estado_actual', r.estado,
      'checkin', r.checkin,
      'checkout', r.checkout,
      'grupo', r.grupo
    ) order by r.checkout desc)
    from public.reservations r
    where r.estado not in ('cancelada','finalizada')
      and r.checkout <= (now() at time zone 'America/Montevideo')::date
  )
)) as diagnostico;
