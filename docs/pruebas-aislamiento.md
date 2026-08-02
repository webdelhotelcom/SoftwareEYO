# Prueba de aislamiento entre clientes

Este es el entregable obligatorio de la Fase 1: demostrar que un cliente no puede consultar, editar ni eliminar datos de otro. Se ejecuta una vez que exista un proyecto de Supabase real con el esquema aplicado.

## Preparación

1. Correr `supabase/testing/seed_two_test_tenants.sql` (ver instrucciones adentro del archivo) para crear **Cliente A** y **Cliente B**, cada uno con su usuario y un alojamiento propio.
2. Tener a mano el email/contraseña de ambos usuarios de prueba.

## Qué se prueba

Iniciando sesión como **Cliente A** (con su token de sesión real, usando la clave `anon` — igual que lo haría el navegador):

| # | Acción | Resultado esperado |
|---|---|---|
| 1 | `select * from properties` | Solo aparece "Alojamiento de A". El de B no aparece en la lista. |
| 2 | `select * from properties where id = '<id del alojamiento de B>'` (id conocido de antemano) | Cero filas — no es que dé error de permisos, directamente no existe para A. |
| 3 | `update properties set nombre='hackeado' where id = '<id del alojamiento de B>'` | Cero filas afectadas. El nombre de B no cambia. |
| 4 | `delete from properties where id = '<id del alojamiento de B>'` | Cero filas afectadas. El alojamiento de B sigue existiendo. |
| 5 | `insert into properties (tenant_id, nombre, ...) values ('<tenant de B>', ...)` | Rechazado por la política de RLS (`new row violates row-level security policy`). A no puede crear alojamientos a nombre de B. |
| 6 | `select * from tenants` | Solo aparece el tenant de A. |
| 7 | `select * from client_limits` | Solo aparece (si existe) la fila del tenant de A. |

Se repite la misma tabla logueado como **Cliente B**, apuntando ahora a los datos de A, esperando los mismos resultados (cero acceso cruzado en ningún sentido).

## Cómo se ejecuta en la práctica

Con las credenciales reales del proyecto, uso el cliente de Supabase JS (la misma librería que usa el panel) autenticado como cada usuario de prueba, y corro estas siete operaciones contra ambos. El resultado (qué filas trajo/afectó cada operación) queda documentado acá abajo, en esta misma sección, después de correrlo.

## Resultado

**Ejecutada el 2026-08-01, contra el proyecto real de producción (`ckbarfwqdnehqnpafzay`), después de aplicar las 4 migraciones.** Se crearon dos tenants de prueba (Cliente A / Cliente B), cada uno con un usuario real de Supabase Auth y un alojamiento propio, y se corrió lo siguiente usando el cliente de Supabase JS autenticado como cada usuario (la misma librería que usa `app/panel.html`):

| # | Prueba | Resultado obtenido |
|---|---|---|
| 1 | A lista sus alojamientos (`select * from properties`) | Solo "Alojamiento de A" — el de B no aparece. ✅ |
| 2 | B lista sus alojamientos | Solo "Alojamiento de B" — el de A no aparece. ✅ |
| 3 | B lista `tenants` | Solo ve "Cliente de prueba B", no el de A. ✅ |
| 4 | B lee el alojamiento de A por ID directo | 0 filas devueltas. ✅ |
| 5 | B intenta editar (`update ... set nombre`) el alojamiento de A | 0 filas afectadas — no cambió nada. ✅ |
| 6 | B intenta borrar (`delete`) el alojamiento de A | 0 filas afectadas — sigue existiendo. ✅ |
| 7 | B intenta crear un alojamiento nuevo con `tenant_id` de A | Rechazado: `new row violates row-level security policy for table "properties"`. ✅ |
| 8 | Se vuelve a leer el alojamiento de A después de todos los intentos de B | Nombre intacto, sin cambios. ✅ |
| 9 | Login real por la pantalla del panel (no llamada directa a la API) con el usuario de Cliente A | Entra correctamente, sidebar muestra su email y rol, badge de plan muestra "Plan Profesional · Cliente de prueba A", página Alojamientos muestra "1 de 15 alojamientos utilizados" y la tarjeta de "Alojamiento de A". Sin errores en consola. ✅ |

**Conclusión: ningún cliente pudo leer, editar, borrar ni crear datos a nombre del otro, en ningún caso.** El aislamiento por `tenant_id` + RLS funciona correctamente en la base real.

Los dos tenants de prueba quedan en la base hasta que se corra `supabase/testing/cleanup_two_test_tenants.sql` (y se borren a mano los 2 usuarios de prueba en Authentication → Users) — no interfieren con el uso normal del sistema mientras tanto.

## Actualización (2026-08-02): permisos por rol, no solo por tenant_id

La prueba de arriba (2026-08-01) demostró que un cliente no puede tocar los datos de **otro cliente**. Pero en la auditoría de seguridad del 2026-08-02 se encontró que, dentro de un mismo cliente, un **rol de bajo privilegio** (por ejemplo `limpieza`) sí podía editar y borrar alojamientos por la API directa — porque hasta ese momento la mayoría de las políticas RLS de escritura solo revisaban `tenant_id`, nunca el rol ni el permiso del usuario.

**Prueba en vivo que confirmó el problema (antes del fix):**

| # | Acción | Resultado obtenido |
|---|---|---|
| 1 | Usuario con rol `limpieza` (sin permiso `editar_alojamientos`) intenta `update properties set nombre=...` por la API, con su propio token | La fila se actualizó igual. ❌ La UI escondía el botón, pero la base de datos no lo impedía. |
| 2 | El mismo usuario intenta `delete` sobre un alojamiento de su propio tenant | Se borró igual. ❌ |

**Corrección:** migración `0019_permissions_enforcement.sql` — se reescribieron las políticas de insert/update/delete de las 21 tablas para exigir también `has_permission('clave_correspondiente')` (o `is_admin()` según el caso), no solo `tenant_id = current_tenant_id()`. Se agregaron ~47 claves de permiso nuevas y se sembraron los valores por defecto de cada rol para tenants existentes y futuros. Ver `docs/permisos.md` para el detalle de qué permiso protege cada acción.

**Reprueba en vivo después del fix (mismo usuario `limpieza`, mismo tenant, mismas dos acciones):**

| # | Acción | Resultado obtenido |
|---|---|---|
| 1 | `update properties set nombre=...` | 0 filas afectadas — rechazado por RLS. ✅ |
| 2 | `delete from properties where id=...` | 0 filas afectadas — rechazado por RLS. ✅ |
| 3 | Control: el mismo usuario admin del tenant hace la misma edición | Funciona normalmente. ✅ (la restricción es por permiso, no rota la función para quien sí lo tiene) |

**Prueba relacionada, también corregida el mismo día:** un usuario desactivado (`profiles.active=false`) podía seguir escribiendo datos si ya tenía una sesión abierta en el navegador (no se revisaba en cada consulta, solo al iniciar sesión). Se probó en vivo creando una tarea con una sesión ya desactivada — se creó igual. Corregido en `0020_deactivated_user_lockout.sql`: `current_tenant_id()`/`has_permission()` ahora exigen `active=true` en cada llamada, no solo al loguearse. Reprueba: la misma sesión ya no pudo crear la tarea, y el panel detecta la desactivación en un plazo máximo de 60 segundos y cierra la sesión automáticamente.

**Conclusión actualizada:** el aislamiento entre clientes (tenant_id) y la separación por rol dentro de un mismo cliente (permisos) están ambos aplicados y verificados a nivel de base de datos — no dependen de que el navegador coopere.

## Batería final de pruebas de seguridad (2026-08-02) — 2 tenants × 5 roles × XSS × límites

Última prueba de la corrección de auditoría, con 2 tenants descartables reales (uno con 5 usuarios de distinto rol, otro con 1 admin) y datos reales de por medio, todo por la API con las credenciales reales de cada usuario (no simulado, no revisión de código solamente).

| # | Prueba | Resultado obtenido |
|---|---|---|
| 1 | `admin` del tenant A edita un alojamiento del tenant A | 1 fila afectada. ✅ |
| 2 | `encargado` (tiene `editar_alojamientos`) edita el mismo alojamiento | 1 fila afectada. ✅ |
| 3 | `encargado` (NO tiene `eliminar_alojamientos`) intenta borrarlo | 0 filas, sin error — bloqueado por RLS. ✅ |
| 4 | `limpieza` (sin `editar_alojamientos`) intenta editarlo | 0 filas, error "new row violates row-level security policy". ✅ |
| 5 | `limpieza` intenta borrarlo | 0 filas, sin error — bloqueado. ✅ |
| 6 | `contador` (sin `editar_alojamientos`) intenta editarlo | 0 filas, error de RLS. ✅ |
| 7 | `propietario` lista alojamientos | Solo ve el suyo (1 de 2 que existían en el tenant) — el alcance por `owner_id` filtra el resto aunque sean del mismo tenant. ✅ |
| 8 | `propietario` edita un gasto de su propio alojamiento (permiso `editar_gastos`) | 1 fila afectada. ✅ (confirma la corrección de la migración 0022, ver más abajo) |
| 9 | Admin del **tenant B** consulta alojamientos filtrando explícitamente por el `tenant_id` del tenant A (id conocido de antemano) | 0 filas — ni siquiera pidiendo el tenant ajeno a propósito devuelve algo. ✅ |
| 10 | Admin del tenant B intenta editar un alojamiento del tenant A por su id | 0 filas, sin error. ✅ |
| 11 | Payload XSS real (`<img src=x onerror="...">`) guardado como concepto de un gasto, logueado como admin real por la pantalla del panel (no API directa) | Se renderiza como texto escapado (`&lt;img src=x onerror=...&gt;`) en la tabla de Gastos. El `onerror` nunca se disparó. ✅ |
| 12 | Límite de plan: tenant B (plan `inicial`, tope 5 alojamientos) — se insertan 6 de a uno | Los primeros 5 entran, el 6° es rechazado por el trigger server-side con "Alcanzaste el límite de 5 alojamientos de tu plan." ✅ |
| 13 | (Efecto colateral de armar la prueba) Se intentó crear un tenant con plan `profesional` (tope 3 usuarios) y cargarle 5 perfiles de una | El 4° perfil fue rechazado por el trigger de límite de usuarios — confirma que ese límite también es real, no solo el de alojamientos. ✅ |

**Hallazgo de esta batería, corregido en el momento:** la función que siembra permisos por defecto para tenants nuevos le daba a `propietario` el permiso `editar_gastos`, pero el bloque de backfill para tenants que ya existían (como la cuenta real del fundador) no lo tenía — mismo rol, resultado distinto según cuándo se hubiera creado el tenant. Corregido en `0022_fix_propietario_editar_gastos.sql` (backfill dirigido, no pisa configuraciones ya tocadas a mano) y en el propio `0019` (para que una instalación nueva desde cero quede consistente desde el principio). La prueba #8 de la tabla de arriba confirma que, después de la corrección, el permiso funciona.

**Conclusión final:** con datos reales de 2 tenants y 5 roles distintos, ningún rol pudo hacer más de lo que su permiso le permite, ningún cliente pudo tocar datos de otro (ni siquiera pidiéndolo explícitamente por id), un payload XSS real quedó neutralizado en pantalla, y los límites de plan (alojamientos y usuarios) se aplicaron en el servidor sin depender del navegador. Tenants de prueba limpiados después de la corrida.
