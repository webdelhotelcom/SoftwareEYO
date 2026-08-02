-- ════════════════════════════════════════════════════════════════
-- 0022 — Corrección detectada en las pruebas finales de la auditoría
-- (Fase 9, 2026-08-02): el backfill de 0019 para tenants ya existentes
-- no le daba al rol "propietario" el permiso "editar_gastos", aunque
-- la función que siembra tenants NUEVOS sí se lo daba desde el primer
-- momento (0019 ya lo tenía en seed_default_role_permissions()). Esto
-- dejaba a un propietario de un tenant creado ANTES de esa migración
-- con menos permisos que uno de un tenant creado después — mismo rol,
-- distinto resultado, sin ninguna razón para que sea así.
--
-- No pisa nada: on conflict do nothing, así que si algún admin ya
-- desactivó ese permiso a mano para su rol "propietario", esta
-- migración no lo reactiva.
-- ════════════════════════════════════════════════════════════════

insert into public.role_permissions (tenant_id, role, permission_key, allowed)
select t.id, 'propietario', 'editar_gastos', true
from public.tenants t
on conflict (tenant_id, role, permission_key) do nothing;
