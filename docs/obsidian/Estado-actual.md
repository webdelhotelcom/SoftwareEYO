# Estado actual

Ver también: [[00-Indice]] · [[Historia-y-decisiones]] · [[Centro-de-Configuracion]] · [[Finalizacion-Automatica-Reservas]]

Foto al **2026-08-20**. La sección de abajo hasta "Terminado y verificado en vivo (hasta 2026-08-03)" es la foto original del 2026-08-03 (después del cierre de la corrección de auditoría de 12 fases, renombres, Personalización por cuenta, menú de cuenta rediseñado, Inteligencia de Precios Fase 1) — se dejó tal cual como registro histórico. Lo nuevo desde entonces está en la sección siguiente. Como cualquier nota de estado, esto se desactualiza — si estás leyendo esto mucho después, confiá más en `git log` y en los task lists activos que en esta lista.

## Terminado y verificado en vivo (2026-08-19 a 2026-08-20)

- **Centro de Configuración (Fase 3) publicado a producción** en Netlify (`dashing-conkies-92cb00.netlify.app`) — el Deploy Preview que estaba pendiente de aprobación se promovió directo a producción vía API de Netlify (`restore` del deploy ya revisado), sin volver a subir nada — así quedó exactamente lo que el usuario ya había mirado.
- **Caja (Modo Propietario) — dos arreglos entregados en producción, por fuera del trabajo de i18n en curso** (parcheados sobre el contenido ya publicado, sin mezclar el trabajo de idioma que seguía a medias):
  - Bug real encontrado y corregido: `payment_operations` no tenía columna `id`, y el trigger genérico de auditoría la exige — rompía todo movimiento de caja con "record 'new' has no field 'id'" (migración `0044`).
  - Campo "Concepto" del modal de movimiento de caja se capturaba en el formulario pero nunca se mandaba al servidor — quedaba invisible en Movimientos (migración `0045`, agrega `p_concepto` a `registrar_movimiento_caja`).
  - Función nueva: **eliminar una apertura de Caja cerrada** (botón rojo en el detalle del historial), con doble confirmación (diálogo + PIN de operador con permiso `administrar_operadores_caja`) y recálculo de `sena_parcial` de las reservas afectadas antes de borrar (migración `0046`, `eliminar_caja_propietario`).
- **Web EYO (sitio personal, `index.html`)** — ver [[Web-EYO-Sitio-Personal]] para el detalle completo: nuevo alojamiento "Emiliano", galerías nuevas de Grande/Medio, portada nueva de Nueva, sección Antes/Después ampliada (Grande y Almacén EYO, sin perder las fotos originales), y arreglo real de desborde horizontal en celular. Publicado en una cuenta de GitHub distinta a la original por un problema de permisos — **el link cambió** a `webdelhotelcom.github.io/EYOSoftware`.
- **Repositorio de Software EYO subido a GitHub, público:** `github.com/webdelhotelcom/SoftwareEYO` — antes solo existía local. Se revisó primero que ningún archivo versionado tuviera secretos reales (solo placeholders/comentarios de ejemplo). Incluyó todo lo pendiente: migraciones `0027`-`0046`, notas nuevas de Obsidian, skills de `.agents/`, y el traslado de `privacidad.html`/`terminos.html` a `app/`.
- **Página comercial de Software EYO publicada** en `https://software-eyo.netlify.app` (sitio Netlify aparte del panel, mismo repositorio) — decisión pendiente desde la auditoría de Fase 7 ("Todavía no" publicarla), retomada y publicada a pedido explícito del usuario. Se corrigieron primero dos links rotos (a `privacidad.html`/`terminos.html`, que se habían movido a `app/` en Fase 3) y las etiquetas de meta `canonical`/`og:url` que apuntaban a la web vieja. Los archivos, con nombres raros de descargas repetidas (`index (21).html`, `software (8).html`), se renombraron a `index.html`/`software.html`.

## Terminado y verificado en vivo (desde 2026-08-03 hasta 2026-08-18)

- **Caja profesional** (Modo Propietario): operadores con PIN propio, sesiones/turnos, arqueo, auditoría de Caja — ver `supabase/migrations/0036` a `0040`.
- **Causa real de "Salidas de hoy" vacío**: dos triggers en `reservations` (`BEFORE`/`AFTER UPDATE OF estado`) centralizan `checkout_real_at` y la creación de la tarea de limpieza para CUALQUIER camino que lleve a un estado de salida (no solo el botón de Recepción) — migración `0041`. POS agregado como método de pago visible en Caja — migración `0042`.
- **Rediseño responsive completo** (Fase 2): sistema `.mobile-data-card` reutilizable para Reservas/Huéspedes/Reportes en ≤480px (decidido pantalla por pantalla probando con contenido largo real, no por cantidad de columnas), Calendario rediseñado con barras `grid-column:span N` (una por reserva, nombre siempre visible), Resumen Mensual y Reportes corregidos (les faltaba `.table-wrap`, por eso desbordaban la página). Desplegado y confirmado en producción.
- **Centro de Configuración** (Fase 3): ver [[Centro-de-Configuracion]] — Ajustes reorganizado en 10 categorías maestro-detalle, modo oscuro/claro/sistema por usuario, Usuarios y Auditoría reparentadas adentro, Idioma (Beta, infraestructura real pero traducción parcial), Centro de Ayuda con 25 artículos + 9 tutoriales, legales movidos a `app/` con aviso de borrador. **En Deploy Preview de Netlify, pendiente de que el usuario lo revise en su dispositivo real antes de publicar a producción.**
- **Mercado dejó de mostrarse como BETA** — ya se considera función oficial (incluido en el mismo Deploy Preview de Fase 3).
- **Finalización automática de reservas vencidas** — ver [[Finalizacion-Automatica-Reservas]] — `pg_cron` diario, **ya activo en producción**.

## Terminado y verificado en vivo

- Los 20 módulos de negocio migrados a Supabase (ver [[Modulos]]).
- Aislamiento multi-tenant por `tenant_id` + RLS.
- Permisos por rol aplicados server-side en las 21 tablas (no solo en pantalla).
- Sesión de usuario desactivado bloqueada en el acto, no solo en el próximo login.
- Sanitización de XSS en las inserciones de `innerHTML`, con payloads reales probados sin ejecutarse.
- Headers de seguridad HTTP en Netlify (CSP, X-Frame-Options, etc.).
- Deduplicación en la migración desde la demo vieja + rastro de restauraciones en Auditoría.
- Documentación del repositorio (README, permisos, backup/restore, migración, pruebas de aislamiento) alineada con el estado real del sistema.
- Página comercial sin contenido inventado ni enlaces rotos (testimonio pendiente oculto, `og-cover.jpg` real, `privacidad.html`/`terminos.html` reales).
- Código muerto conocido eliminado (`save()`/`load()`/`saveAll()` sin llamadores).
- Batería final de seguridad (2 tenants × 5 roles × XSS × límites de plan) — ver `docs/pruebas-aislamiento.md`.
- Matriz de anchos de pantalla (375/768/1280px) sin desborde horizontal.
- Informe final de cierre de auditoría (12 fases) — `docs/cierre-auditoria-2026-08-02.md`.
- Nombre del software unificado a "Software EYO" y nombres de plan sin "Uruguay" (Plan Hotel, Plan Profesional), en el panel y en las páginas comerciales.
- Bandera `is_founder` por tenant (no por email hardcodeado) para mostrar "Plan Hotel - Founder" en la cuenta fundadora.
- Personalización por cuenta (nombre comercial, 2 colores, logo) — ver [[Personalizacion]].
- Menú de cuenta rediseñado: un único trigger fijo (avatar) arriba a la derecha en vez de correo/tuerca/cerrar sesión siempre visibles; en celular es una hoja inferior (bottom sheet) respetando `safe-area-inset` de notch/Dynamic Island; probado en 320/360/375/390/414/768/1024px y limpieza de datos al cerrar sesión.
- Inteligencia de Precios, Fase 1 (beta, solo Plan Hotel) — comparación de mercado, similitud de competidores, motor de recomendación con explicación del cálculo. Ver [[Inteligencia-de-Precios]] para alcance, arquitectura y lo que falta.

## Pendiente, documentado explícitamente como tal (no asumido como hecho)

- **Identidad visual propia de Software EYO** (Fase 4 del proyecto original de migración) — distinto de la Personalización por cliente ya implementada: esto era aplicar la marca propia del proyecto (no la de cada cliente) más allá de lo ya cargado. No se ha vuelto a retomar.
- **Prueba en un dispositivo/navegador real** (iPhone con Safari, Android con Chrome) — todo lo probado hasta ahora fue con motor Chromium simulando anchos de pantalla, nunca un dispositivo físico. Ver `docs/dispositivos-navegadores.md`. Sigue pendiente también para la Fase 3 (Centro de Configuración) recién construida.
- ~~Publicación de la página comercial~~ — **hecho el 2026-08-20**, ver sección de arriba. Ya no está pendiente.
- **Inteligencia de Precios, Fases 2+** (calendario de precios, simulador, alertas automáticas, historial/evolución con gráficos, aprendizaje con resultados propios) y la conexión oficial a Booking.com/Airbnb — explícitamente no iniciadas, a la espera de que el usuario las pida.
- ~~Publicar a producción el Centro de Configuración (Fase 3)~~ — **hecho el 2026-08-19**, ver sección de abajo. Ya no está pendiente.
- **i18n completo (Fase 4), EN CURSO** — traducir toda la interfaz a español/inglés/portugués de Brasil sobre la infraestructura `t()`/`data-i18n` ya construida en Fase 3 (marcado "Beta" mientras dura). Se hace módulo por módulo, en un orden fijo, cada uno cerrado por completo (cablear + EN + PT + verificación estática) antes de pasar al siguiente, sin pausar a preguntar entre medio — así lo pidió el usuario. **Hechos y verificados (13 de 20 + infraestructura)**: infraestructura compartida, Reservas, Calendario, Dashboard, Alojamientos, Propietarios, Huéspedes, Recepción, Habitaciones, Limpieza, Caja, Finanzas, Gastos, Reportes, Mensajes/WhatsApp, Pre-facturación, Mantenimiento, Usuarios y permisos, Auditoría. **Quedan, en este orden**: Mercado → Ajustes → Centro de Ayuda (el más grande, ~25 artículos largos) → cierre final (`validateI18n()` en 0, barrido estático de strings sueltos, QA visual en los 3 idiomas, recién ahí sacar el badge "Beta"). El diccionario (`I18N_ES`/`I18N_EN`/`I18N_PT` en `app/panel.html`) tiene 1.098 claves por idioma a esta altura, verificado en paridad completa (0 faltantes) tras cada módulo. No hubo prueba en navegador real con credenciales de Supabase en este entorno — verificación fue sintáctica + paridad de diccionario, la QA visual en los 3 idiomas queda para el cierre. Retomable directamente desde acá sin perder contexto: el plan completo con el orden de módulos y las 4 reglas de refuerzo está guardado en el historial de la sesión que lo empezó.
- **`hostal.html`** dentro del repo `webeyo` (ver [[Web-EYO-Sitio-Personal]]): reemplazo de fotos de "Habitación Grande" y "Habitación Medio" vía el array `HABITACIONES` (líneas ~911-942). Sigue en pausa — es una tarea distinta a la de `index.html` (que sí se completó el 2026-08-20, ver la nota).

## Cómo confirmar que esta lista sigue siendo cierta

`git log --oneline` en la raíz del repo — cada fase de la corrección de auditoría tiene su propio commit con el prefijo "Corrección de auditoría (Fase N)". Si hay commits más nuevos que no aparecen mencionados acá, esta nota quedó vieja.
