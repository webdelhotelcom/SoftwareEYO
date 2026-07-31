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

_(Se completa cuando el proyecto de Supabase esté creado y el esquema aplicado — ver docs/supabase-setup.md)._
