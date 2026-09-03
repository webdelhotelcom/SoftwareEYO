-- ════════════════════════════════════════════════════════════════
-- Cuenta demo para grabar videos -- tenant nuevo y separado, plan Hotel
-- (el más alto, sin límites de contrato), con datos de ejemplo realistas
-- para que se vean pobladas TODAS las pantallas principales: Alojamientos,
-- Propietarios, Huéspedes, Reservas (~200), Gastos, Tareas.
--
-- No es una migración -- es un script de un solo uso, con datos
-- explícitamente FICTICIOS para demo (no se confunde con "no inventar
-- datos": esa regla es sobre datos reales de clientes, esto es una demo
-- que el usuario pidió a propósito).
--
-- REQUISITO PREVIO (no lo puede hacer este script): crear el usuario de
-- login de la demo en el Dashboard de Supabase → Authentication → Users →
-- Add user → email "demo@bestoic.uy" (o el que prefieras, cambiándolo acá
-- abajo), con una contraseña que vos elijas. Recién con ESE usuario ya
-- creado corré este script.
--
-- Alcance de esta pasada: Alojamientos, Propietarios, Huéspedes, Reservas,
-- Gastos, Tareas. Quedan afuera (se pueden agregar en una pasada aparte si
-- hace falta para el video): Habitaciones, Check-in/out, Housekeeping,
-- Mantenimiento, Caja, Pre-facturación, Usuarios y Permisos con varios
-- roles, Inteligencia de Precios.
-- ════════════════════════════════════════════════════════════════

do $$
declare
  v_admin_email text := 'demo@bestoic.uy'; -- CAMBIAR acá si usaste otro email
  v_admin_id uuid;
  v_tenant_id uuid;

  v_property_names text[] := array['Hostal del Puerto','Cabañas del Bosque','Apartamento Centro','Posada La Rambla','Hostal Bahía','Cabaña El Faro'];
  v_property_ids uuid[];
  v_owner_names text[] := array['Ana Fernández','Roberto Silva','Marcela Castro','Diego Ramírez'];
  v_owner_ids uuid[];

  v_first_names text[] := array['Lucía','Martín','Sofía','Diego','Valentina','Nicolás','Camila','Federico','Agustina','Rodrigo','Florencia','Ignacio','Julieta','Santiago','Victoria','Facundo','Antonella','Bruno','Milagros','Emiliano','Delfina','Joaquín','Renata','Franco','Abril','Maximiliano','Catalina','Tomás','Guadalupe','Lautaro'];
  v_last_names text[] := array['Rodríguez','González','Fernández','López','Martínez','Pérez','García','Sánchez','Romero','Suárez','Torres','Díaz','Álvarez','Ruiz','Silva','Castro','Ramírez','Flores','Acosta','Benítez'];
  v_guest_ids uuid[];
  v_guest_names text[];

  v_canales text[] := array['Booking','Airbnb','WhatsApp','Instagram','Recomendación','Llamada'];
  v_categorias_gasto text[] := array['Limpieza','Mantenimiento','Servicios','Insumos','Comisiones','Impuestos','Marketing'];

  i int;
  v_prop_id uuid;
  v_guest_name text;
  v_checkin date;
  v_nights int;
  v_precio numeric;
  v_estado text;
  v_offset int;
begin
  select id into v_admin_id from auth.users where email = v_admin_email;
  if v_admin_id is null then
    raise exception 'No existe el usuario % -- crealo primero en Authentication > Users del Dashboard.', v_admin_email;
  end if;

  -- ── Tenant + límites (plan Hotel exige client_limits explícito, nunca
  -- "ilimitado") + perfil admin ──
  insert into public.tenants (name, plan) values ('Bestoic Demo', 'hotel') returning id into v_tenant_id;
  insert into public.client_limits (tenant_id, max_properties, max_rooms, max_users, notes)
    values (v_tenant_id, 20, 60, 10, 'Límites de la cuenta demo para videos, no es un contrato real.');
  insert into public.profiles (id, tenant_id, email, role, active)
    values (v_admin_id, v_tenant_id, v_admin_email, 'admin', true);

  -- ── Propietarios ──
  for i in 1..array_length(v_owner_names, 1) loop
    insert into public.owners (tenant_id, nombre, telefono, email)
      values (v_tenant_id, v_owner_names[i], '099' || (100000 + i * 37)::text, lower(replace(v_owner_names[i], ' ', '.')) || '@ejemplo.com')
      returning id into v_prop_id;
    v_owner_ids := array_append(v_owner_ids, v_prop_id);
  end loop;

  -- ── Alojamientos (repartidos entre los propietarios) ──
  for i in 1..array_length(v_property_names, 1) loop
    insert into public.properties (tenant_id, nombre, direccion, propietario_id, capacidad, precio, comision_pct, checkin_h, checkout_h)
      values (
        v_tenant_id, v_property_names[i],
        'Calle ' || (10 + i * 3)::text || ', Chuy, Uruguay',
        v_owner_ids[1 + (i % array_length(v_owner_ids, 1))],
        2 + (i % 6), 1200 + (i * 300), 10, '14:00', '10:00'
      )
      returning id into v_prop_id;
    v_property_ids := array_append(v_property_ids, v_prop_id);
  end loop;

  -- ── Huéspedes (90, nombres combinados sin repetir) ──
  for i in 0..89 loop
    v_guest_name := v_first_names[1 + (i % array_length(v_first_names, 1))];
    insert into public.guests (tenant_id, nombre, apellido, telefono, email, tipo_doc, doc, pais)
      values (
        v_tenant_id, v_guest_name, v_last_names[1 + ((i * 7) % array_length(v_last_names, 1))],
        '098' || (200000 + i * 53)::text,
        lower(v_guest_name) || '.' || lower(v_last_names[1 + ((i * 7) % array_length(v_last_names, 1))]) || i::text || '@ejemplo.com',
        'CI', (40000000 + i * 911)::text, 'Uruguay'
      )
      returning id into v_prop_id;
    v_guest_ids := array_append(v_guest_ids, v_prop_id);
    v_guest_names := array_append(v_guest_names, v_guest_name || ' ' || v_last_names[1 + ((i * 7) % array_length(v_last_names, 1))]);
  end loop;

  -- ── Reservas (200) -- repartidas en los últimos ~9 meses + algunas a
  -- futuro, estado coherente con la fecha de checkin. ──
  for i in 1..200 loop
    v_offset := (random() * 300)::int - 30; -- de -30 (futuro) a +270 (pasado) días atrás
    v_checkin := current_date - v_offset;
    v_nights := 1 + (random() * 6)::int;
    v_prop_id := v_property_ids[1 + (i % array_length(v_property_ids, 1))];
    v_guest_name := v_guest_names[1 + ((i * 3) % array_length(v_guest_names, 1))];
    v_precio := 1200 + (random() * 3500)::int;

    if v_checkin < current_date - 1 then
      v_estado := (array['finalizada','finalizada','finalizada','finalizada','cancelada','no-presentada'])[1 + floor(random() * 6)];
    elsif v_checkin <= current_date + 2 then
      v_estado := (array['alojado','checkin-pendiente','confirmada'])[1 + floor(random() * 3)];
    else
      v_estado := (array['confirmada','esperando-sena','sena-confirmada'])[1 + floor(random() * 3)];
    end if;

    insert into public.reservations (
      tenant_id, propiedad_id, huesped, telefono, email, huespedes,
      checkin, checkout, noches, precio, canal, estado, metodo_pago
    ) values (
      v_tenant_id, v_prop_id, v_guest_name,
      '098' || (300000 + i * 41)::text, lower(replace(v_guest_name, ' ', '.')) || i::text || '@ejemplo.com',
      1 + (random() * 3)::int,
      v_checkin, v_checkin + v_nights, v_nights, v_precio,
      v_canales[1 + ((i * 5) % array_length(v_canales, 1))],
      v_estado,
      (array['efectivo','transferencia','tarjeta'])[1 + floor(random() * 3)]
    );
  end loop;

  -- ── Gastos (90, repartidos en los últimos ~9 meses) ──
  for i in 1..90 loop
    insert into public.expenses (tenant_id, propiedad_id, fecha, categoria, concepto, monto)
      values (
        v_tenant_id,
        v_property_ids[1 + (i % array_length(v_property_ids, 1))],
        current_date - (random() * 270)::int,
        v_categorias_gasto[1 + (i % array_length(v_categorias_gasto, 1))],
        v_categorias_gasto[1 + (i % array_length(v_categorias_gasto, 1))] || ' -- ejemplo demo',
        300 + (random() * 4000)::int
      );
  end loop;

  -- ── Tareas (20, mezcla de pendientes y completadas) ──
  for i in 1..20 loop
    insert into public.tasks (tenant_id, propiedad_id, label, cat, due, done)
      values (
        v_tenant_id,
        v_property_ids[1 + (i % array_length(v_property_ids, 1))],
        (array['Revisar wifi','Reponer toallas','Coordinar limpieza profunda','Chequear caldera','Actualizar fotos','Renovar sábanas'])[1 + (i % 6)],
        (array['limpieza','mantenimiento','otro'])[1 + (i % 3)],
        current_date + (i - 10),
        i % 3 = 0
      );
  end loop;

  raise notice 'Listo -- tenant_id: %', v_tenant_id;
end $$;

-- Verificación
select
  (select count(*) from public.reservations where tenant_id = (select id from public.tenants where name = 'Bestoic Demo')) as reservas,
  (select count(*) from public.guests where tenant_id = (select id from public.tenants where name = 'Bestoic Demo')) as huespedes,
  (select count(*) from public.properties where tenant_id = (select id from public.tenants where name = 'Bestoic Demo')) as alojamientos,
  (select count(*) from public.owners where tenant_id = (select id from public.tenants where name = 'Bestoic Demo')) as propietarios,
  (select count(*) from public.expenses where tenant_id = (select id from public.tenants where name = 'Bestoic Demo')) as gastos,
  (select count(*) from public.tasks where tenant_id = (select id from public.tenants where name = 'Bestoic Demo')) as tareas;
