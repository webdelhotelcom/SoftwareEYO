# Cierre de la corrección de auditoría — 2026-08-02

Informe final de las 11 fases de corrección abiertas por la auditoría de seguridad independiente del mismo día. Cada fila tiene una prueba en vivo real detrás — ver `docs/pruebas-aislamiento.md` para el detalle de la batería de seguridad, y el historial de git (`git log`, commits con prefijo "Corrección de auditoría") para el código exacto de cada fase.

**Veredicto: listo para clientes reales**, sin hallazgos críticos ni altos abiertos. Salvedades no técnicas: sin prueba en dispositivo físico real, identidad visual propia pendiente, página comercial sin publicar por decisión del usuario.

## Tabla de cierre

| Fase | Estado | Evidencia | Archivo | Problema | Acción |
|---|---|---|---|---|---|
| 1 — Permisos por rol en RLS | Aprobado | Usuario `limpieza` bloqueado editando/borrando alojamientos vía API real; admin sin afectar. | `0019_permissions_enforcement.sql` | RLS solo revisaba `tenant_id`, no el permiso (hallazgo crítico). | 47 permisos nuevos + políticas de 21 tablas reescritas para exigir `has_permission()`. |
| 2 — Sesión de usuario desactivado | Aprobado | Sesión ya abierta de un usuario desactivado no pudo crear una tarea; auto-logout en ≤60s. | `0020_deactivated_user_lockout.sql` | Desactivar un usuario no cortaba una sesión ya iniciada. | Funciones clave exigen `active=true` en cada llamada, no solo al loguearse. |
| 3 — Sanitización XSS | Aprobado | 4 payloads reales en 8 módulos (Fase 3) + 1 payload adicional en Gastos vía UI real (Fase 9). Ninguno se ejecutó. | `app/panel.html` (`esc()`) | Decenas de `innerHTML` con texto libre sin escapar, incl. Auditoría. | Función `esc()` central aplicada en cada render, incluidos los popups `document.write()`. |
| 4 — Headers de seguridad | Aprobado | Cero violaciones de CSP en consola con el sitio en vivo; APIs externas cargan igual. | `app/_headers` | Sin headers de seguridad HTTP. | CSP + X-Frame-Options + Referrer-Policy + Permissions-Policy. `unsafe-inline` documentado como límite consciente. |
| 5 — Deduplicación y rastro de restauraciones | Aprobado | Ciclo real crear→exportar→borrar→restaurar (2/2 recuperados) + migración legacy con 1 duplicado real omitido. | `0021_restore_audit_trail.sql` | Migrar el mismo archivo dos veces duplicaba datos; restauraciones sin rastro en Auditoría. | Dedup por campos clave en los 6 módulos migrables + acción `RESTORE` en `audit_log`. |
| 6 — Documentación del repositorio | Aprobado | README y docs revisados contra el código real. | `README.md`, `docs/*.md` | La documentación describía el estado de la Fase 1 (2026-08-01). | Reescritos README y 4 docs; creado `docs/permisos.md`. |
| 7 — Página comercial | Parcial | Testimonio oculto (reversible); `og-cover.jpg` real; `privacidad.html`/`terminos.html` creados y enlazados. | `index (21).html`, `privacidad.html`, `terminos.html` | Testimonio con placeholder visible, imagen de redes rota, enlaces muertos. | Ocultar en vez de inventar. Video se dejó tal cual (ya tenía fallback honesto; ocultarlo rompía 2 botones reales). Página sigue sin publicarse — decisión del usuario. |
| 8 — Código muerto | Parcial | `save()`/`load()`/`saveAll()` confirmados sin llamador (grep) y eliminados. | `app/panel.html` | Funciones de `localStorage` de la demo vieja sin usar. | Eliminadas + comentario obsoleto corregido. Sin barrido exhaustivo de todo el archivo. |
| 9 — Batería final de seguridad | Aprobado | 2 tenants reales × 5 roles × aislamiento cruzado × XSS × límites de plan — 13 pruebas, todas con el resultado esperado. | `docs/pruebas-aislamiento.md` | — | Se encontró y corrigió de paso una inconsistencia real (rol `propietario` sin `editar_gastos` en tenants viejos) — `0022`. |
| 10 — Dispositivos y navegadores | No verificable | 375/768/1280px sin desborde horizontal, solo con motor Chromium simulado. | `docs/dispositivos-navegadores.md` | Sin acceso a Safari/WebKit, Firefox ni dispositivo físico real en este entorno. | Documentado honestamente como no verificado. |
| 11 — Base de conocimiento (Obsidian) | Aprobado | 6 notas interlincadas: arquitectura, módulos, seguridad, historia, estado actual, glosario. | `docs/obsidian/*.md` | — | Creadas, enlazadas desde el README. |

## Salvedades (no son hallazgos de seguridad)

1. **Sin prueba en dispositivo físico real** (iPhone/Safari, Android/Chrome) — recomendado antes de prometer "funciona en cualquier dispositivo" ampliamente.
2. **Identidad visual propia** (Fase 4 del plan original de migración) sigue sin retomarse.
3. **Página comercial sin publicar** — decisión explícita del usuario, no un bloqueo técnico.

Versión con diseño de la misma tabla, para lectura: se publicó como artefacto y PDF en la conversación donde se cerró esta corrección — pedir al asistente si hace falta regenerarlos.
