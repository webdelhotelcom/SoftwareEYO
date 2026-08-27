# Software EYO — Contexto para retomar el proyecto

Panel de gestión de alojamientos (hoteles/alojamientos), SaaS multi-tenant.
App de un solo archivo HTML+JS sin build, con Supabase de backend.

## Estructura del repo

- `index.html`, `software.html`, `assets/` — página comercial pública (landing).
- `app/panel.html` — el software real (single-file app, JS/CSS inline). Este es
  el archivo que se edita el 95% del tiempo.
- `app/config.js` — credenciales de Supabase. **GITIGNORED, no está en git.**
  Hay que recrearlo en cada compu nueva (ver abajo).
- `app/config.example.js` — plantilla de `config.js`, sí está en git.
- `supabase/migrations/` — historial de schema. **Nunca editar una migración
  ya aplicada** — siempre se agrega una nueva (`NNNN_descripcion.sql`).
- `deploy/build.sh` — arma el sitio final combinando landing + panel en un
  directorio de staging FUERA del repo (a propósito: el `_headers` de la raíz
  del repo pisaría al de `deploy/` si se construyera adentro).

## Infraestructura viva

- Supabase project ref: `ckbarfwqdnehqnpafzay`.
- Netlify: `dashing-conkies-92cb00.netlify.app` (site_id
  `4a32f93b-1d36-4093-ac74-a5483f83c131`) — `/` sirve la landing, `/panel`
  sirve el software.
- GitHub: `webdelhotelcom/SoftwareEYO` (ojo: es la cuenta `webdelhotelcom`,
  no `alojamietoeyo-maker` que se usa en los otros 2 proyectos personales).

## Recrear `app/config.js` en una compu nueva

Sacar la URL y la anon key reales desde el Dashboard de Supabase
(proyecto `ckbarfwqdnehqnpafzay` → Settings → API), y crear `app/config.js`
con el mismo formato que `app/config.example.js`.

## Convenciones no negociables

- **Multi-tenant real**: toda tabla nueva lleva `tenant_id` + RLS con las 4
  policies (select/insert/update/delete). Nunca confiar en que la UI oculte
  algo — eso no es seguridad real (aprendido de la auditoría 2026-08-02:
  varias tablas solo chequeaban `tenant_id`, nunca el permiso/rol real).
- Cualquier RLS de escritura debe exigir `has_permission()`/`is_admin()`,
  no solo pertenencia al tenant.
- Toda función `SECURITY DEFINER` nueva: `set search_path = ''`, todo objeto
  con esquema explícito (`public.tabla`, nunca `tabla`), `revoke all on
  function ... from public` + `grant execute ... to authenticated`.
- `esc()` para cualquier texto libre insertado vía `innerHTML` (XSS).
- Nunca `service_role` en el navegador. Alta de usuarios usa un cliente
  Supabase aislado (`persistSession:false`) para no pisar la sesión del admin.
- Nunca hardcodear un valor donde debería inferirse de datos reales — este
  proyecto tiene un historial de correcciones por "no inventar datos".

## Deploy

`bash deploy/build.sh` seguido de `netlify deploy --prod` sobre el directorio
de salida. **Nunca deployar con el dev server corriendo** — en Windows,
`@netlify/plugin-nextjs`/el propio proceso de Netlify puede fallar por locks
de archivo si algo sigue sirviendo `.next`/el build previo.

## Estado actual (2026-08-26)

- Fases 1-3 del software hotelero completas, auditadas en seguridad
  (multi-tenant, permisos, XSS, auditoría de acciones) — ver
  `docs/cierre-auditoria-2026-08-02.md`.
- El módulo "Finanzas personales (beta)" que vivía acá **fue extraído a un
  proyecto aparte, Finanzas Ori** (`D:\Ori\finanzas-ori`, repo separado).
  En EYO todavía existen las tablas `finance_*` viejas y el nav-item oculto,
  pendientes de limpieza (migración `0051`, **bloqueada** hasta que Finanzas
  Ori tenga el checkpoint de integridad en PASS completo — no borrar nada de
  esto sin ese checkpoint aprobado).
- PWA instalable agregada recientemente (`manifest.webmanifest`, `sw.js`,
  íconos) — esto es del software hotelero, no de Finanzas.

## Cómo trabajar en este proyecto

- Explorar y proponer un plan por escrito antes de tocar código; esperar un
  OK explícito ("dale"/"segui") antes de editar. No hace falta para pedidos
  triviales de una línea.
- El usuario es no-técnico y a veces trabaja desde un dispositivo distinto
  al de esta sesión: nunca asumir que puede navegar una ruta de archivo —
  pegarle el contenido exacto en el chat cuando haga falta que él haga algo.
- Prefiere preguntas de opción múltiple a preguntas abiertas.
