-- Crea una cuenta de prueba VACÍA (sin ningún dato cargado) para un cliente
-- real, plan Hotel (el más alto), que vence 24 horas después de correr este
-- script -- el vencimiento es real y automático (ver
-- 0054_tenant_trial_expiration.sql, ya debe estar aplicada antes de correr
-- esto): pasadas las 24hs, la base de datos deja de reconocerle acceso al
-- usuario aunque su sesión siga "abierta" en el navegador.
--
-- REQUISITO PREVIO (no lo puede hacer este script): crear el usuario de
-- login en el Dashboard de Supabase -> Authentication -> Users -> Add user
-- -> el email que le vayas a dar al cliente, con una contraseña que vos
-- elijas. Recién con ESE usuario ya creado corré este script. CAMBIÁ
-- v_client_email abajo por el email real que usaste.

do $$
declare
  v_client_email text := 'prueba@bestoic.uy'; -- CAMBIAR acá por el email real del cliente
  v_client_id uuid;
  v_tenant_id uuid;
begin
  select id into v_client_id from auth.users where email = v_client_email;
  if v_client_id is null then
    raise exception 'No existe el usuario % -- crealo primero en Authentication > Users del Dashboard.', v_client_email;
  end if;

  insert into public.tenants (name, plan, trial_expires_at)
    values ('Prueba cliente — ' || v_client_email, 'hotel', now() + interval '24 hours')
    returning id into v_tenant_id;

  -- Mismos límites que la demo anterior (plan Hotel exige client_limits
  -- explícito, nunca "ilimitado") -- ajustables si hace falta otro tope.
  insert into public.client_limits (tenant_id, max_properties, max_rooms, max_users, notes)
    values (v_tenant_id, 20, 60, 10, 'Cuenta de prueba de cliente, vence 24hs después de creada.');

  insert into public.profiles (id, tenant_id, email, role, active)
    values (v_client_id, v_tenant_id, v_client_email, 'admin', true);

  raise notice 'Listo -- tenant_id: %, vence: %', v_tenant_id, (now() + interval '24 hours');
end $$;

-- Verificación
select t.id, t.name, t.plan, t.trial_expires_at,
       (t.trial_expires_at - now()) as tiempo_restante,
       p.email, p.role
from public.tenants t
join public.profiles p on p.tenant_id = t.id
where t.name like 'Prueba cliente%'
order by t.trial_expires_at desc
limit 1;
