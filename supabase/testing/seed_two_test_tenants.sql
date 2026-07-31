-- ════════════════════════════════════════════════════════════════
-- Prueba de aislamiento entre clientes (Fase 1, punto obligatorio del pedido)
-- NO es una migración — no forma parte del esquema del producto, es solo
-- para generar los dos clientes de prueba y confirmar que uno no puede
-- ver ni tocar los datos del otro. Se puede borrar después con
-- cleanup_two_test_tenants.sql.
--
-- Cómo usar:
-- 1. Dashboard → Authentication → Users → Add user. Creá dos usuarios:
--    cliente-a-test@ejemplo.com  y  cliente-b-test@ejemplo.com
--    (cualquier contraseña, es solo para la prueba).
-- 2. Copiá el UID (UUID) que Supabase le asigna a cada uno.
-- 3. Reemplazá <UID_CLIENTE_A> y <UID_CLIENTE_B> acá abajo por esos UID.
-- 4. Corré este archivo completo en el SQL Editor.
-- ════════════════════════════════════════════════════════════════

insert into public.tenants (id, name, plan) values
  ('11111111-1111-1111-1111-111111111111', 'Cliente de prueba A', 'profesional'),
  ('22222222-2222-2222-2222-222222222222', 'Cliente de prueba B', 'profesional');

insert into public.profiles (id, tenant_id, email, role) values
  ('<UID_CLIENTE_A>', '11111111-1111-1111-1111-111111111111', 'cliente-a-test@ejemplo.com', 'admin'),
  ('<UID_CLIENTE_B>', '22222222-2222-2222-2222-222222222222', 'cliente-b-test@ejemplo.com', 'admin');

-- Un alojamiento de ejemplo para cada cliente, para tener algo que intentar
-- leer/editar/borrar "cruzado" durante la prueba.
insert into public.properties (tenant_id, nombre, direccion, capacidad, precio) values
  ('11111111-1111-1111-1111-111111111111', 'Alojamiento de A', 'Dirección de prueba A', 2, 1000),
  ('22222222-2222-2222-2222-222222222222', 'Alojamiento de B', 'Dirección de prueba B', 2, 1000);
