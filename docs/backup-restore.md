# Backup y restauración

Cada uno de los 13 módulos con datos propios tiene su propio par de botones **"Exportar [módulo]"** / **"Importar [módulo]"**, en su sección correspondiente del panel: Alojamientos, Propietarios, Reservas, Gastos, Huéspedes, Tareas, Tipos de habitación ("tipos"), Habitaciones, Estadías, Housekeeping ("limpieza"), Mantenimiento, Caja y Comprobantes.

No existe (ni existió nunca en esta versión) un backup único de "toda la app": cada módulo se exporta e importa por separado, siempre contra Supabase — no hay nada en `localStorage` que respaldar.

## Cómo funciona

- **Exportar backup** — trae todos los registros de ese módulo que le pertenecen al cliente logueado directo de la base de datos (protegido por RLS: solo puede traer los de su propio tenant) y los descarga en un `.json` con la fecha de exportación.
- **Importar backup** — restaura ese `.json`: inserta cada registro como uno **nuevo** en Supabase, asociado automáticamente a la cuenta del usuario logueado (no hace falta indicar el `tenant_id` a mano). No pisa los registros existentes, para evitar perder datos por accidente — si aparecen duplicados evidentes, se borran a mano desde el panel.

Gratis y manual: no depende de ninguna función paga de Supabase. Se recomienda exportar antes de cualquier cambio grande (por ejemplo, antes de una migración de datos o antes de subir una versión nueva del panel).

## Cada restauración queda registrada en Auditoría

Además de las filas individuales que ya deja cada alta en `audit_log` (el registro normal de "quién creó qué"), cada vez que se usa **Importar backup** o **Migrar desde demo anterior** queda un resumen aparte en la página **Auditoría** (acción "restauró"), con el módulo, cuántos registros entraron, cuántos fallaron y cuántos se saltearon por ser duplicados. Por ejemplo:

> *ana@ejemplo.com restauró alojamiento (backup_propio) — 8 de 8 registros — 2026-08-02T14:30:00.000Z*

Esto permite responder después "¿cuándo se restauró este backup, y trajo todo bien?" sin depender de la memoria de nadie.

## ¿Y las copias automáticas de Supabase?

En el plan gratuito de Supabase, la disponibilidad y retención de backups automáticos puede cambiar; no hay que depender de eso para no perder datos. La exportación manual de arriba es la que garantiza tener siempre un `.json` bajo tu control, sin importar el plan de Supabase. Guardá esos archivos en un lugar aparte (Google Drive, disco externo, etc.), no solo en la computadora donde los descargaste.

## Restaurar en una cuenta nueva o después de un problema

1. Abrí el panel, iniciá sesión con un usuario que tenga acceso a la cuenta (tenant) correcta.
2. Andá a la sección del módulo correspondiente → **Importar backup** → elegí el `.json` exportado de ese mismo módulo.
3. Confirmá. Se crean como registros nuevos, asociados automáticamente a tu cuenta.
4. Revisá que la cantidad y los datos coincidan con lo esperado, y confirmá en Auditoría que quedó el registro de la restauración.

## Migrar desde la demo anterior (localStorage)

Es un caso distinto: no es "restaurar un backup propio de Supabase", sino traer datos de la demo vieja (`Panel-EYO-Plan-*.html`) por primera vez. Tiene su propio botón ("Migrar desde demo anterior") y su propia documentación — ver `docs/migracion-localstorage.md`, incluyendo cómo se evitan duplicados si se corre dos veces sin querer.
