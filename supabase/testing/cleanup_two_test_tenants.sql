-- Borra los datos de prueba creados por seed_two_test_tenants.sql.
-- Los usuarios de Authentication (Users) hay que borrarlos aparte, a mano,
-- desde Dashboard → Authentication → Users (esta base no puede borrar
-- usuarios de auth.users por SQL sin privilegios de servicio).

delete from public.properties where tenant_id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222'
);
delete from public.client_limits where tenant_id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222'
);
delete from public.profiles where tenant_id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222'
);
delete from public.tenants where id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222'
);
