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
const {
  jsonResponse,
  getClientIp,
  isAllowedOrigin,
  isValidEmail,
  isValidUuid,
  checkRateLimit,
  verifyTurnstile,
} = require('./_lib/util');

// Precio de lanzamiento del Plan Inicial (primeros 3 clientes) -- se
// usa siempre en esta fase, no hay contador automático de clientes.
// Cuando se cumplan los 3, cambiar este número a mano (150 -> 175) y
// avisar que se actualizó.
const PLAN_PRICES_USD = { inicial: 150, profesional: 500 };
const DEPOSIT_PERCENTAGE = 50;

// Sincronizar a mano con software.html:1525 (const exchangeRate) si
// cambia -- no se puede compartir una variable de JS de navegador con
// esta función de Node en tiempo de ejecución.
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

  const turnstileOk = await verifyTurnstile(turnstile_token, ip);
  if (!turnstileOk) {
    return jsonResponse(403, { error: 'captcha_failed' });
  }

  const planPriceUsd = PLAN_PRICES_USD[plan];
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
            title: `Seña Plan ${plan === 'inicial' ? 'Inicial' : 'Profesional'} — Bestoic`,
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
