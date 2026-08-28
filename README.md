# Bestoic

**Panel en vivo:** https://dashing-conkies-92cb00.netlify.app (hosting gratis en Netlify, conectado al proyecto real de Supabase, plan Free).

**Página comercial en vivo:** https://software-eyo.netlify.app (`index.html` + `software.html`, sitio Netlify aparte del panel — mismo repositorio, otro proyecto de hosting, para no arriesgar el panel real con cada cambio de contenido).

Sistema real multi-cliente (multi-tenant) de gestión de alojamientos y hotelería: cada cliente (tenant) tiene sus propios datos, separados por `tenant_id` y protegidos por Row Level Security (RLS) de PostgreSQL — nunca solo por el navegador. Reemplaza a la demo original en localStorage.

## Estructura del repositorio

```
EYO/
  app/
    panel.html            → el panel real (Supabase + Auth). Es el único archivo que se sigue desarrollando.
    config.example.js     → plantilla de configuración, versionada.
    config.js             → configuración real con tus claves (NO versionado, ver .gitignore).
    _headers               → headers de seguridad HTTP para Netlify (CSP, X-Frame-Options, etc.).
  supabase/
    migrations/           → esquema SQL versionado, 0001 en adelante (el número más alto que exista en la carpeta). Se corren TODAS en orden en el SQL Editor de Supabase (ver docs/supabase-setup.md).
    testing/               → scripts SQL solo para la prueba de aislamiento entre clientes (no es parte del producto).
  docs/
    supabase-setup.md      → paso a paso para crear el proyecto de Supabase y cargar el esquema completo.
    permisos.md             → catálogo de permisos, roles y cómo se aplican en la base de datos (no solo en pantalla).
    backup-restore.md      → cómo exportar/restaurar cada módulo, y cómo queda registrado en Auditoría.
    migracion-localstorage.md → cómo traer datos de la demo vieja (localStorage) a Supabase, con deduplicación.
    limites-gratuitos.md   → qué límites del plan gratuito de Supabase hay que vigilar y cómo.
    pruebas-aislamiento.md → pruebas en vivo de que un cliente no accede a datos de otro (aislamiento + permisos por rol).
    dispositivos-navegadores.md → qué anchos/navegadores se probaron de verdad y cuáles no.
    obsidian/               → base de conocimiento del proyecto (arquitectura, historia, decisiones) — abrí esta carpeta como vault en Obsidian, o empezá por docs/obsidian/00-Indice.md.
  .env.example            → referencia de las variables necesarias (ver docs/supabase-setup.md).

  index.html               → página comercial (landing), publicada en https://software-eyo.netlify.app
  software.html            → página comercial (funciones y precios), publicada en https://software-eyo.netlify.app/software.html
  assets/images/           → imágenes de la página comercial (og-cover.jpg, etc.)

  # Demo original — HISTÓRICA, no se edita más.
  # Queda como referencia hasta que se decida retirarla del todo.
  Panel-EYO-Plan-Hotel (7).html
  Panel-EYO-Plan-Profesional (4).html
  Panel-EYO-Plan-Inicial (5).html
  LEEME (2).md            → instrucciones de la demo vieja (localStorage). Ver el aviso al principio de ese archivo.
```

## Estado actual

**Los 20 módulos de negocio están migrados a Supabase, en producción, protegidos por RLS + permisos por rol:** Alojamientos, Propietarios, Reservas, Gastos, Huéspedes, Usuarios y Permisos, Auditoría, Tareas, Tipos de habitación, Habitaciones, Check-in/out (estadías), Housekeeping, Mantenimiento, Caja, Calendario hotelero, Reportes, Pre-facturación, Resumen mensual, WhatsApp/Mensajes y Dashboard. No queda ningún módulo de negocio funcionando solo en `localStorage` (ese estado transicional, descrito en versiones viejas de este README, ya terminó).

`app/panel.html` es un único archivo HTML que:
- Autentica contra Supabase Auth (sin usuario/contraseña hardcodeados).
- Lee y escribe cada módulo directo contra las tablas de Supabase, filtradas automáticamente por `tenant_id` vía RLS.
- Aplica permisos por rol tanto en la interfaz (oculta botones) como en la base de datos (las políticas RLS rechazan la escritura igual, aunque alguien edite el JavaScript del navegador) — ver `docs/permisos.md`.
- Registra automáticamente cada alta/edición/baja en `audit_log` (página **Auditoría**, solo visible para admin), incluyendo un resumen cuando se restaura un backup o se migra desde la demo vieja.

### Auditoría de seguridad (2026-08-02)

Se hizo una auditoría técnica completa, con pruebas en vivo (no solo revisión de código), antes de considerar el sistema listo para clientes reales. Se encontraron y corrigieron:

- **Crítico:** los permisos por rol solo se aplicaban en la pantalla, no en la base — corregido en `0019_permissions_enforcement.sql` (matriz completa de permisos por rol, aplicada con políticas RLS en las 21 tablas).
- **Alto:** un usuario desactivado podía seguir escribiendo datos si ya tenía sesión abierta — corregido en `0020_deactivated_user_lockout.sql`.
- **Alto:** decenas de campos de texto libre se insertaban en el HTML sin escapar (riesgo XSS) — corregido con una función `esc()` central aplicada en toda la app.
- **Medio:** faltaban headers de seguridad HTTP — agregado `app/_headers` (CSP, X-Frame-Options, etc.).
- **Medio:** la migración desde la demo vieja podía duplicar registros si se corría dos veces, y las restauraciones no dejaban rastro en Auditoría — corregido en `0021_restore_audit_trail.sql` (deduplicación + registro `RESTORE` en Auditoría).

Detalle completo, evidencia y resultados de las pruebas en vivo: pedir los artefactos de auditoría publicados, o ver `docs/pruebas-aislamiento.md` para la parte de aislamiento/permisos.

## Por dónde seguir

- ¿Proyecto de Supabase nuevo desde cero? → `docs/supabase-setup.md`.
- ¿Cómo funcionan los roles y permisos? → `docs/permisos.md`.
- ¿Backups y restauración? → `docs/backup-restore.md`.
- ¿Traer datos de la demo vieja? → `docs/migracion-localstorage.md`.
