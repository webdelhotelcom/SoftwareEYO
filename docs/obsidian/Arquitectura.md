# Arquitectura

Ver también: [[00-Indice]] · [[Seguridad]] · [[Modulos]]

## Las tres piezas

1. **`app/panel.html`** — el frontend. Un único archivo HTML con CSS y JavaScript inline, sin build step, sin framework (no React/Vue/etc.), sin bundler. Se edita directo y se sube tal cual. La ventaja: cero dependencias de tooling, cualquiera puede abrirlo y entender qué hace leyendo de arriba a abajo. La desventaja consciente: es un archivo grande (miles de líneas) — se acepta ese costo a cambio de simplicidad operativa, dado el tamaño del equipo que lo mantiene.
2. **Supabase** (Postgres + Auth + API autogenerada) — toda la base de datos, autenticación y las reglas de seguridad (RLS). Un solo proyecto, plan Free, para todos los clientes.
3. **Netlify** — hosting estático del archivo de arriba (como `index.html` + `config.js` en la raíz del deploy). Plan Free.

Cero servidor propio, cero backend custom: `panel.html` habla directo con la API REST que Supabase genera automáticamente a partir del esquema SQL, usando la librería `supabase-js` cargada por CDN.

## Multi-tenant: aislamiento lógico, no físico

Todos los clientes (tenants) comparten las mismas tablas. Lo que los separa es:
- Una columna `tenant_id` en cada tabla de negocio.
- Políticas de Row Level Security (RLS) en PostgreSQL que filtran automáticamente cada consulta por el `tenant_id` del usuario logueado — **a nivel de base de datos**, no en el código JavaScript. Aunque alguien manipule el navegador o llame a la API directo con su propio token real, Postgres rechaza cualquier lectura/escritura fuera de su propio tenant.
- La función `current_tenant_id()` (security definer) resuelve el tenant del usuario actual a partir de `auth.uid()`, y es la que usan todas las políticas.

Se eligió este modelo (un proyecto compartido) en vez de "un proyecto de Supabase por cliente" explícitamente para quedarse en el plan gratuito — más proyectos individuales habría significado costo por cliente. Ver [[Historia-y-decisiones]].

## Roles y permisos (resumen — detalle en [[Seguridad]] y `docs/permisos.md`)

8 roles fijos (`admin`, `gerencia`, `encargado`, `recepcion`, `limpieza`, `mantenimiento`, `contador`, `propietario`), con una grilla de permisos configurable **por cliente** (`role_permissions`, tabla `tenant_id` + `role` + `permission_key` + `allowed`). Cada política de escritura de cada tabla exige el permiso correspondiente vía `has_permission('clave')`, no solo el `tenant_id`.

## Auditoría interna

`audit_log` registra automáticamente (vía triggers) cada insert/update/delete de las tablas de negocio, más un evento sintético `RESTORE` cuando se restaura un backup o se migra desde la demo vieja. Solo el admin de cada tenant puede leerlo, y nadie puede insertar/editar/borrar filas manualmente (ni siquiera el propio tenant) — es tamper-proof por diseño.

## Por qué un solo archivo y no una app "de verdad" (React, etc.)

Decisión explícita del proyecto, no una limitación técnica: mantener la superficie de mantenimiento mínima para un sistema que un desarrollador (con ayuda de IA) mantiene solo, sin equipo de frontend dedicado. El costo (un archivo grande, sin tipado, sin tests automatizados de UI) se acepta a cambio de poder editar y desplegar sin pipeline. Si el proyecto creciera mucho más, este trade-off valdría la pena reconsiderarlo — no se ha hecho porque no hizo falta todavía.
