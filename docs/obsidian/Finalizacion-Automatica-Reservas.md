# Finalización automática de reservas vencidas

Ver también: [[00-Indice]] · [[Modulos]] · [[Historia-y-decisiones]]

Agregado el 2026-08-18, migración `0043_finalizacion_automatica_reservas.sql`. Antes, una reserva se pasaba a mano a "Finalizada" cuando terminaba la estadía — sobre todo en Modo Administrador (Alojamientos/Propietarios), que no tiene ningún flujo de Recepción/Checkout como Modo Propietario/Hostal y por lo tanto ningún mecanismo automático la movía de estado.

## Cómo funciona

Un `pg_cron` job (extensión de Postgres incluida en Supabase, gratis, no es un servicio nuevo) corre todos los días **11:00 hora Uruguay** (14:00 UTC) y llama a `private.finalizar_reservas_vencidas()`:

```sql
update public.reservations
set estado = 'finalizada'
where estado not in ('cancelada','finalizada')
  and checkout <= (now() at time zone 'America/Montevideo')::date;
```

- Se basa en `checkout` (columna `date`, la fecha planeada) — no en `checkout_real_at` (`timestamptz`, solo se completa vía el flujo de Recepción de Modo Propietario/Hostal, y las reservas de Modo Administrador nunca la tocan).
- El check-out de EYO es a las 10:00 — la automatización corre una hora después y finaliza el **mismo día** del checkout (`<=`, no `<`), no al día siguiente.
- **Idempotente por diseño**: el propio `where estado not in (...)` hace que correr el job todos los días nunca reprocese una fila ya finalizada.
- **No toca información financiera**: es un `UPDATE` de una sola columna. No escribe `sena_parcial`, no llama a `registrar_movimiento_caja`, no crea ni modifica `payment_operations`/`cash_sessions`.
- Queda registrado automáticamente en `audit_log` vía el trigger genérico que ya tiene `reservations` desde `0011_audit_log` — sin trabajo adicional, visible en Ajustes → Auditoría con `user_id`/`user_email` en null (no hay sesión de usuario en un job programado).

## Decisiones confirmadas explícitamente por el usuario (no asumidas)

Existe una función separada `intentar_finalizar_reserva()` (migración `0034`, se usa desde el flujo de cobro/checkout de Modo Propietario) que sí exige `estado='checkout-realizado'` + saldo pendiente en cero antes de finalizar. La primera versión de este diseño quería reutilizar ese mismo freno acá — el usuario aclaró dos cosas antes de aprobar:

1. **Sin chequeo de saldo**: en la operación real de EYO siempre se cobra todo antes de que el huésped se vaya — no hay reservas vencidas con saldo pendiente en la práctica.
2. **Sin restricción de estado inicial**: se finaliza desde cualquier estado no-cancelado (incluidos Consulta/Esperando seña) — si una reserva quedó en un estado temprano con el checkout ya vencido, es porque el huésped realmente estuvo.

`intentar_finalizar_reserva()` **no se tocó ni se modificó** — es un mecanismo distinto para un flujo distinto (Recepción), y esta automatización nueva es una función independiente.

## Seguridad de la función

- Schema **`private`** (nuevo, `create schema if not exists private`) — no `public`. Supabase/PostgREST solo expone vía API los schemas listados explícitamente (normalmente solo `public`), así que esta función de mantenimiento no es alcanzable por REST aunque alguien tuviera el nombre exacto.
- `security definer` + **`set search_path = ''`** con todo objeto referenciado con schema explícito (`public.reservations`, no `reservations`) — práctica actual recomendada por Supabase para funciones `SECURITY DEFINER`, evita que alguien "intercepte" la función creando un objeto con el mismo nombre en un schema que quede antes en el `search_path` de quien la ejecuta. Distinto del patrón `search_path=public` usado en funciones más viejas del proyecto (`intentar_finalizar_reserva`, `registrar_checkout_propietario`) — esas no se migraron a este patrón nuevo en esta ronda, eso sería un cambio aparte.

## TODO futuro documentado en el propio SQL

Tanto `'America/Montevideo'` como la hora de check-out (10:00, de ahí la ejecución a las 11:00) están hardcodeados. El día que Software EYO tenga clientes fuera de Uruguay o con otro horario de check-out, ambos valores deberían salir de columnas configurables por tenant/establecimiento (ej. `tenants.timezone`, `tenants.checkout_hour`) — no resuelto en esta ronda.

## Verificación antes de aprobar

Diagnóstico de solo lectura (`supabase/one-off/diagnostico_reservas_vencidas.sql`, mismo `WHERE` que la función) corrido primero contra producción: 13 reservas afectadas la primera vez, todas en estado "confirmada", checkouts vencidos desde diciembre 2025 en adelante — nada inesperado, ninguna `cancelada` se coló. Recién con ese resultado confirmado se aprobó correr la migración.

**Importante**: la función procesa TODOS los tenants y TODAS las reservas que cumplan el `WHERE` de una sola pasada — no se puede acotar a "una sola reserva de prueba" sin editarla. Por eso nunca se ejecuta manualmente contra producción para probar; cualquier prueba de comportamiento real se hace en local/staging con datos propios. Contra producción, lo único que se corre a mano es el diagnóstico de solo lectura.
