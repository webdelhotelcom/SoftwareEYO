// Crea (o reutiliza, según idempotency_key) una Order de Mercado Pago
// (Checkout Pro vía Orders API) para la seña del 50% de Plan Inicial o
// Plan Profesional de Bestoic -- ver plan en
// C:\Users\Orieles\.claude\plans\splendid-weaving-origami.md, sección
// "BESTOIC — Botón de pago de la seña del plan".
//
// Nunca marca nada como 'pagado' -- eso lo hace exclusivamente
// mp-plan-webhook.js, después de confirmar el estado real contra la
// API de Mercado Pago. Esta función solo crea la orden y devuelve la
// URL de checkout.
'use strict';

const { supabaseRpc, supabaseUpdate } = require('./_lib/supabase');

const PLAN_LABELS = { emprendedor: 'Emprendedor', profesional: 'Profesional' };
const {
  jsonResponse,
  getClientIp,
  isAllowedOrigin,
  isValidEmail,
  isValidUuid,
  checkRateLimit,
  verifyTurnstile,
} = require('./_lib/util');

// Precio de Plan Emprendedor: USD 150, punto -- sin ninguna lógica de
// "precio regular" ni suba futura (corregido 2026-09-04: si algún día
// se sube, es una decisión aparte tomada con datos de ventas, nunca algo
// que el código ya lleve implícito).
const PLAN_PRICES_USD = { emprendedor: 150, profesional: 500 };
const DEPOSIT_PERCENTAGE = 50;

// Cupo de módulos del catálogo incluidos en el precio del plan (sin
// costo adicional mientras no se supere) -- mismo valor que
// PLANS[plan].includedModules en software.html, sincronizar a mano si
// cambia. Hotel no tiene cupo fijo (va por WhatsApp/cotización, nunca
// llega a esta función -- no está en PLAN_PRICES_USD).
const PLAN_MODULE_QUOTA = { emprendedor: 3, profesional: 6 };

// Módulos que cada plan incluye automáticamente y que NUNCA pueden venir
// en selected_modules (no son una "elección" que consuma cupo).
const PLAN_AUTO_INCLUDED = { emprendedor: [], profesional: ['personalizacion'] };

// Catálogo real de módulos -- mismas 17 keys que MODULES en
// software.html (Propietarios, Comisiones, Reportes avanzados,
// Temporadas y precios, Roles y permisos, Operadores con PIN,
// Housekeeping, Mantenimiento, Recepción, Habitaciones individuales,
// Cuenta del huésped, Caja y turnos, Reportes hoteleros, Auditoría,
// Pre-facturación, Mercado Bestoic, Personalización). Sincronizar a mano
// si el catálogo del frontend cambia.
const VALID_MODULE_KEYS = [
  'propietarios', 'comisiones', 'reportes_avanzados', 'temporadas_precios',
  'roles_permisos', 'operadores_pin', 'housekeeping', 'mantenimiento',
  'recepcion', 'habitaciones_individuales', 'cuenta_huesped', 'caja_turnos',
  'reportes_hoteleros', 'auditoria', 'prefacturacion', 'mercado_bestoic',
  'personalizacion',
];

// Decisión comercial todavía pendiente del usuario -- mientras sigan en
// null, esta función RECHAZA cualquier config con excedente de módulos o
// con extraProperties/extraUsers > 0 (nunca cobra un precio inventado).
// El día que se definan, alcanza con completar estos 3 valores acá -- no
// hace falta ningún cambio de arquitectura nuevo en ese momento.
const EXTRA_MODULE_PRICE_USD = null;
const EXTRA_PROPERTY_PRICE_USD = null;
const EXTRA_USER_PRICE_USD = null;

// Sincronizar a mano con software.html (const exchangeRate) si cambia --
// no se puede compartir una variable de JS de navegador con esta función
// de Node en tiempo de ejecución.
const EXCHANGE_RATE = 41;

const MAX_REQUESTS_PER_MINUTE = 5;
const MAX_BODY_BYTES = 5000;

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return jsonResponse(405, { error: 'method_not_allowed' });
  }

  if (!isAllowedOrigin(event)) {
    return jsonResponse(403, { error: 'origin_not_allowed' });
  }

  const ip = getClientIp(event);
  const withinLimit = await checkRateLimit(supabaseRpc, ip, MAX_REQUESTS_PER_MINUTE);
  if (!withinLimit) {
    return jsonResponse(429, { error: 'too_many_requests' });
  }

  const rawBody = event.body || '';
  if (Buffer.byteLength(rawBody, 'utf8') > MAX_BODY_BYTES) {
    return jsonResponse(413, { error: 'payload_too_large' });
  }

  let body;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return jsonResponse(400, { error: 'invalid_json' });
  }

  const { plan, nombre, email, telefono, idempotency_key, turnstile_token } = body;

  if (!Object.prototype.hasOwnProperty.call(PLAN_PRICES_USD, plan)) {
    return jsonResponse(400, { error: 'invalid_plan' });
  }
  if (!isValidEmail(email)) {
    return jsonResponse(400, { error: 'invalid_email' });
  }
  if (typeof nombre !== 'string' || nombre.length > 200) {
    return jsonResponse(400, { error: 'invalid_nombre' });
  }
  if (telefono != null && (typeof telefono !== 'string' || telefono.length > 30)) {
    return jsonResponse(400, { error: 'invalid_telefono' });
  }
  if (!isValidUuid(idempotency_key)) {
    return jsonResponse(400, { error: 'invalid_idempotency_key' });
  }

  // ── Validación de la config del configurador ("Arma tu Bestoic") ──
  // El navegador nunca decide el precio ni qué es válido -- todo se
  // reconstruye y valida acá contra el propio catálogo del servidor.
  // localStorage/DevTools del cliente son solo UX, nunca fuente de
  // verdad. Cada paso rechaza con 400 explícito, nunca normaliza en
  // silencio una config inválida.
  const selectedModules = Array.isArray(body.selected_modules) ? body.selected_modules : [];
  const extraProperties = Number.isFinite(body.extra_properties) ? body.extra_properties : 0;
  const extraUsers = Number.isFinite(body.extra_users) ? body.extra_users : 0;

  // 1) Cada key tiene que existir realmente en el catálogo.
  if (!selectedModules.every((key) => VALID_MODULE_KEYS.includes(key))) {
    return jsonResponse(400, { error: 'invalid_module_key' });
  }
  // 2) Sin duplicados -- un módulo repetido no puede contar doble contra
  // el cupo ni el excedente.
  if (new Set(selectedModules).size !== selectedModules.length) {
    return jsonResponse(400, { error: 'duplicate_module_key' });
  }
  // 3) Ningún módulo auto-incluido del plan puede venir como si fuera una
  // elección más -- eso inflaría artificialmente cuánto cupo "usó".
  const autoIncluded = PLAN_AUTO_INCLUDED[plan] || [];
  if (selectedModules.some((key) => autoIncluded.includes(key))) {
    return jsonResponse(400, { error: 'auto_included_module_not_selectable' });
  }
  // 4) extraProperties/extraUsers tienen que ser enteros >= 0.
  if (!Number.isInteger(extraProperties) || extraProperties < 0 || !Number.isInteger(extraUsers) || extraUsers < 0) {
    return jsonResponse(400, { error: 'invalid_extras' });
  }
  // 5) Mientras los precios de excedente sigan sin definir, esta función
  // rechaza cualquier config que los necesite -- nunca cobra un monto
  // parcial o inventado. Esas configs van por WhatsApp (frontend).
  const moduleQuota = PLAN_MODULE_QUOTA[plan];
  const excessModules = Math.max(0, selectedModules.length - moduleQuota);
  const needsExtraPricing = excessModules > 0 || extraProperties > 0 || extraUsers > 0;
  if (needsExtraPricing && (EXTRA_MODULE_PRICE_USD == null || EXTRA_PROPERTY_PRICE_USD == null || EXTRA_USER_PRICE_USD == null)) {
    return jsonResponse(400, { error: 'extras_not_priced_yet' });
  }

  const turnstileOk = await verifyTurnstile(turnstile_token, ip);
  if (!turnstileOk) {
    return jsonResponse(403, { error: 'captcha_failed' });
  }

  // Total real -- precio fijo del plan + excedente (0 hoy siempre, ya
  // que needsExtraPricing con precios sin definir se rechazó arriba;
  // queda calculado igual para cuando el usuario complete las 3
  // constantes de excedente).
  const excessModulesCostUsd = EXTRA_MODULE_PRICE_USD != null ? excessModules * EXTRA_MODULE_PRICE_USD : 0;
  const extraPropertiesCostUsd = EXTRA_PROPERTY_PRICE_USD != null ? extraProperties * EXTRA_PROPERTY_PRICE_USD : 0;
  const extraUsersCostUsd = EXTRA_USER_PRICE_USD != null ? extraUsers * EXTRA_USER_PRICE_USD : 0;
  const planPriceUsd = PLAN_PRICES_USD[plan] + excessModulesCostUsd + extraPropertiesCostUsd + extraUsersCostUsd;
  const amountUyu = Math.round(((planPriceUsd * DEPOSIT_PERCENTAGE) / 100) * EXCHANGE_RATE);

  const claim = await supabaseRpc('claim_plan_deposit_attempt', {
    p_idempotency_key: idempotency_key,
    p_plan: plan,
    p_plan_price_usd: planPriceUsd,
    p_exchange_rate: EXCHANGE_RATE,
    p_deposit_percentage: DEPOSIT_PERCENTAGE,
    p_amount_uyu: amountUyu,
    p_nombre: nombre,
    p_email: email,
    p_telefono: telefono || null,
  });

  const row = claim.row;
  const isOwner = claim.is_owner;

  if (!isOwner) {
    if (row.status === 'creando') {
      return jsonResponse(202, { status: 'procesando' });
    }
    if (row.status === 'listo') {
      return jsonResponse(200, { checkout_url: row.checkout_url });
    }
    return jsonResponse(200, { status: row.status, failure_reason: row.failure_reason || null });
  }

  // is_owner === true: esta llamada es la dueña del intento -- crea la
  // Order en Mercado Pago (o reintenta, si estaba en error_reintentable
  // o si recuperó un 'creando' trabado).
  const nowIso = new Date().toISOString();
  try {
    const mpRes = await fetch('https://api.mercadopago.com/v1/orders', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.MP_ACCESS_TOKEN}`,
        'X-Idempotency-Key': idempotency_key,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        type: 'online',
        processing_mode: 'manual',
        total_amount: String(amountUyu),
        external_reference: row.id,
        payer: { email },
        items: [
          {
            title: `Seña Plan ${PLAN_LABELS[plan]} — Bestoic`,
            quantity: 1,
            unit_price: String(amountUyu),
          },
        ],
        config: {
          notification_url: `${process.env.PUBLIC_SITE_URL}/.netlify/functions/mp-plan-webhook`,
          online: {
            success_url: `${process.env.PUBLIC_SITE_URL}/pago-gracias.html?result=success`,
            failure_url: `${process.env.PUBLIC_SITE_URL}/pago-gracias.html?result=failure`,
            pending_url: `${process.env.PUBLIC_SITE_URL}/pago-gracias.html?result=pending`,
            auto_return: 'approved',
          },
        },
      }),
    });

    if (!mpRes.ok) {
      const errText = await mpRes.text();
      const retryable = mpRes.status >= 500;
      await supabaseUpdate(
        'plan_deposit_payments',
        { id: row.id },
        {
          status: retryable ? 'error_reintentable' : 'error_final',
          failure_reason: errText.slice(0, 500),
          raw_status: String(mpRes.status),
          updated_at: nowIso,
        }
      );
      return jsonResponse(retryable ? 502 : 400, {
        error: retryable ? 'mp_temporarily_unavailable' : 'mp_rejected_order',
      });
    }

    const mpData = await mpRes.json();
    await supabaseUpdate(
      'plan_deposit_payments',
      { id: row.id },
      {
        status: 'listo',
        mercado_pago_order_id: mpData.id,
        checkout_url: mpData.checkout_url,
        // Informativo únicamente -- para que el founder sepa qué
        // configurar al crear la cuenta a mano. Nunca afecta el precio.
        selected_modules: selectedModules,
        updated_at: nowIso,
      }
    );
    return jsonResponse(200, { checkout_url: mpData.checkout_url });
  } catch (err) {
    await supabaseUpdate(
      'plan_deposit_payments',
      { id: row.id },
      {
        status: 'error_reintentable',
        failure_reason: String(err).slice(0, 500),
        updated_at: nowIso,
      }
    );
    return jsonResponse(502, { error: 'mp_request_failed' });
  }
};
