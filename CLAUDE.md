# Bestoic — Contexto para retomar el proyecto

Panel de gestión de alojamientos (hoteles/alojamientos), SaaS multi-tenant.
App de un solo archivo HTML+JS sin build, con Supabase de backend.

@FINANCE.md — convenciones financieras (moneda, redondeo, comisiones,
saldo pendiente, seña del plan SaaS). Fuente de verdad para cualquier
código que calcule dinero en este proyecto; leer antes de tocar
`app/panel.html` en las secciones de Reservas/Gastos/Caja/Finanzas o
`netlify/functions/mp-plan-order.js`.

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

## Estado actual (2026-08-28)

- Fases 1-3 del software hotelero completas, auditadas en seguridad
  (multi-tenant, permisos, XSS, auditoría de acciones) — ver
  `docs/cierre-auditoria-2026-08-02.md`.
- El módulo "Finanzas personales (beta)" que vivía acá **fue extraído a un
  proyecto aparte, Finanzas Ori** (`D:\Ori\finanzas-ori`, repo separado).
  En Bestoic todavía existen las tablas `finance_*` viejas y el nav-item oculto,
  pendientes de limpieza. **OJO con el número de migración**: cuando se
  documentó esto se pensaba usar `0051` para esa limpieza, pero `0051`/`0052`/
  `0053` ya se usaron para otras cosas (ver abajo) — la limpieza de Finanzas
  personales toma el próximo número libre cuando se haga. Sigue **bloqueada**
  hasta que Finanzas Ori tenga el checkpoint de integridad en PASS completo —
  no borrar nada de esto sin ese checkpoint aprobado.
- PWA instalable agregada (`manifest.webmanifest`, `sw.js`, íconos) — esto es
  del software hotelero, no de Finanzas.
- **Rebranding "Software EYO" → "Bestoic" (2026-08-27/28), código listo y
  commiteado localmente, deploy pendiente:**
  - 2 commits en `master`: `952a8de` (aísla `owner_bank_accounts` por permiso
    + restaura CSP del agente Mercado) y `efbb0c0` (el rebranding completo:
    texto en marketing/panel/docs/skills, imágenes `almacen-*` renombradas,
    logo nuevo integrado en favicon/header/footer/og-cover/íconos PWA).
  - Migración `0053_rebrand_bestoic_comments.sql` — **ya aplicada en
    producción** (comentarios de metadata + 2 mensajes de error).
  - **No se pudo hacer `git push`** — el remote `software-eyo` exige la
    cuenta de GitHub `webdelhotelcom`, y el Git Credential Manager de esta
    compu/sesión tenía cacheada la cuenta `alojamietoeyo-maker` (la de los
    otros 2 proyectos personales), que da 403. Para sincronizar entre
    computadoras: en la compu donde SÍ esté logueado como `webdelhotelcom`
    en Git, correr `git push software-eyo master` — los 2 commits están
    listos, solo falta subirlos.
  - **El deploy a Netlify se cuelga sistemáticamente desde una sesión de
    Claude Code** (probado 6 veces: se traba siempre en "Waiting for deploy
    to go live", aunque los archivos sí terminan de subirse) — parece un
    problema de red/conexión larga del entorno sandboxeado, no del sitio ni
    de la cuenta. Hay que correrlo a mano, en una terminal real (Git Bash):
    `bash deploy/build.sh` → `cd /tmp/bestoic_publish` →
    `netlify deploy --dir=. --site=4a32f93b-1d36-4093-ac74-a5483f83c131 --no-build`
    (borrador primero, revisar, recién después `--prod`).
  - Logo nuevo (el que el usuario proveyó) queda guardado en
    `D:\Ori\LOGO\ChatGPT Image 27 ago 2026, 23_36_54.png` — ya integrado en
    el repo (favicon embebido en `index.html`/`software.html`, 2 `<img>` de
    header/footer, `assets/images/og-cover.jpg`, `app/icon-192.png`,
    `app/icon-512.png`, `app/icon-maskable-512.png`). El original tenía fondo
    negro cuadrado detrás del círculo blanco — se le sacó ese fondo (chroma
    key sobre negro puro) antes de componerlo en cada uso.
  - Pendiente, no hecho todavía: renombrar el repo de GitHub, el dominio/site
    de Netlify, el proyecto de Google Cloud OAuth, y el instalador
    `eyo-market-instalador` — todos son servicios externos, documentados
    como migración aparte en el plan de rebranding.

## Cómo trabajar en este proyecto

- Explorar y proponer un plan por escrito antes de tocar código; esperar un
  OK explícito ("dale"/"segui") antes de editar. No hace falta para pedidos
  triviales de una línea.
- El usuario es no-técnico y a veces trabaja desde un dispositivo distinto
  al de esta sesión: nunca asumir que puede navegar una ruta de archivo —
  pegarle el contenido exacto en el chat cuando haga falta que él haga algo.
- Prefiere preguntas de opción múltiple a preguntas abiertas.
