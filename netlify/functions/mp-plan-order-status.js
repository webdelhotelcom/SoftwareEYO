// Endpoint de solo lectura para el polling del frontend mientras espera
// un 202 de mp-plan-order.js. Nunca crea nada, nunca llama a Mercado
// Pago -- por eso no exige Turnstile (no puede generar ningún efecto).
// Tiene su propio rate limit, más permisivo que el de creación, porque
// se llama varias veces seguidas por diseño.
'use strict';

const { supabaseRpc, supabaseSelectOne } = require('./_lib/supabase');
const { jsonResponse, getClientIp, isAllowedOrigin, isValidUuid, checkRateLimit } = require('./_lib/util');

const MAX_REQUESTS_PER_MINUTE = 30;

exports.handler = async (event) => {
  if (event.httpMethod !== 'GET') {
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

  const idempotencyKey = (event.queryStringParameters || {}).idempotency_key;
  if (!isValidUuid(idempotencyKey)) {
    return jsonResponse(400, { error: 'invalid_idempotency_key' });
  }

  const row = await supabaseSelectOne(
    'plan_deposit_payments',
    { idempotency_key: idempotencyKey },
    'status,checkout_url,failure_reason'
  );

  if (!row) {
    return jsonResponse(404, { error: 'not_found' });
  }

  if (row.status === 'creando') {
    return jsonResponse(202, { status: 'procesando' });
  }
  if (row.status === 'listo') {
    return jsonResponse(200, { status: 'listo', checkout_url: row.checkout_url });
  }
  return jsonResponse(200, { status: row.status, failure_reason: row.failure_reason || null });
};
