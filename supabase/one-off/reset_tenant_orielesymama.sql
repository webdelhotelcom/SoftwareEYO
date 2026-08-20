-- Vacía por completo el tenant de orielesymama@gmail.com ("EYO — Cuenta
-- Founder"), dejándolo como recién creado, para cargar datos reales en vez
-- de los de prueba. Pedido explícito del usuario 2026-08-05 — confirmó que
-- todo lo cargado hoy es información de prueba, descartable, sin backup.
--
-- Qué SÍ se borra (todo lo que es "dato cargado", en orden hijo -> padre
-- para no chocar con las foreign keys):
--   price_recommendations, market_snapshots, market_searches,
--   competitor_properties, competitor_sets, pricing_property_config,
--   facturas, billing_config, cash_sessions, maint_tickets, hk_tasks,
--   stays, rooms, room_types, expenses, reservations, tasks, guests,
--   owners, properties, tenant_settings, audit_log (este último AL FINAL:
--   los deletes de arriba lo repueblan solos vía trigger, si se borra
--   antes queda con basura nueva).
--
-- Qué NO se toca (es configuración del sistema, no "datos" del tenant):
--   tenants (el tenant en sí sigue existiendo), profiles (tu login sigue
--   funcionando), role_permissions (tu grilla de permisos), client_limits
--   (tus límites 999/999/999 — si se borrara, caerías al default del plan
--   Hotel, mucho más bajo), plan_config, permissions_catalog,
--   market_data_sources (catálogos globales, compartidos por todos los
--   tenants).
--
-- Cómo correrlo: Supabase Dashboard -> SQL Editor -> pegar y ejecutar.
-- Es una sola transacción: si algo falla a mitad de camino, no queda nada
-- a medio borrar.

begin;

do $$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from public.profiles where email = 'orielesymama@gmail.com';

  if v_tenant_id is null then
    raise exception 'No se encontró ningún profile con email orielesymama@gmail.com — se aborta sin borrar nada.';
  end if;

  raise notice 'Vaciando el tenant %', v_tenant_id;

  delete from public.price_recommendations where tenant_id = v_tenant_id;
  delete from public.market_snapshots where tenant_id = v_tenant_id;
  delete from public.market_searches where tenant_id = v_tenant_id;
  delete from public.competitor_properties where tenant_id = v_tenant_id;
  delete from public.competitor_sets where tenant_id = v_tenant_id;
  delete from public.pricing_property_config where tenant_id = v_tenant_id;

  delete from public.facturas where tenant_id = v_tenant_id;
  delete from public.billing_config where tenant_id = v_tenant_id;
  delete from public.cash_sessions where tenant_id = v_tenant_id;
  delete from public.maint_tickets where tenant_id = v_tenant_id;
  delete from public.hk_tasks where tenant_id = v_tenant_id;
  delete from public.stays where tenant_id = v_tenant_id;
  delete from public.rooms where tenant_id = v_tenant_id;
  delete from public.room_types where tenant_id = v_tenant_id;

  delete from public.expenses where tenant_id = v_tenant_id;
  delete from public.reservations where tenant_id = v_tenant_id;
  delete from public.tasks where tenant_id = v_tenant_id;
  delete from public.guests where tenant_id = v_tenant_id;
  delete from public.owners where tenant_id = v_tenant_id;
  delete from public.properties where tenant_id = v_tenant_id;

  delete from public.tenant_settings where tenant_id = v_tenant_id;

  -- último: los deletes de arriba disparan triggers que insertan en
  -- audit_log, así que se limpia recién ahora.
  delete from public.audit_log where tenant_id = v_tenant_id;

  raise notice 'Listo. Tenant % vaciado — el login y los permisos siguen intactos.', v_tenant_id;
end $$;

commit;
