# Software EYO

## Estructura del repositorio

```
EYO/
  app/
    panel.html            → el panel (Supabase real). Éste es el que se sigue desarrollando.
    config.example.js     → plantilla de configuración, versionada.
    config.js             → configuración real con tus claves (NO versionado, ver .gitignore).
  supabase/
    migrations/           → esquema SQL versionado. Se corre en orden en el SQL Editor de Supabase.
    testing/               → scripts SQL solo para la prueba de aislamiento entre clientes (no es parte del producto).
  docs/
    supabase-setup.md      → paso a paso para crear el proyecto de Supabase y cargar el esquema.
    backup-restore.md      → cómo hacer y restaurar backups (localStorage y Supabase).
    migracion-localstorage.md → cómo traer los alojamientos de la demo vieja a Supabase.
    limites-gratuitos.md   → qué límites del plan gratuito de Supabase hay que vigilar y cómo.
    pruebas-aislamiento.md → prueba de que un cliente no accede a datos de otro.
  .env.example            → referencia de las variables necesarias (ver docs/supabase-setup.md).

  # Demo original (localStorage, sin backend) — INTACTA, no se edita más.
  # Queda como referencia histórica hasta que la migración esté aprobada.
  Panel-EYO-Plan-Hotel (7).html
  Panel-EYO-Plan-Profesional (4).html
  Panel-EYO-Plan-Inicial (5).html
  index (21).html
  software (8).html
  LEEME (2).md
```

## Estado de la migración

El proyecto está pasando de "demo HTML con localStorage" a "sistema real con Supabase" **por fases**, sin romper lo que ya funciona:

- **Fase 0** ✅ — repositorio git, con la demo original intacta como commit base.
- **Fase 1** (en curso) — backend real: Supabase (Postgres + Auth), separación por `tenant_id`, políticas RLS, límites por plan validados en el servidor, y el primer módulo (**Alojamientos**) conectado de punta a punta.
- **Fase 2 en adelante** — el resto de los módulos (Reservas, Gastos, Huéspedes, Propietarios, Usuarios y Permisos, Auditoría, Housekeeping, Mantenimiento, Caja, hotelería, Reportes, Pre-facturación) se migran uno por uno siguiendo el mismo patrón ya probado en Alojamientos.

Mientras dura la migración, `app/panel.html` tiene módulos en dos estados a la vez: Alojamientos ya habla con Supabase; el resto (Reservas, Gastos, Propietarios, Huéspedes, Tareas...) todavía usa localStorage, exactamente como en la demo original. Es un estado transicional esperado, no un error.

## Por dónde seguir

Ver `docs/supabase-setup.md` para crear el proyecto de Supabase y dejar `app/panel.html` funcionando con datos reales.
