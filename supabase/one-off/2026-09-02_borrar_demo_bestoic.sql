-- Borra por completo el tenant "Bestoic Demo" (demo@bestoic.uy) creado el
-- 2026-09-01 para grabar videos -- 200 reservas, habitaciones, caja, etc.
-- Se reemplaza por una cuenta de prueba nueva, vacía, para un cliente real
-- (ver 2026-09-02_crear_trial_cliente.sql).
--
-- SEGURIDAD: guarda explícita para nunca poder borrar el tenant de
-- orielesymama@gmail.com por error -- ver memoria "nunca tocar la cuenta
-- del founder". Este script solo actúa sobre el tenant que se llama
-- exactamente "Bestoic Demo".
--
-- Orden hijo -> padre (mismo criterio que reset_tenant_orielesymama.sql,
-- ampliado con las tablas de Caja/Mercado que ese script no tenía porque
-- el tenant del founder no las usaba en esa fecha).
--
-- NO borra el usuario de auth.users (demo@bestoic.uy) -- si querés
-- reutilizar ese login para otra cosa, borralo a mano desde el Dashboard
-- (Authentication > Users). Este script solo borra los DATOS del tenant.

begin;

do $$
declare
  v_tenant_id uuid;
begin
  select id into v_tenant_id from public.tenants where name = 'Bestoic Demo';

  if v_tenant_id is null then
    raise notice 'No existe ningún tenant "Bestoic Demo" -- nada que borrar.';
    return;
  end if;

  if v_tenant_id = (select tenant_id from public.profiles where email = 'orielesymama@gmail.com') then
    raise exception 'GUARDA DE SEGURIDAD: el tenant resuelto coincide con el de orielesymama@gmail.com -- se aborta sin borrar nada.';
  end if;

  raise notice 'Borrando tenant "Bestoic Demo" (%)', v_tenant_id;

  delete from public.price_recommendations where tenant_id = v_tenant_id;
  delete from public.market_snapshots where tenant_id = v_tenant_id;
  delete from public.market_searches where tenant_id = v_tenant_id;
  delete from public.competitor_properties where tenant_id = v_tenant_id;
  delete from public.competitor_sets where tenant_id = v_tenant_id;
  delete from public.pricing_property_config where tenant_id = v_tenant_id;

  delete from public.payment_operations where tenant_id = v_tenant_id;
  delete from public.cash_audit_log where tenant_id = v_tenant_id;
  delete from public.facturas where tenant_id = v_tenant_id;
  delete from public.billing_config where tenant_id = v_tenant_id;
  delete from public.cash_operators where tenant_id = v_tenant_id; -- cascada: cash_operator_secrets
  delete from public.cash_sessions where tenant_id = v_tenant_id;
  delete from public.cash_session_counters where tenant_id = v_tenant_id;

  delete from public.maint_tickets where tenant_id = v_tenant_id;
  delete from public.hk_tasks where tenant_id = v_tenant_id;
  delete from public.stays where tenant_id = v_tenant_id;
  delete from public.rooms where tenant_id = v_tenant_id;
  delete from public.room_types where tenant_id = v_tenant_id;

  delete from public.expenses where tenant_id = v_tenant_id;
  delete from public.reservations where tenant_id = v_tenant_id;
  delete from public.tasks where tenant_id = v_tenant_id;
  delete from public.guests where tenant_id = v_tenant_id;
  delete from public.owner_bank_accounts where tenant_id = v_tenant_id;
  delete from public.owners where tenant_id = v_tenant_id;
  delete from public.properties where tenant_id = v_tenant_id;

  delete from public.tenant_settings where tenant_id = v_tenant_id;

  delete from public.role_permissions where tenant_id = v_tenant_id;
  delete from public.client_limits where tenant_id = v_tenant_id;

  -- profiles también está auditada (trigger de log_audit_event) -- borrarla
  -- repuebla audit_log de nuevo, así que audit_log tiene que borrarse
  -- DESPUÉS de profiles, no antes (bug real: la primera versión de este
  -- script lo borraba antes y el delete final de tenants fallaba por la
  -- FK con las filas nuevas que el propio borrado de profiles generó).
  delete from public.profiles where tenant_id = v_tenant_id;

  -- ahora sí, último de todos: nada de lo de arriba puede repoblar esto.
  delete from public.audit_log where tenant_id = v_tenant_id;

  delete from public.tenants where id = v_tenant_id;

  raise notice 'Listo -- tenant "Bestoic Demo" eliminado por completo.';
end $$;

commit;

-- Verificación
select count(*) as deberia_ser_cero from public.tenants where name = 'Bestoic Demo';
