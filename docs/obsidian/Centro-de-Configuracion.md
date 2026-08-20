# Centro de Configuración (Fase 3)

Ver también: [[00-Indice]] · [[Personalizacion]] · [[Estado-actual]] · [[Historia-y-decisiones]]

Agregado el 2026-08-18. Ajustes dejó de ser una página larga de 5 cards y pasó a ser un verdadero Centro de Configuración: 10 categorías en un layout maestro-detalle (desktop: dos columnas siempre visibles; mobile: lista de categorías → detalle → "← Ajustes"). Estado al cierre de esta nota: **implementado y probado, corriendo en un Deploy Preview de Netlify, pendiente de aprobación del usuario en su dispositivo real antes de pasar a producción.**

## Las 10 categorías

General (nombre comercial + logo) · Apariencia (tema) · Idioma (Beta) · Cuenta y seguridad · Usuarios y permisos · Auditoría · Recuperación (antes "Copias de seguridad") · Obtener ayuda · Mejorar plan · Más información.

## Modo oscuro/claro/sistema

- Preferencia **por usuario, no por navegador**: `localStorage` con clave `eyo_theme:<uid>` (namespaced por el uid autenticado) — una computadora compartida entre empleados no hereda el tema de quien la usó antes. Default: `system`.
- `'system'` nunca se colapsa a un valor resuelto al guardar — se reevalúa contra `matchMedia('(prefers-color-scheme: dark)')` cada vez, y reacciona en vivo si cambia el tema del sistema operativo.
- Sin flash de contenido (FOUC): script inline al principio de `<head>`, antes de pintar — usa un puntero no-namespaced `eyo_last_uid` como mejor estimación mientras el login real (asíncrono) todavía no resolvió; se corrige solo apenas `currentUser` está disponible.
- **Cambiar de tema no reconstruye la página** (se descartó `refreshPage()` genérico a propósito, en una corrección del usuario durante el plan): las variables CSS se aplican de inmediato, y solo se re-renderizan puntualmente los 9 gráficos Chart.js montados (vía un registro `chart id → función dueña`) y el Calendario si está activo — un modal/formulario abierto con texto sin guardar nunca se pierde al cambiar de tema.
- PDF, impresión y `buildReportDoc()` (export de Reportes/Resumen Mensual) quedan **siempre en claro**, sin importar el tema activo del usuario que exporta — `data-theme="light"` forzado explícitamente en el documento exportado.

## Usuarios y permisos / Auditoría — reparentadas, no navegación

Se sacaron del menú principal y pasaron a vivir REALMENTE dentro de Ajustes (no un link que navega a otra página): sus `<div>` de página completos se mueven una sola vez (`appendChild`) hacia el panel de contenido de Ajustes, y se les saca la clase `.page` para que dejen de participar del barrido global `document.querySelectorAll('.page')` que hace `showPage()` en cada navegación — si no se les sacaba esa clase, ese barrido las hubiera tapado por error al navegar a cualquier otra pantalla estando abiertas dentro de Ajustes. `renderUsersPage()`/`renderAuditPage()` no se tocaron — mismos ids internos, mismas funciones, mismos datos.

El gate de permiso (`can('administrar_usuarios')`) se revisa antes de mostrar la categoría o cargar sus datos — no solo se oculta el botón. La frontera de seguridad real sigue siendo RLS en Supabase, como siempre en este proyecto: esto solo evita el camino normal por interfaz, nunca fue pensado como la protección real.

## Personalización — colores retirados, ver [[Personalizacion]]

Los selectores de color principal/menú lateral se sacaron de la interfaz (General quedó con nombre + logo únicamente). Detalle completo de la migración de esa decisión en [[Personalizacion]].

## Idioma — Beta, infraestructura real pero alcance parcial

Selector funcional (Español LATAM / English US / Português BR), namespaced por usuario igual que el tema (`eyo_lang:<uid>`, default `es`). Infraestructura `t(key, fallback)` + 3 diccionarios (`I18N_ES`/`I18N_EN`/`I18N_PT`) + `applyTranslations()` para nodos estáticos marcados `data-i18n`.

**Alcance real de esta ronda**: solo se migraron las tablas ya centralizadas del código (estados de reserva, roles, y un puñado de textos estáticos de prueba) — no la interfaz completa (eso son ~1.800-2.500 strings repartidas en 50 funciones de render, 288 `showToast`, 40 `alert`/`confirm`, exports PDF/CSV/Excel — tamaño comparable a toda la Fase 2 responsive). Por eso la categoría se muestra marcada como **"Idiomas — Beta"** con aviso de "traducción parcial" — nunca se presenta como terminada. La traducción completa queda pendiente, para un plan aparte cuando el usuario lo pida.

## Centro de Ayuda

Manual completo dentro de la app (Ajustes → Obtener ayuda): buscador + filtro por categoría + 25 artículos (`para qué sirve` / `cómo usarlo` / `paso a paso` / `errores frecuentes` / `consejos` por cada uno) cubriendo todos los módulos reales de la app — no solo una selección — más 9 tutoriales concretos con pasos escritos referenciando funciones reales del código (`openNewReservation()`, `openCheckin()`, etc.). Preparado para video más adelante (campo `videoSlot`, sin integrar ninguna plataforma todavía).

## Más información / legales

`terminos.html` y `privacidad.html` se **movieron** (no copiaron) de la raíz del repo a `app/` — antes no se desplegaban en absoluto (solo se publica el contenido de `app/`); ahora es la única copia real, evitando que quedaran dos versiones que se desincronizan con el tiempo. Se les agregó un aviso visible de "Borrador sujeto a revisión legal" (no habían sido revisados por un profesional). "Acerca de EYO" no inventa versión ni datos de contacto que no existen en el proyecto.

## Mejorar plan

Placeholder puro: "Beta/Próximamente", sin ninguna integración de pago (nada de Stripe/Mercado Pago/checkout/suscripciones) — solo la sección preparada visualmente.

## Verificación realizada

Sin capturas de pantalla reales (el tool de screenshots está roto en este entorno de desarrollo) — verificación vía DOM real en el Browser pane: los 3 modos de tema con gráficos/calendario montados, formulario abierto no pierde texto al cambiar de tema, 3 escenarios de permisos (admin / rol limitado con el permiso / rol sin el permiso) para Usuarios y Auditoría, shell mobile y desktop, `buildReportDoc()` nunca hereda oscuro, contraste del acento heredado de una configuración de marca vieja validado contra sus usos reales (botón/link/badge, no solo "acento vs fondo" en abstracto).

**Deploy**: primero un Deploy Preview de Netlify con `draft=true` (la URL de producción nunca se tocó durante el desarrollo) — confirmado en vivo que producción seguía sirviendo el build anterior mientras el preview ya tenía el código nuevo. Publicación a producción pendiente de que el usuario lo revise en su dispositivo real y apruebe.

## Archivos modificados

Todo en `app/panel.html` (bloque `<style>`, shell de Ajustes, funciones nuevas `applyTheme()`/`getChartPalette()`/`t()`/`HELP_ARTICLES`/etc.) + `app/terminos.html` + `app/privacidad.html` (movidos desde la raíz del repo).
