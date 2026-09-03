# Bestoic — Índice

Base de conocimiento tipo Obsidian del proyecto. Pensada para que alguien (vos mismo dentro de seis meses, u otra persona) pueda entender el sistema sin releer toda la conversación que lo construyó. Los enlaces `[[así]]` son notas de esta misma carpeta; abrí esta carpeta como vault en Obsidian si querés navegar en grafo.

Esto **no reemplaza** la documentación operativa de `docs/` (cómo instalar, cómo migrar datos, etc.) — la complementa con el panorama general y el porqué de las decisiones. Para instrucciones paso a paso, andá a `docs/`, no acá.

## Notas de esta carpeta

- [[Arquitectura]] — cómo está armado el sistema (multi-tenant, Supabase, Netlify, el archivo único).
- [[Modulos]] — los 20 módulos de negocio y en qué migración SQL nació cada uno.
- [[Seguridad]] — el modelo de permisos, RLS, XSS, headers — resumen de alto nivel (el detalle está en `docs/permisos.md`).
- [[Historia-y-decisiones]] — línea de tiempo del proyecto y por qué se tomó cada decisión importante.
- [[Personalizacion]] — nombre comercial, colores y logo por cuenta: decisión técnica, estructura de datos y seguridad. **Los colores se retiraron en Fase 3** — ver [[Centro-de-Configuracion]].
- [[Inteligencia-de-Precios]] — módulo beta (solo Plan Hotel): comparación de precios de mercado, similitud de competidores, motor de recomendación.
- [[Modo-Propietario-Conexion-Reservas]] — plan técnico aprobado (v5), renombrar modos, simplificar Modo Propietario, conectar Reservas con Recepción/Habitaciones/Limpieza/Mantenimiento/Caja, con Modo Administrador intacto.
- [[Login-Externo-Google-Microsoft]] — "Continuar con Google/Microsoft" vía Supabase Auth: código listo pero **pausado y oculto**, trancado en la configuración de Google Cloud Console/Microsoft Entra ID.
- [[Centro-de-Configuracion]] — Fase 3: Ajustes reorganizado en 10 categorías (maestro-detalle), modo oscuro/claro/sistema por usuario, Usuarios y Auditoría reparentadas adentro, Idioma (Beta), Centro de Ayuda con 25 artículos, legales. En Deploy Preview, pendiente de aprobación en producción.
- [[Finalizacion-Automatica-Reservas]] — `pg_cron` diario que pasa a "Finalizada" toda reserva vencida (excepto canceladas), sin intervención manual — ya activo en producción.
- [[Vencimiento-Cuentas-Prueba]] — cuentas de cliente de prueba con vencimiento real de 24hs a nivel de base de datos, no solo un aviso visual. Reemplazó la vieja cuenta demo de video.
- [[Pago-Sena-Plan-MercadoPago]] — botón de pago de la seña del plan (Mercado Pago, Checkout Pro/Orders API) en la página comercial — primer backend real del proyecto (Netlify Functions). Implementado y commiteado, deploy pendiente de que Netlify se reactive.
- [[Web-EYO-Sitio-Personal]] — proyecto aparte (no es Bestoic): el sitio personal de Orieles (`D:\Ori\webeyo`) y el micrositio de reservas `hostal.html`, publicados en **dos repos de GitHub distintos** (uno de ellos, `webdelhotelcom.github.io`, ni siquiera está clonado localmente). Migrado a una cuenta de GitHub nueva por problema de permisos con la original; contenido, fotos y arreglo responsive actualizados 2026-08-20 y 2026-08-21.
- [[Productividad-Ori]] — séptimo producto EYO, de uso personal (no comercial): app de calendario/productividad/cronómetro/gimnasio/estadísticas (Next.js + Supabase, `D:\Ori\productividad-ori`). Ya tiene código real y en producción — incluye un módulo de Nutrición completo (agregado 2026-08-20). Ver la memoria de sesión del proyecto para el detalle técnico; esta carpeta de notas es la de Bestoic, no la suya propia.
- [[Estado-actual]] — qué está terminado, qué está pendiente, a la fecha de esta nota.
- [[Glosario]] — términos técnicos del proyecto explicados en una línea.

## Lo más importante para orientarse rápido

- **Un solo archivo hace todo el trabajo pesado del frontend:** `app/panel.html`. No hay build step, no hay framework — HTML/CSS/JS plano en un archivo, deployado tal cual.
- **Un solo proyecto de Supabase, plan Free, multi-cliente:** nunca un proyecto por cliente. La separación es lógica (`tenant_id` + RLS), no física.
- **Las migraciones SQL son la fuente de verdad del esquema**, en `supabase/migrations/`, numeradas y pensadas para correrse en orden, una sola vez cada una, para siempre (no se editan retroactivamente salvo para corregir un comentario desactualizado — la lógica ya aplicada en producción no se toca, se corrige con una migración nueva).
- **Nada se anuncia como "terminado" sin una prueba en vivo que lo confirme.** Es la regla de trabajo de todo este proyecto, no solo de la auditoría — ver [[Historia-y-decisiones]].
