# Vencimiento de cuentas de prueba

Ver también: [[00-Indice]] · [[Estado-actual]] · [[Historia-y-decisiones]] · [[Seguridad]]

## Qué es

Un cliente potencial puede recibir una cuenta de prueba (plan Hotel, sin datos cargados) que **vence sola, de verdad, a nivel de base de datos** — no es un aviso visual que se pueda esquivar. Se usó por primera vez el 2026-09-02 para reemplazar la vieja cuenta demo de video (`Bestoic Demo`, con 200 reservas de ejemplo) por una cuenta vacía para un cliente real de prueba.

## Cómo funciona (migración `0054_tenant_trial_expiration.sql`)

- `tenants.trial_expires_at` — nullable. `NULL` = el cliente no vence nunca (todos los clientes reales de hoy). Con fecha = cuenta de prueba con vencimiento real.
- Las 4 funciones que gatean el acceso a **toda** la base de datos — `current_tenant_id()`, `has_permission()`, `is_admin()`, `current_owner_id()` — pasan a exigir además que `trial_expires_at is null or trial_expires_at > now()`. Mismo mecanismo exacto que ya usaba `0020_deactivated_user_lockout.sql` para `profiles.active=false`: apenas vence, Postgres deja de reconocerle tenant al usuario, así que **toda** política `tenant_id = current_tenant_id()` empieza a fallar de inmediato — no depende de que nadie lo desactive a mano ni de que el navegador cierre la sesión.
- Policy nueva `tenants_select_own_via_profile` — sin esto, la propia fila de `tenants` se volvería invisible apenas vence (porque `tenants_select_own` depende de `current_tenant_id()`, que ya dejó de reconocer al usuario) y el panel no podría ni mostrar el mensaje de "tu prueba venció". Mismo patrón que `profiles_select_self_always` (0020) para el caso de usuario desactivado.
- `app/panel.html`: banner de cuenta regresiva en vivo (`#trialBanner`, solo visible si `tenantRow.trial_expires_at` existe), chequeo en el login (`loginError` si ya venció), y el mismo watch de 60s que ya usaba "usuario desactivado" (`startActiveUserWatch()`) ahora también revisa el vencimiento y desloguea con aviso propio.

## Verificado en vivo (2026-09-02), no solo en el papel

Con la cuenta de prueba real (`prueba@bestoic.uy`), usando sus propias credenciales (nunca las del founder):
1. Login real → plan Hotel, banner con cuenta regresiva correcta, cuenta vacía.
2. `trial_expires_at` puesto en el pasado a mano → el watch de 60s sacó sola a la sesión sin intervención, y un login nuevo fue rechazado con el mensaje correcto.
3. **Regresión, la prueba más importante porque esto toca a todos los clientes reales**: la misma cuenta con `trial_expires_at=null` (simulando un cliente normal) → login, `current_tenant_id()`, `is_admin()`, lectura de datos, todo funciona exactamente igual que antes de esta migración.

## Decisión de diseño: por qué se reemplazó la demo de video

La cuenta `Bestoic Demo` (200 reservas de ejemplo, para grabar un video) quedó obsoleta para este caso de uso — un cliente de prueba real no debe ver datos inventados de otro. Se armaron 2 scripts de un solo uso (`supabase/one-off/2026-09-02_borrar_demo_bestoic.sql` / `2026-09-02_crear_trial_cliente.sql`), con una guarda explícita en el primero para que nunca pueda borrar por error el tenant de `orielesymama@gmail.com` (ver la regla en [[Historia-y-decisiones]]).

**Bug real encontrado al borrar la demo vieja**: el primer intento de `2026-09-02_borrar_demo_bestoic.sql` borraba `audit_log` **antes** que `profiles` — pero `profiles` está auditada (trigger que inserta en `audit_log` al borrar), así que el borrado de `profiles` repoblaba `audit_log` con filas nuevas, y el `delete from tenants` final fallaba por esa misma FK. Mismo error de orden que ya documentaba el comentario de `reset_tenant_orielesymama.sql`, cometido de nuevo en un script distinto — corregido: `audit_log` siempre al final de todos, sin excepción.

## Pendiente / hoja de ruta

- No hay alta automática de tenant al vencer o al pagar — sigue siendo manual (ver [[Pago-Sena-Plan-MercadoPago]]).
- No existe todavía un flujo de "extender" una prueba vencida — hoy la única forma es correr un `update` a mano sobre `trial_expires_at`.
