# Estado actual

Ver también: [[00-Indice]] · [[Historia-y-decisiones]]

Foto al **2026-08-02**, después del cierre de la corrección de auditoría (12 fases) y de la ronda de correcciones visuales/funcionales que siguió (renombres, Personalización por cuenta). Como cualquier nota de estado, esto se desactualiza — si estás leyendo esto mucho después, confiá más en `git log` y en los task lists activos que en esta lista.

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

## Pendiente, documentado explícitamente como tal (no asumido como hecho)

- **Identidad visual propia de Software EYO** (Fase 4 del proyecto original de migración) — distinto de la Personalización por cliente ya implementada: esto era aplicar la marca propia del proyecto (no la de cada cliente) más allá de lo ya cargado. No se ha vuelto a retomar.
- **Prueba en un dispositivo/navegador real** (iPhone con Safari, Android con Chrome) — todo lo probado hasta ahora fue con motor Chromium simulando anchos de pantalla, nunca un dispositivo físico. Ver `docs/dispositivos-navegadores.md`.
- **Publicación de la página comercial** — el usuario decidió explícitamente no publicarla todavía ("Todavía no"), aunque ya pasó revisión y las correcciones de la Fase 7.

## Cómo confirmar que esta lista sigue siendo cierta

`git log --oneline` en la raíz del repo — cada fase de la corrección de auditoría tiene su propio commit con el prefijo "Corrección de auditoría (Fase N)". Si hay commits más nuevos que no aparecen mencionados acá, esta nota quedó vieja.
