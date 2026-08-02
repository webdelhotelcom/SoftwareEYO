# Software EYO — Índice

Base de conocimiento tipo Obsidian del proyecto. Pensada para que alguien (vos mismo dentro de seis meses, u otra persona) pueda entender el sistema sin releer toda la conversación que lo construyó. Los enlaces `[[así]]` son notas de esta misma carpeta; abrí esta carpeta como vault en Obsidian si querés navegar en grafo.

Esto **no reemplaza** la documentación operativa de `docs/` (cómo instalar, cómo migrar datos, etc.) — la complementa con el panorama general y el porqué de las decisiones. Para instrucciones paso a paso, andá a `docs/`, no acá.

## Notas de esta carpeta

- [[Arquitectura]] — cómo está armado el sistema (multi-tenant, Supabase, Netlify, el archivo único).
- [[Modulos]] — los 20 módulos de negocio y en qué migración SQL nació cada uno.
- [[Seguridad]] — el modelo de permisos, RLS, XSS, headers — resumen de alto nivel (el detalle está en `docs/permisos.md`).
- [[Historia-y-decisiones]] — línea de tiempo del proyecto y por qué se tomó cada decisión importante.
- [[Estado-actual]] — qué está terminado, qué está pendiente, a la fecha de esta nota.
- [[Glosario]] — términos técnicos del proyecto explicados en una línea.

## Lo más importante para orientarse rápido

- **Un solo archivo hace todo el trabajo pesado del frontend:** `app/panel.html`. No hay build step, no hay framework — HTML/CSS/JS plano en un archivo, deployado tal cual.
- **Un solo proyecto de Supabase, plan Free, multi-cliente:** nunca un proyecto por cliente. La separación es lógica (`tenant_id` + RLS), no física.
- **Las migraciones SQL son la fuente de verdad del esquema**, en `supabase/migrations/`, numeradas y pensadas para correrse en orden, una sola vez cada una, para siempre (no se editan retroactivamente salvo para corregir un comentario desactualizado — la lógica ya aplicada en producción no se toca, se corrige con una migración nueva).
- **Nada se anuncia como "terminado" sin una prueba en vivo que lo confirme.** Es la regla de trabajo de todo este proyecto, no solo de la auditoría — ver [[Historia-y-decisiones]].
