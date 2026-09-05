---
finance_md: "0.1"
model_name: "Bestoic — Panel de gestión hotelera (reservas, caja, comisiones, seña de plan)"
currency: UYU
secondary_units: [USD]
language: es
sources: [app/panel.html, netlify/functions/mp-plan-order.js, supabase/migrations]
---

# Convenciones financieras de Bestoic

## Context

Bestoic es un software de gestión para alojamientos (hoteles/apart-hoteles/
casas de alquiler), multi-tenant, un solo archivo `app/panel.html` +
Supabase. Este archivo describe las reglas financieras **ya existentes en
el código real** — no inventa ninguna regla contable nueva. Es la fuente de
verdad para las convenciones (moneda, redondeo, qué es un ingreso/gasto,
qué es una comisión) que cualquier agente o desarrollador debe seguir al
tocar código financiero de este proyecto — nunca reemplaza la lógica de
base de datos ni las validaciones server-side, que siguen viviendo en
`supabase/migrations/`.

Hay **dos negocios financieros completamente separados** en este repo, y
no deben mezclarse nunca:

1. **El negocio de los clientes de Bestoic** — sus reservas, gastos,
   comisiones, caja — vive en `reservations`/`expenses`/`cash_sessions` y
   se calcula en vivo, sin tablas propias de "transacciones". Es lo que
   cubre la mayor parte de este documento.
2. **El propio negocio de Bestoic (SaaS)** — la venta de licencias/planes
   del software — vive en `plan_deposit_payments`, es un flujo
   completamente aparte (Mercado Pago), documentado en su propia sección
   más abajo.

## Statement structure

Bestoic no tiene un P&L/balance formal — el módulo "Finanzas" del panel es
un resumen calculado en vivo, no un libro contable con período de cierre.
La cadena real de cálculo, por reserva y por gasto:

```
Reserva:  precio (bruto) − descuento − comisión de plataforma (OTA)
            = "cobrado"
          cobrado − seña_parcial (todo lo ya cobrado, no solo la 1ra seña)
            = saldo pendiente real (ver advertencia en Ambigüedades)

          Si NO es modo Hostal (administra propiedades de terceros):
            comisión de gestión = bruto × comisionPct (config. por propiedad, default 10%)
            depósito al propietario = bruto × 40% (fijo, ver Ambigüedades)

Finanzas (agregado del período, filtrado por año):
  bruto total     = Σ precio de reservas no canceladas
  neto ("cobrado")= Σ (precio − descuento − comisión plataforma)
  gastos          = Σ expenses.monto
  resultado       = neto − gastos                         (modo Hostal/propio)
  resultado       = neto − gastos − comisión de gestión    (modo Administrador, es el resultado del PROPIETARIO)
```

Caja (Modo Propietario) es un libro de movimientos aparte, que se
**reconcilia** contra lo cobrado en las reservas — nunca es una segunda
fuente de ingresos que se sume por separado en el Dashboard/Finanzas
(esto está en el propio texto de ayuda de la app, no es una interpretación
mía).

## Units & sign convention

- **Moneda primaria: UYU (pesos uruguayos), única, hardcodeada** para todo
  el módulo operativo (reservas, gastos, caja) — no hay columna `currency`
  en ninguna de esas tablas. `fmt()`/`formatCurrency()` en `app/panel.html`
  siempre pasan `'UYU'` para este módulo.
- **Redondeo: pesos enteros** (`Math.round()`) para reservas/gastos/caja —
  nunca centavos en esta parte del sistema.
- **Excepción real, ya existente: Pre-facturación (comprobantes internos,
  sin validez fiscal DGI) SÍ es multi-moneda (UYU/USD), con 2 decimales**
  (`invMoney()`, columnas `numeric(12,2)`). Los totales de UYU y USD se
  mantienen **siempre separados**, nunca convertidos ni sumados entre sí.
- Montos como `precio`, `descuento`, `monto` (gastos) se guardan como
  **magnitudes positivas** y se restan explícitamente en cada fórmula —
  esto es una convención por uso consistente en todo el código, **no** un
  `check` de la base de datos (no hay ningún `check (monto >= 0)` en
  `expenses`). Si se agrega una función nueva que toca estos campos,
  seguir la misma convención (nunca un monto negativo).
- **Excepción con signo real y sí forzado por diseño: los movimientos de
  Caja.** `cash_sessions.movimientos` sí lleva signo (ingresos positivos,
  egresos negativos), y ese signo **lo decide siempre el servidor**, nunca
  el navegador — tanto para altas manuales (`ingreso-manual`/
  `egreso-manual`) como para anulaciones (el importe de una anulación se
  calcula server-side como `-importe_original`, nunca aceptado del
  cliente).
- `metodo_pago` de Caja es una lista cerrada, server-side:
  `efectivo | transferencia | tarjeta | otro` — nunca texto libre, porque
  `calcular_expected_cash()` depende de reconocer exactamente `efectivo`.

## Currency & FX

- Multi-currency real, pero **acotado y nunca automático**: solo dos
  lugares del sistema salen de UYU puro.
  1. **Pre-facturación** (arriba) — UYU/USD, nunca convertidos entre sí.
  2. **Precio de los planes de Bestoic (SaaS)** — definido en USD
     (`PLAN_PRICES_USD` en `mp-plan-order.js`), cobrado en UYU vía Mercado
     Pago con un tipo de cambio **hardcodeado y duplicado a mano** en dos
     archivos: `const exchangeRate = 41` en `software.html`/`index.html`
     (solo para mostrar el precio en pesos al visitante) y
     `EXCHANGE_RATE = 41` en `mp-plan-order.js` (el que realmente calcula
     el cobro). **No hay ningún mecanismo que los mantenga sincronizados
     automáticamente** — si uno cambia sin el otro, el precio mostrado y
     el precio cobrado divergen. Documentado como riesgo conocido, no
     resuelto — cualquier cambio al tipo de cambio tiene que tocar los dos
     archivos a mano.
- El módulo operativo (reservas/gastos/caja) **no tiene ningún concepto de
  FX** — es UYU puro, sin excepción.

## Comisiones (propiedades administradas por Bestoic)

- `properties.comisión_pct` — porcentaje de gestión, **configurable por
  propiedad**, default 10%, editable desde el formulario de la propiedad.
- Si el grupo de la reserva es `hostal` (modo "propiedades propias, no de
  terceros"): comisión de gestión = 0, depósito al propietario = 0 — el
  resultado neto es el ingreso completo del propio negocio.
- Si no: comisión de gestión = `bruto × comisiónPct` (variable).
- **Depósito al propietario = `bruto × 40%`, fijo, independiente de
  `comisiónPct`** — ver Ambigüedades abajo, es una inconsistencia real del
  sistema, no una regla de negocio confirmada como intencional.
- `tiene_comision_plat`/`comisión_plat_pct` en la reserva es una comisión
  **distinta**: la que cobra la plataforma externa (Booking/Airbnb), no la
  de gestión de Bestoic.

## Caja (arqueo, apertura/cierre)

- `expected_cash` = efectivo inicial + movimientos con `metodo_pago='efectivo'`
  (con signo), **nunca** incluye transferencia/tarjeta/otro.
- `difference` = `declared_cash − expected_cash`. Cualquier diferencia
  distinta de cero **exige una observación obligatoria** para poder cerrar
  la caja — el cierre se rechaza sin ella.
- Sobrepago al cobrar una reserva: rechazado si el importe supera el saldo
  pendiente **+ 1 peso de tolerancia** (redondeo acumulado de
  `Math.round()` en los pasos previos) — nunca se acepta un cobro que
  exceda claramente lo que se debe.
- El cierre "administrativo" (cuando el operador original no está
  disponible) **nunca inventa un arqueo**: si no se declara `declared_cash`,
  esa columna queda en `null`, nunca se asume "declarado = esperado".

## Plan de Bestoic — seña de la venta del propio SaaS

Tabla `plan_deposit_payments`, completamente aparte del negocio de los
clientes (sin `tenant_id`, no es multi-tenant — el que paga es un
prospecto, no un tenant existente todavía):

- `plan_price_usd`/`exchange_rate` se **congelan en el momento del cobro**
  y nunca se recalculan después, aunque el precio de lista o el tipo de
  cambio cambien más adelante — son una foto histórica de esa venta
  puntual.
- `deposit_percentage` **hoy es siempre exactamente 50** en la práctica
  (único valor que manda el único llamador, `mp-plan-order.js`), pero el
  esquema de la base permite cualquier valor entre 1 y 100 — no hay ningún
  `check`/regla que lo fije en 50. Ver Ambigüedades.
- El servidor **nunca confía en un precio/total que mande el navegador** —
  recalcula todo desde su propia copia de `PLANS`/`MODULES` antes de crear
  cualquier orden de cobro, y rechaza (nunca cobra un monto parcial o
  inventado) cualquier configuración cuyo excedente de módulos/
  alojamientos/usuarios no tenga un precio definido todavía
  (`EXTRA_MODULE_PRICE_USD`/`EXTRA_PROPERTY_PRICE_USD`/`EXTRA_USER_PRICE_USD`,
  actualmente `null` — decisión comercial pendiente, no un dato faltante
  por error).

## Ambigüedades / inconsistencias reales encontradas — documentadas, no corregidas

Por instrucción explícita: reportarlas y dejarlas registradas acá en vez de
corregir el código ahora. Cualquiera de estas 5 puede ser una decisión de
negocio real (y este documento no debe asumir cuál) o un bug — queda para
una decisión aparte.

1. **Depósito al propietario (40% fijo) vs. comisión de gestión
   (`comisiónPct`, configurable, default 10%) no son complementarios.**
   `calcRes()` calcula los dos de forma completamente independiente sobre
   el mismo `bruto` — si se edita `comisiónPct` de una propiedad (la UI lo
   permite), el 40% del depósito no se ajusta. Los dos números dejan de
   sumar un reparto consistente de `bruto`.
2. **Dos fórmulas de "saldo pendiente" distintas conviven.** La correcta
   (`cobrado − sena_parcial`, la misma que usa el RPC servidor
   `saldo_pendiente_reserva()`) se usa en la mayoría del código. Pero el
   dashboard de Finanzas ("Reservas con saldo pendiente") usa por error
   `calcRes(r).saldo`, que es un **50% fijo del bruto** (pensado para
   mensajes de "seña/saldo" en WhatsApp, no para saber cuánto falta cobrar
   de verdad) — puede mostrar un número sin relación con lo realmente
   adeudado.
3. **`plan_deposit_payments.deposit_percentage` es schema-flexible (1-100)
   pero de hecho siempre 50** — nada en la base impone ese 50, solo la
   ausencia de otro llamador.
4. **Dos granularidades de redondeo conviven** según el módulo (panel:
   pesos enteros; Pre-facturación: 2 decimales) — no es un bug, pero es
   fácil asumir por error que hay una sola regla global de redondeo.
5. **Mismatch menor de default**: el formulario de reserva sugiere 15% de
   comisión de plataforma por defecto (`||15` en el JS), pero la columna
   de la base tiene `default 0`. Si el JS no corre por algún motivo, el
   default real termina siendo 0%, no 15%.

## Glosario

- **`sena_parcial`**: acumulador de TODO lo efectivamente cobrado contra
  una reserva (no solo el primer pago/seña) — a pesar del nombre, incluye
  cualquier pago posterior también.
- **"Cobrado" (`calcRes(r).cobrado`)**: `precio − descuento − comisión de
  plataforma` — el neto que le queda a Bestoic/al propietario antes de
  restar `sena_parcial`. No es lo mismo que "ingreso reconocido" en un
  sentido contable formal; es simplemente el neto de la reserva.
- **Modo Hostal vs. Modo Administrador**: Hostal = propiedades propias (sin
  comisión de gestión ni depósito a terceros); Administrador = se
  gestionan propiedades de otros dueños (con comisión y depósito).
