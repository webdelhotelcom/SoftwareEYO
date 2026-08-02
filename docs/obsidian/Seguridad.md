# Seguridad

Ver también: [[00-Indice]] · [[Arquitectura]] · `docs/permisos.md` · `docs/pruebas-aislamiento.md`

Resumen de alto nivel de las capas de seguridad del sistema. El detalle operativo (cómo reconfigurar permisos, qué política protege qué tabla) vive en `docs/permisos.md` — esta nota es el mapa, no el manual.

## Las capas, de afuera hacia adentro

1. **Autenticación real** (Supabase Auth) — sin usuario/contraseña hardcodeado como en la demo vieja (`admin`/`1234`).
2. **Aislamiento por tenant** (`tenant_id` + RLS) — un cliente no puede ver ni tocar datos de otro cliente, verificado en vivo con 2 tenants reales.
3. **Permisos por rol, aplicados en la base de datos** (`has_permission()` + RLS) — no alcanza con ocultar un botón en pantalla; la política de la tabla exige el permiso igual. Ver `docs/permisos.md`.
4. **Alcance por dueño** (`current_owner_id()`) — el rol `propietario` ve solo lo suyo, no todo el tenant.
5. **Usuarios desactivados pierden acceso en el acto**, no solo en el próximo login.
6. **Sanitización de XSS** (`esc()`) — todo texto libre insertado en `innerHTML` pasa por esta función antes.
7. **Headers HTTP** (`app/_headers`) — CSP, `X-Frame-Options: DENY`, etc.
8. **Auditoría tamper-proof** (`audit_log`) — sin política de insert/update/delete directo para el cliente; solo se llena por triggers y por la función acotada `log_restore_event()`.

## El hallazgo más importante de la auditoría

Hasta el 2026-08-02, la capa 3 (permisos por rol) prácticamente no existía a nivel de base de datos — casi todas las políticas de escritura solo revisaban `tenant_id`, no el permiso. Se probó en vivo con un usuario de rol `limpieza` editando y borrando alojamientos por la API directa, sin pasar por la pantalla. Corregido en `0019_permissions_enforcement.sql`. Este fue el hallazgo que motivó todo el resto de la corrección de auditoría (Fases 1-10) — ver [[Historia-y-decisiones]].

## Cómo se prueba esto en la práctica

No con revisión de código solamente: con usuarios reales, tokens reales, y verificando **filas devueltas/afectadas**, no solo ausencia de error (un `UPDATE`/`DELETE` bloqueado por el `USING` de una política RLS devuelve 0 filas silenciosamente, no un error). El patrón de prueba (tenants descartables, roles reales, limpieza después) está documentado en detalle en `docs/pruebas-aislamiento.md`, incluida la batería final de la Fase 9.

## Límite consciente, no un descuido

El CSP de `app/_headers` necesita `'unsafe-inline'` en `script-src`/`style-src` porque toda la app es un único HTML con cientos de `onclick=` y estilos inline. Es una limitación aceptada a cambio de la simplicidad de "un solo archivo" (ver [[Arquitectura]]), documentada explícitamente en vez de dejarla como una sorpresa para quien audite el CSP más adelante.
