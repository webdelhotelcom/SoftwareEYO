---
name: permissions-review
description: Revisar o extender el sistema de roles y permisos de Bestoic (fundador, administrador, encargado, empleado, propietario) — catálogo de permisos, role_permissions, gating de páginas/botones, o cuando un rol puede hacer algo que no debería (o no puede hacer algo que sí debería). Usar ante pedidos como "agregar un permiso nuevo", "el rol empleado no debería ver X", "revisá los permisos del módulo Y".
---

# Roles y permisos — Bestoic

## Los 5 roles

fundador, administrador, encargado, empleado, propietario. El rol
`propietario` es especial: además del permiso, sus políticas RLS también
filtran por `current_owner_id()` — solo ve lo que es suyo dentro del
tenant (sus propiedades, sus reservas), no todo el tenant.

## Cómo está armado el catálogo

- `permissions_catalog`: ~70 claves (ej. `ver_analisis_precios`,
  `editar_gastos`, `crear_propietarios`, `administrar_usuarios`,
  `acceder_prefacturacion`) — un catálogo único, no por tenant.
- `role_permissions`: la matriz rol×permiso×tenant, con defaults sensatos
  seedeados automáticamente para tenants nuevos (trigger en `tenants`) y
  para tenants existentes al agregar un permiso nuevo.
- `has_permission(perm_key)` (server-side, security definer) y `can(key)`
  (client-side en `panel.html`, espeja el server-side para UI/nav — el
  admin siempre da `true`).
- `PAGE_PERMISSION` en `panel.html`: mapea página → permiso mínimo para
  entrar (ej. `usuarios:'administrar_usuarios'`). Si una página no está en
  ese objeto, cualquier usuario logueado del tenant puede abrirla — para
  módulos sensibles hay que agregarla explícitamente.
- `planAllows(page)`: gating por plan (Inicial/Profesional/Hotel), en
  `PLAN_CONFIG[plan].pages` — es una capa DISTINTA del permiso por rol, no
  reemplaza el chequeo de permiso, se suman.

## La regla que ya se rompió una vez (no repetirlo)

**Agregar la clave al catálogo NO alcanza — hay que verificar que
realmente alguna política RLS la exija.** El hallazgo real de la auditoría
2026-08-02: 9 permisos nuevos de "Inteligencia de Precios" existían en el
catálogo, pero las políticas de SELECT (migración 0025) solo chequeaban el
plan del tenant, no `has_permission('ver_analisis_precios')` — un
`limpieza` sin ese permiso podía igual leer los competidores cargados. Se
corrigió en 0026. Cualquier permiso nuevo debe probarse así: crear/usar un
usuario con un rol que NO debería tener el permiso, confirmar que
realmente se lo niega la base (no solo la UI).

## Checklist al agregar un permiso o módulo nuevo

1. Clave nueva en `permissions_catalog` (nombre en español,
   snake_case, verbo+objeto: `ver_x`, `crear_x`, `editar_x`,
   `administrar_x`).
2. Default por rol en `role_permissions` para tenants existentes Y nuevos
   (el trigger de auto-seed en `tenants` debe cubrir el permiso nuevo).
3. Toda política RLS relevante (select/insert/update/delete) lo exige, no
   solo `tenant_id`.
4. `PAGE_PERMISSION` en `panel.html` si es una página completa nueva.
5. Botones/acciones puntuales gateados con `can('clave')` del lado
   cliente — SOLO como comodidad visual (ocultar el botón), nunca como la
   única protección real (la RLS es la protección real).
6. Probar en vivo con un usuario de rol bajo: ¿la UI lo oculta Y la base
   lo bloquea si se intenta igual por la API?

## Ejecución manual

`/permissions-review` — repasa un módulo o rol puntual contra este
checklist, o diseña el catálogo de permisos para una funcionalidad nueva.
