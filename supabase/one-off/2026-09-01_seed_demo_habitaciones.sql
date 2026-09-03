-- ════════════════════════════════════════════════════════════════
-- Segunda pasada de datos demo -- Habitaciones (room_types + rooms) para
-- el tenant "Bestoic Demo" ya creado. Igual que la pasada anterior: datos
-- ficticios a propósito, para grabar video.
--
-- OJO: rooms/room_types NO tienen propiedad_id en el esquema real -- las
-- habitaciones son a nivel de todo el tenant, no por alojamiento
-- individual (así está armado el módulo hoy, no es una limitación de este
-- script).
-- ════════════════════════════════════════════════════════════════

do $$
declare
  v_tenant_id uuid;
  v_type_ids uuid[];
  v_type_id uuid;
  i int;
  v_piso text;
begin
  select id into v_tenant_id from public.tenants where name = 'Bestoic Demo';
  if v_tenant_id is null then
    raise exception 'No existe el tenant "Bestoic Demo" -- corré primero el script de la primera pasada.';
  end if;

  -- ── Tipos de habitación ──
  insert into public.room_types (tenant_id, nombre, capacidad, camas, tipo_cama, banio, ac, tv, frigobar, precio, descripcion)
    values (v_tenant_id, 'Individual', 1, 1, '1 plaza', 'privado', true, true, false, 1500, 'Habitación individual con baño privado.')
    returning id into v_type_id;
  v_type_ids := array_append(v_type_ids, v_type_id);

  insert into public.room_types (tenant_id, nombre, capacidad, camas, tipo_cama, banio, ac, tv, frigobar, precio, descripcion)
    values (v_tenant_id, 'Doble', 2, 1, '2 plazas', 'privado', true, true, true, 2200, 'Habitación doble con cama matrimonial.')
    returning id into v_type_id;
  v_type_ids := array_append(v_type_ids, v_type_id);

  insert into public.room_types (tenant_id, nombre, capacidad, camas, tipo_cama, banio, ac, tv, frigobar, precio, descripcion)
    values (v_tenant_id, 'Triple', 3, 2, 'mixta', 'privado', true, true, true, 2800, 'Habitación triple, ideal para familias chicas.')
    returning id into v_type_id;
  v_type_ids := array_append(v_type_ids, v_type_id);

  insert into public.room_types (tenant_id, nombre, capacidad, camas, tipo_cama, banio, ac, tv, frigobar, precio, descripcion)
    values (v_tenant_id, 'Suite', 2, 1, '2 plazas', 'privado', true, true, true, 3800, 'Suite con living independiente y frigobar.')
    returning id into v_type_id;
  v_type_ids := array_append(v_type_ids, v_type_id);

  -- ── Habitaciones (18, repartidas en 3 pisos, estados variados y
  -- realistas: mayoría disponible, algunas ocupadas/limpieza/mantenimiento) ──
  for i in 1..18 loop
    v_piso := (array['1','2','3'])[1 + (i % 3)];
    insert into public.rooms (tenant_id, tipo_id, numero, piso, estado)
      values (
        v_tenant_id,
        v_type_ids[1 + (i % array_length(v_type_ids, 1))],
        v_piso || lpad((1 + (i % 6))::text, 2, '0'),
        v_piso,
        (array['disponible','disponible','disponible','ocupada','ocupada','limpieza','mantenimiento'])[1 + floor(random() * 7)]
      );
  end loop;

  raise notice 'Listo -- % tipos de habitación, 18 habitaciones.', array_length(v_type_ids, 1);
end $$;

-- Verificación
select
  (select count(*) from public.room_types where tenant_id = (select id from public.tenants where name = 'Bestoic Demo')) as tipos_de_habitacion,
  (select count(*) from public.rooms where tenant_id = (select id from public.tenants where name = 'Bestoic Demo')) as habitaciones;

-- ════════════════════════════════════════════════════════════════
-- Caja -- 10 turnos, la mayoría cerrados (con cierre) + 1 abierto hoy.
-- Formato real de cada movimiento (verificado contra el código de
-- panel.html): {tipo, monto, concepto, ts}, tipo en
-- ingreso/egreso/transferencia/tarjeta.
-- ════════════════════════════════════════════════════════════════

do $$
declare
  v_tenant_id uuid;
  v_responsables text[] := array['Ana Fernández','Roberto Silva','Marcela Castro'];
  i int;
  v_apertura date;
  v_ts_str text;
begin
  select id into v_tenant_id from public.tenants where name = 'Bestoic Demo';
  if v_tenant_id is null then
    raise exception 'No existe el tenant "Bestoic Demo" -- corré primero el script de la primera pasada.';
  end if;

  for i in 1..9 loop
    v_apertura := current_date - (i * 7);
    v_ts_str := to_char(v_apertura, 'YYYY-MM-DD');
    insert into public.cash_sessions (tenant_id, responsable, efectivo_inicial, abierta, apertura, cierre, movimientos)
      values (
        v_tenant_id,
        v_responsables[1 + (i % array_length(v_responsables, 1))],
        2000,
        false,
        v_apertura,
        v_apertura,
        jsonb_build_array(
          jsonb_build_object('tipo', 'ingreso', 'monto', 1500 + (random() * 2000)::int, 'concepto', 'Pago de reserva', 'ts', v_ts_str),
          jsonb_build_object('tipo', 'egreso', 'monto', 300 + (random() * 500)::int, 'concepto', 'Insumos de limpieza', 'ts', v_ts_str),
          jsonb_build_object('tipo', 'transferencia', 'monto', 800 + (random() * 1500)::int, 'concepto', 'Pago de reserva (transferencia)', 'ts', v_ts_str)
        )
      );
  end loop;

  -- Turno de hoy, todavía abierto.
  insert into public.cash_sessions (tenant_id, responsable, efectivo_inicial, abierta, apertura, movimientos)
    values (
      v_tenant_id, v_responsables[1], 2000, true, current_date,
      jsonb_build_array(
        jsonb_build_object('tipo', 'ingreso', 'monto', 1800, 'concepto', 'Pago de reserva', 'ts', to_char(current_date, 'YYYY-MM-DD')),
        jsonb_build_object('tipo', 'egreso', 'monto', 450, 'concepto', 'Compra de insumos', 'ts', to_char(current_date, 'YYYY-MM-DD'))
      )
    );

  raise notice 'Listo -- 10 turnos de caja.';
end $$;

-- Verificación
select count(*) as turnos_de_caja, count(*) filter (where abierta) as abiertos
from public.cash_sessions where tenant_id = (select id from public.tenants where name = 'Bestoic Demo');
