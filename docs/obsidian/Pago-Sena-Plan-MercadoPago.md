# Pago de la seña del plan (Mercado Pago)

Ver también: [[00-Indice]] · [[Estado-actual]] · [[Historia-y-decisiones]] · [[Arquitectura]]

## Qué es (y qué NO es)

Un botón **"Pagar seña y empezar"** en `software.html` (la página comercial, sección de planes), solo en **Plan Inicial** (USD 75, seña del 50% de USD 150) y **Plan Profesional** (USD 250, seña del 50% de USD 500) — los dos únicos con precio fijo. Plan Hotel y Desarrollo Personalizado, sin precio cerrado, siguen yendo por WhatsApp como antes.

Es plata que un **prospecto** le paga a **Bestoic** por la licencia del software (50% para empezar, 50% al entregar) — **no** tiene nada que ver con que un hotel-cliente le cobre a sus huéspedes por una reserva. Cuando el pago se confirma, el founder crea la cuenta a mano (ver [[Vencimiento-Cuentas-Prueba]]) — no hay alta automática de tenant.

**Este malentendido casi hace que se construyera lo equivocado** — ver la entrada de [[Historia-y-decisiones]] del 2026-09-02: el pedido original de 16 pasos del usuario describía cobros huésped-a-hotel dentro del panel (Payment Brick, tabla `mp_payments` atada a reservas, botón en el detalle de una reserva) — se investigó y se diseñó un plan completo para eso antes de que el usuario aclarara que no era lo que quería. Ese diseño quedó documentado como referencia histórica (marcado "SUPERADO") en el archivo de planes de la sesión, por si el pedido de cobros huésped-a-hotel se retoma en serio alguna vez.

## Por qué Orders API y no Preferences (Checkout Pro clásico)

Mercado Pago trata `POST /checkout/preferences` como el flujo **legacy**. La skill oficial `mp-integrate` de Anthropic/MercadoPago (usada para la investigación inicial) dice *"Checkout Pro: cannot use Orders API; only preferences mode allowed"* — **esto está desactualizado**. Se verificó directo contra la documentación oficial de Mercado Pago (no se confió a ciegas ni en la skill ni en la corrección del usuario sin comprobarla) y dice textual: *"The Preferences API will continue to be supported, but new features will only be available in the Orders API. If you are starting a new integration, use the Orders API."* — confirmado, se construyó con `POST /v1/orders`.

**Lección para cualquier trabajo futuro con Mercado Pago en este proyecto: no confiar en esa skill para decisiones de qué endpoint/API usar sin verificar contra la documentación oficial vigente primero.**

## Arquitectura (primer backend real de este proyecto)

Hasta este pedido, Bestoic no tenía **ningún** backend propio — todo era Supabase + HTML/JS estático. Se agregó:

- `netlify.toml` + `netlify/functions/` — sin ninguna dependencia npm (ni `mercadopago` ni `@supabase/supabase-js`): `fetch`/`crypto` nativos de Node + llamadas REST directas a Supabase con `service_role`, para no romper la filosofía "sin build" del repo.
- `netlify/functions/mp-plan-order.js` — crea la Order en Mercado Pago. Protegida con Cloudflare Turnstile (captcha), rate limiting (tabla `plan_order_rate_limits`, respaldada por Supabase — Netlify no garantiza rate limiting nativo), validación de origen, y validación estricta de los 4 campos del formulario.
- `netlify/functions/mp-plan-order-status.js` — endpoint de solo lectura, **separado a propósito**: el polling del frontend mientras espera un `202` no puede volver a llamar a `mp-plan-order` (los tokens de Turnstile son de un solo uso, la segunda llamada fallaría siempre). Sin Turnstile porque no puede crear nada.
- `netlify/functions/mp-plan-webhook.js` — único lugar que puede marcar un pago como `pagado` (nunca el frontend). Valida la firma (`x-signature` HMAC, comparación de tiempo constante), vuelve a consultar `GET /v1/orders/{id}` como fuente de verdad (nunca confía en el cuerpo del webhook), verifica importe/moneda/cuenta-vendedora/entorno antes de tocar la base, y mapea los estados **reales** de Orders API (verificados contra la documentación, distintos a los de Payments/Preferences):

  | Order status / detail | Estado interno |
  |---|---|
  | `created` | `listo` |
  | `processing` / `in_process` | `pendiente` |
  | `processing` / `pending_review_manual` | `en_revision` |
  | `processed` / `accredited` | `pagado` |
  | `processed` / `partially_refunded` | `reembolso_parcial` |
  | `refunded` | `reembolsado` |
  | `failed` | `rechazado` |
  | `canceled` | `cancelado` |
  | `action_required` / `waiting_capture` | `autorizacion_pendiente` |

  Contracargos **no** salen de este mapeo — Mercado Pago los maneja como un recurso/evento aparte, no como un `status` de la Order. Documentado como límite conocido, no resuelto en esta fase.

- `supabase/migrations/0055_plan_deposit_payments.sql` — tabla `plan_deposit_payments` **sin `tenant_id`** (quien paga todavía no es un usuario de ningún tenant), RLS habilitada sin ninguna policy para `authenticated`/`anon` (solo las Netlify Functions con `service_role` la tocan). Idempotencia real vía RPC `claim_plan_deposit_attempt()`: nunca bloquea más allá de su propia transacción (a diferencia de un `FOR UPDATE` que espera), devuelve si la llamada es "dueña" del intento (`is_owner`) o no, recupera un intento `creando` trabado hace más de 30s, y reclama `error_reintentable` (red/timeout/5xx) de inmediato — nunca `error_final` (4xx, necesita revisión).

## Las 4 rondas de revisión técnica del usuario (antes de aprobar)

Cada corrección se verificó contra documentación oficial real antes de aceptarla, nunca a ciegas:
1. Variables de entorno incompletas, tabla necesitaba más columnas/estados, idempotencia insuficiente (un UUID nuevo por click podía duplicar), webhook necesitaba más verificaciones, nunca confiar en la página de retorno, proteger la función pública (rate limit/Turnstile), cuotas sin interés no son solo un número en el código, agregar pruebas de reembolso/contracargo.
2. **Corrección de fondo**: Orders API en vez de Preferences (ver arriba).
3. La concurrencia seguía mal resuelta (el `FOR UPDATE` no cubre la llamada real a Mercado Pago, que pasa después, fuera de esa transacción) — rediseñada con el patrón `is_owner`. `config.online`/`notification_url` reales de Orders API (no `back_urls` de Preferences). Estados reales de Orders API (no los de Payments).
4. El topic del webhook es `orders_v2` pero el **valor real del campo `type` en el JSON es `'order'`**, no `'orders_v2'` (verificado con un payload de ejemplo real). El polling reutilizaba un token de Turnstile ya gastado (de ahí `mp-plan-order-status.js`). `error_creacion` no se podía recuperar nunca (separado en `error_reintentable`/`error_final`). Una prueba de contracargo contradecía que estuviera "fuera de alcance" — se sacó de la verificación.

## Estado (2026-09-03)

**Implementado y commiteado** (commit `92b31b9`, ya subido a `webdelhotelcom/SoftwareEYO`). Configurado en vivo con el usuario, paso a paso, chat en mano: cuenta de Mercado Pago (credenciales de **prueba**, `MP_ENVIRONMENT=test`), Cloudflare Turnstile, `service_role` de Supabase, las 8 variables de entorno cargadas en Netlify, migración `0055` aplicada en producción.

**Pendiente**:
- El sitio de Netlify (`dashing-conkies-92cb00`) está pausado por límite de créditos del team — según la documentación oficial se reactiva solo al empezar el ciclo nuevo (ya empezó el 2026-09-03), sin ningún botón que apretar, pero tardó más de lo esperado. Ver [[Estado-actual]] para el estado más reciente.
- Este sitio se publica **manualmente** (`deploy/build.sh` + `netlify deploy`), no automático desde GitHub — subir el commit a GitHub no dispara un deploy nuevo acá.
- Falta la prueba de punta a punta con una tarjeta de prueba real, una vez que el sitio esté activo.
- Con credenciales de prueba (`TEST-`), nada de esto cobra plata real todavía — el pase a credenciales de producción es un paso aparte, explícito, recién después de verificar todo.
- Revisar en la cuenta de Mercado Pago qué cuotas están habilitadas como "sin interés" antes de publicar — no es algo configurable desde el código.

## Gotcha de esta sesión: 3 cuentas de GitHub distintas

El repo pertenece a `webdelhotelcom` — pero la Credential Manager de Windows del usuario tenía cacheada `alojamietoeyo-maker` (otros proyectos personales), y al generar un token nuevo "a las apuradas" salió una **tercera** cuenta, `orielesymama-cyber`, que tampoco tenía permiso. El usuario tiene 3 cuentas de GitHub reales. Lección: antes de generar un token para este repo, confirmar explícitamente en la esquina superior derecha de github.com que dice `webdelhotelcom` — no asumirlo.
