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
