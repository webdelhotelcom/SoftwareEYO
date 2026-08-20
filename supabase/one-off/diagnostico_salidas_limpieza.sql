-- Diagnóstico de SOLO LECTURA. No modifica nada.
-- Necesito ver el estado real de las reservas de Modo Propietario con
-- checkout de hoy o de ayer, y si generaron (o no) una tarea de limpieza.

with t as (
  select tenant_id from public.profiles where email='orielesymama@gmail.com'
)
select jsonb_pretty(jsonb_build_object(
  'hoy_uy', (now() at time zone 'America/Montevideo')::date,
  'reservas_checkout_hoy_o_ayer', (
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'huesped', r.huesped,
      'propiedad', p.nombre,
      'checkin', r.checkin,
      'checkout', r.checkout,
      'estado', r.estado,
      'checkin_real_at', r.checkin_real_at,
      'checkout_real_at', r.checkout_real_at,
      'checkout_by', r.checkout_by,
      'tiene_tarea_limpieza', exists(select 1 from public.hk_tasks h where h.reserva_id = r.id)
    ) order by r.checkout desc)
    from public.reservations r
    cross join t
    join public.properties p on p.id = r.propiedad_id
    where r.tenant_id = t.tenant_id and r.grupo = 'hostal'
      and r.checkout >= ((now() at time zone 'America/Montevideo')::date - 1)
      and r.checkout <= (now() at time zone 'America/Montevideo')::date
  ),
  'hk_tasks_hostal_todas', (
    select jsonb_agg(jsonb_build_object(
      'id', h.id, 'propiedad_id', h.propiedad_id, 'reserva_id', h.reserva_id,
      'grupo', h.grupo, 'estado', h.estado, 'ts', h.ts, 'created_at', h.created_at
    ) order by h.created_at desc)
    from public.hk_tasks h
    cross join t
    where h.tenant_id = t.tenant_id and h.grupo = 'hostal'
  ),
  'trigger_check_reservation_overlap_existe', (
    select count(*) > 0 from pg_trigger where tgname = 'trg_check_reservation_overlap'
  ),
  'funcion_registrar_checkout_propietario_existe', (
    select count(*) > 0 from pg_proc where proname = 'registrar_checkout_propietario'
  )
)) as diagnostico;
