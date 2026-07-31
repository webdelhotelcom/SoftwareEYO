# Backup y restauración

Hay dos sistemas de backup separados mientras dura la migración por fases:

## 1. Datos que todavía viven en localStorage (Reservas, Gastos, Propietarios, Tareas)

Botones en la barra lateral del panel, sección **"Datos (todavía en este navegador)"**:

- **Exportar backup** — descarga un `.json` con todo lo que hoy sigue en localStorage.
- **Importar backup** — restaura ese `.json`. Pide confirmación porque reemplaza los datos actuales.

Esto es exactamente el mecanismo que ya existía en la demo original. Se mantiene igual hasta que estos módulos se migren a Supabase en la Fase 2 (en ese momento este backup deja de tener sentido y se retira).

## 2. Alojamientos (ya en Supabase)

Sección **"Alojamientos (Supabase)"** en la barra lateral:

- **Exportar alojamientos** — trae todos los alojamientos del cliente logueado directo de la base de datos (protegido por RLS: solo puede traer los del propio tenant) y los descarga en un `.json`.
- **Importar alojamientos** — restaura ese `.json`: inserta cada alojamiento como uno **nuevo** en Supabase (no pisa los existentes, para evitar perder datos por accidente). Si aparecen duplicados, se borran a mano desde el panel.

Gratis y manual: no depende de ninguna función paga de Supabase. Se recomienda exportar antes de cualquier cambio grande (por ejemplo, antes de una migración de datos o antes de subir una versión nueva del panel).

## ¿Y las copias automáticas de Supabase?

En el plan gratuito de Supabase, la disponibilidad y retención de backups automáticos puede cambiar; no hay que depender de eso para no perder datos. La copia manual de arriba es la que garantiza tener siempre un `.json` bajo tu control, sin importar el plan de Supabase. Guardá esos archivos en un lugar aparte (Google Drive, disco externo, etc.), no solo en la computadora donde los descargaste.

## Restaurar en una cuenta nueva o después de un problema

1. Abrí el panel, iniciá sesión con un usuario que tenga acceso a la cuenta (tenant) correcta.
2. Sección "Alojamientos (Supabase)" → **Importar alojamientos** → elegí el `.json` exportado.
3. Confirmá. Se crean como alojamientos nuevos, asociados automáticamente a tu cuenta (no hace falta indicar el `tenant_id` a mano: lo toma del usuario logueado).
4. Revisá que la cantidad y los datos coincidan con lo esperado.
