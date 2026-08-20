# Modo Propietario — conexión real a Reservas (plan aprobado, en implementación)

Ver también: [[00-Indice]] · [[Modulos]] · [[Historia-y-decisiones]] · [[Seguridad]] · [[Estado-actual]]

Nota de continuidad: esto resume el plan técnico **v5**, aprobado por el usuario, para la etapa "renombrar modos, simplificar Modo Propietario, conectar Reservas con Recepción/Habitaciones/Limpieza/Mantenimiento/Caja". Si estás retomando este trabajo en una conversación nueva, esta nota es el punto de partida — no hace falta releer todo el historial. El plan completo con el SQL exacto vive en `C:\Users\Orieles\.claude\plans\splendid-weaving-origami.md` (fuera del repo, en la máquina del usuario); acá queda la versión autocontenida para no depender de ese archivo.

## Restricción no negociable (repetida varias veces por el usuario)

**Todos los datos ya cargados son del usuario y no se tocan.** Verbatim: *"todos esos datos yo los cargue y son mios, no deben cambiarse, son del gmail orielesymama@gmail.com"*. Esto incluye especialmente las 6 filas de `room_types` y 6 de `rooms` cargadas a mano — nunca se borran ni se modifican. Toda migración de esta etapa es **aditiva** (`add column if not exists`, nunca `drop`/`truncate`/`delete` sin `where` puntual). El **Modo Administrador** (`grupo='propiedades'`) debe quedar **byte a byte igual** — mismas tablas (`rooms`/`stays`/`hk_tasks` vía `room_id`/`maint_tickets` vía `room_id`/`cash_sessions`), mismo HTML, mismos cálculos financieros. Cada función mode-aware nueva empieza con `if (grupoActual()==='hostal') return XxxPropietario();` y el bloque `propiedades` que sigue no se toca.

## Diagnóstico

`properties`/`reservations` (817 reservas, 8 alojamientos) es la única fuente real de datos operativos del Modo Propietario. Recepción, Habitaciones, Housekeeping, Mantenimiento y Caja nunca se conectaron a esos datos — siguen leyendo el modelo viejo (`rooms`/`room_types`/`stays`/`hk_tasks`/`maint_tickets`), vacío salvo las 6+6 filas mencionadas arriba.

Dos hallazgos verificados leyendo `app/panel.html` (no supuestos), clave para toda la implementación:

- **`reservations.sena_parcial`** (numeric) ya es el campo real de pago acumulado por reserva. La fórmula de saldo que usa hoy toda la interfaz (Finanzas, CSV, ficha de reserva — `calcRes()` en `panel.html:2021`, usos en `panel.html:2952,3335-3336,3843`) es `saldo = cobrado − sena_parcial`, donde `cobrado = precio − descuento − comisión de plataforma`. `cash_sessions` tiene 0 filas hoy — nunca se usó para pagos reales. Todo el diseño de Caja/idempotencia de esta etapa se apoya en `sena_parcial` como fuente de verdad, no en Caja.
- **`grupo` ya se envía siempre desde el frontend**: `propertyToDb`/`reservationToDb`/`expenseToDb`/`taskToDb`/`guestToDb` (líneas 2108, 2176, 2229, 2254, 7180) arman `grupo: data.grupo||grupoActual()` en los 5 casos — nunca dependen de un default de la base. Por eso se puede quitar el `default` a nivel de columna en Supabase sin tocar el frontend.
- `properties.estado` (`'activo'/'inactivo'`, usado por `badgeA()`) es el campo real de "¿está activo?" — se usa para exigir alojamiento activo en el trigger de solapamiento.

## Alcance de esta etapa

1. Renombrar "EYO Hostal"→"Modo Propietario", "Administrador de propiedades"→"Modo Administrador" (solo texto visible; `bizMode` interno no cambia).
2. Ocultar "Tipos de habitación" del nav en Modo Propietario (tabla/datos intactos).
3. Ampliar `properties` con 12 campos que hoy solo viven en `room_types` (categoría, descripción, camas, tipo de cama, baño, piso, A/C, TV, frigobar, cocina, estacionamiento, comodidades).
4. Migrar esos campos con **vista previa de solo lectura obligatoria** antes de copiar nada (solo coincidencias exactas no ambiguas, solo campos vacíos, `grupo='hostal'`).
5. Conectar Recepción/Habitaciones/Housekeeping("Limpieza")/Mantenimiento/Caja a datos reales, en una rama de código nueva y separada de la rama Administrador.
6. Check-in/check-out real con hora real (`checkin_real_at`/`checkout_real_at`), estados de origen restringidos, idempotente.
7. Tarea de limpieza automática al hacer check-out, sin duplicados, **sin retroactividad sobre las 817 reservas históricas**.
8. Conexión básica (no reconstrucción completa) de pagos de reserva ↔ Caja, con idempotencia real e importes validados en el servidor.
9. Trigger de no-solapamiento de fechas en Supabase, **solo para `grupo='hostal'`**.
10. Traducción visual Housekeeping→Limpieza y estados relacionados.

## Decisiones técnicas clave

### Estados que bloquean disponibilidad (lista única, Supabase + JS)
```
sena-parcial, sena-confirmada, confirmada, checkin-pendiente,
alojado, checkout-realizado, saldo-pendiente, finalizada
```
No bloquean: `consulta`, `esperando-sena`, `cancelada`, `no-presentada`. Fuente de verdad en SQL: `estados_bloqueantes_hostal()` (función `immutable`), espejada en una constante JS, con prueba de regresión que compara ambas.

### `grupo` — sin default a nivel de columna
Tras backfill/verificación (inventario de solo lectura primero), `grupo` queda `not null` + `check (grupo in ('hostal','propiedades'))` **sin `default`** — cada creación debe declararlo explícitamente (ya lo hace, ver hallazgo arriba). Un error de programación futuro se rechaza en vez de clasificar mal un dato.

### Saldo de la reserva — calculado en el servidor, sin inventar una fuente nueva
```sql
saldo_pendiente_reserva(p_reserva_id) = greatest(
  (precio - descuento - (comisión de plataforma si aplica)) - sena_parcial, 0)
```
Sin ningún `grant` (ni `public` ni `authenticated`) — solo invocable desde el interior de otras funciones `security definer` ya validadas. Cada pago nuevo registrado por Caja incrementa `sena_parcial` en la misma transacción, así el resto de la app sigue mostrando el mismo número sin duplicar nada.

### Idempotencia de pagos — tabla `payment_operations`
```sql
create table public.payment_operations (
  payment_operation_id uuid primary key,
  tenant_id uuid not null,
  reserva_id uuid references reservations(id),
  cash_session_id uuid references cash_sessions(id),
  tipo text not null check (tipo in ('sena','pago-parcial','pago-final',
    'cobro-checkin','cobro-checkout','anulacion','devolucion')),
  importe numeric not null,
  reversa_de uuid references payment_operations(payment_operation_id),
  created_at timestamptz not null default now(),
  created_by uuid
);
-- unique index parcial en reversa_de: como mucho una anulación por operación original
-- RLS habilitada, sin políticas para authenticated: solo se toca desde funciones security definer
```
`insert ... on conflict (payment_operation_id) do nothing` da unicidad real a nivel de motor (no una búsqueda-y-después-insertar, que pierde condiciones de carrera). El frontend genera el UUID con `crypto.randomUUID()` y lo guarda en `sessionStorage` antes de enviar el cobro. Cobros exigen importe estrictamente positivo; anulaciones exigen `p_reversa_de` válido del mismo tenant/reserva y calculan el importe inverso **en el servidor** (nunca confían en un número del navegador); ninguna operación puede dejar `sena_parcial` por debajo de cero; un cobro que supere el saldo pendiente (± tolerancia de redondeo) se rechaza en esta etapa (no hay "crédito a favor" todavía).

### Check-out transaccional
`registrar_checkout_propietario(p_reserva_id, p_cobro jsonb default null)` hace, en una sola función atómica: valida tenant/estado de origen (`alojado`), marca `checkout_real_at`+estado, crea la única tarea de limpieza (índice único parcial en `hk_tasks(reserva_id)`), y si hay cobro llama **directamente** (misma transacción, no una llamada HTTP aparte) a `registrar_movimiento_caja`. Si algo falla, todo se revierte.

### Trigger de solapamiento — solo Modo Propietario
Retorna sin validar nada si `grupo<>'hostal'` (Modo Administrador intacto). Si el estado de la reserva es no-bloqueante, permite datos incompletos (igual que hoy). Si es bloqueante, exige `propiedad_id`/`checkin`/`checkout`/`tenant_id`, `checkout>checkin`, y que el alojamiento exista, sea del mismo tenant, `grupo='hostal'` y `estado='activo'`. Compara rangos `daterange(checkin, checkout, '[)')` (checkout exclusivo, para permitir salida y llegada el mismo día en el mismo alojamiento).

### `estadoOperativo(propId, fechaISO)` — objeto, no una palabra
```
{ estadoPrincipal, saleHoy, llegaHoy, limpieza, mantenimiento, fueraDeServicio, proximaLlegada }
```
Una reserva futura lejana nunca convierte el estado de "hoy" en reservado (solo aparece como `proximaLlegada`). `saleHoy`/`llegaHoy` son banderas independientes que pueden coexistir con `estadoPrincipal='ocupado'`. Fechas siempre con `timeZone:'America/Montevideo'` explícito, nunca `toISOString()`.

## Migraciones (orden)

`0027` (columna `grupo`, sin default) → inventario de solo lectura → `0032` (finaliza `grupo`: not null + check, sin default) → `0028` (12 campos de Alojamientos) → `0029` (`hk_tasks`/`maint_tickets` + índices) → `0030` (timestamps reales de check-in/out) → `0031` (trigger de solapamiento) → `0033` (tabla `payment_operations`) → `0034` (RPCs: `registrar_checkin`, `saldo_pendiente_reserva`, `intentar_finalizar_reserva`, `registrar_movimiento_caja`, `registrar_checkout_propietario`) → `0035` (ajustes de RLS si la revisión de `pg_policies` encuentra algún gap) → vista previa de `room_types→properties` → copia real aprobada.

## Pendiente para otra etapa (documentado, no se hace ahora)

Automatización completa de apertura/cierre de Caja, conciliación bancaria, arqueos, reapertura de turnos; mantenimiento con rango de fechas futuro; realtime/suscripciones Supabase; vinculación de las 35 gastos de EYO Hostal a nivel de alojamiento individual; "crédito a favor" cuando un cobro supera el saldo; eventual tabla normalizada de movimientos de Caja en vez de jsonb.

## Cómo verificar que esta nota sigue vigente

Si estás retomando esto en una sesión nueva: primero correr `git log --oneline` para ver si ya hay commits de esta etapa (buscar migraciones `0027` a `0035` en `supabase/migrations/`), y revisar si `app/panel.html` ya tiene `registrar_checkout_propietario`/`estadoOperativo`/"Modo Propietario" en el texto visible. Si nada de eso existe todavía, el trabajo sigue en el punto de partida descrito acá.
