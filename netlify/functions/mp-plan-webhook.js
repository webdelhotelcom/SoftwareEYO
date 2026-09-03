// Webhook público de Mercado Pago (Orders API, topic orders_v2 --
// payload real: {type:'order', action:'order.processed', data:{id}}).
// Es la ÚNICA función que puede marcar un pago como 'pagado' -- nunca
// el frontend, nunca mp-plan-order.js. Verificado en 4 rondas de
// revisión antes de implementar, ver el plan.
'use strict';

const { supabaseSelectOne, supabaseUpdate } = require('./_lib/supabase');
const { jsonResponse } = require('./_lib/util');
const crypto = require('crypto');

// Mapeo real de estados de una Order (Orders API) -- NO son los
// estados de Payments/Preferences, son distintos, verificados contra la
// documentación oficial. Contracargos no salen de acá -- Mercado Pago
// los maneja como un evento/recurso aparte, deliberadamente fuera de
// esta fase.
function mapOrderStatus(status, statusDetail) {
  if (status === 'created') return 'listo';
  if (status === 'processing' && statusDetail === 'pending_review_manual') return 'en_revision';
  if (status === 'processing') return 'pendiente';
  if (status === 'processed' && statusDetail === 'partially_refunded') return 'reembolso_parcial';
  if (status === 'processed') return 'pagado';
  if (status === 'refunded') return 'reembolsado';
  if (status === 'failed') return 'rechazado';
  if (status === 'canceled') return 'cancelado';
  if (status === 'action_required' && statusDetail === 'waiting_capture') return 'autorizacion_pendiente';
  return null; // estado desconocido -- no se actualiza nada, se deja para revisión manual
}

function verifySignature(event) {
  const xSignature = event.headers['x-signature'];
  const xRequestId = event.headers['x-request-id'];
  const dataId = (event.queryStringParameters || {})['data.id'];
  if (!xSignature || !xRequestId || !dataId) return false;

  const parts = Object.fromEntries(
    xSignature.split(',').map((p) => {
      const [k, v] = p.split('=');
      return [k.trim(), (v || '').trim()];
    })
  );
  const ts = parts.ts;
  const v1 = parts.v1;
  if (!ts || !v1) return false;

  const manifest = `id:${dataId};request-id:${xRequestId};ts:${ts};`;
  const expected = crypto
    .createHmac('sha256', process.env.MP_WEBHOOK_SECRET)
    .update(manifest)
    .digest('hex');

  const expectedBuf = Buffer.from(expected, 'utf8');
  const gotBuf = Buffer.from(v1, 'utf8');
  if (expectedBuf.length !== gotBuf.length) return false;
  return crypto.timingSafeEqual(expectedBuf, gotBuf);
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return jsonResponse(405, { error: 'method_not_allowed' });
  }

  // 1) Verifica el tipo de evento -- el payload real trae type:'order'
  // (orders_v2 es el nombre del topic en la config de MP, no el valor
  // del campo type del JSON).
  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch {
    return jsonResponse(400, { error: 'invalid_json' });
  }
  if (payload.type !== 'order') {
    return jsonResponse(200, { ignored: true }); // 200 para que MP no reintente algo que no nos interesa
  }

  // 2) Valida la firma -- comparación de tiempo constante, nunca ===.
  if (!verifySignature(event)) {
    return jsonResponse(401, { error: 'invalid_signature' });
  }

  const orderId = payload.data && payload.data.id;
  if (!orderId) {
    return jsonResponse(400, { error: 'missing_order_id' });
  }

  // 3) Fuente de verdad: vuelve a consultar la orden completa contra la
  // API de MP -- nunca confía en el cuerpo del webhook a ciegas.
  const mpRes = await fetch(`https://api.mercadopago.com/v1/orders/${orderId}`, {
    headers: { Authorization: `Bearer ${process.env.MP_ACCESS_TOKEN}` },
  });
  if (!mpRes.ok) {
    return jsonResponse(502, { error: 'mp_query_failed' });
  }
  const order = await mpRes.json();

  // 4) Verificaciones adicionales, todas obligatorias antes de tocar la base.
  const externalReference = order.external_reference;
  if (!externalReference) {
    return jsonResponse(200, { ignored: true });
  }

  const row = await supabaseSelectOne('plan_deposit_payments', { id: externalReference });
  if (!row) {
    return jsonResponse(200, { ignored: true }); // no es nuestro
  }

  const orderAmount = Number(order.total_amount);
  if (orderAmount !== Number(row.amount_uyu)) {
    await supabaseUpdate(
      'plan_deposit_payments',
      { id: row.id },
      {
        failure_reason: `Desajuste de importe: MP=${orderAmount}, esperado=${row.amount_uyu}`,
        raw_status: order.status,
        status_detail: order.status_detail || null,
        updated_at: new Date().toISOString(),
      }
    );
    return jsonResponse(200, { flagged: true });
  }

  // Vendedor/aplicación esperado -- viene tanto en el payload del
  // webhook (application_id/user_id) como, en teoría, resoluble contra
  // la propia orden -- se compara contra el payload, que ya trae estos
  // campos directamente.
  const expectedSeller = process.env.MP_SELLER_USER_ID;
  if (expectedSeller && String(payload.user_id) !== String(expectedSeller)) {
    return jsonResponse(200, { ignored: true }); // orden de otra cuenta -- no es nuestra
  }

  const expectedEnvironment = process.env.MP_ENVIRONMENT; // 'test' | 'production'
  const isLive = payload.live_mode === true;
  if (expectedEnvironment === 'production' && !isLive) {
    return jsonResponse(200, { ignored: true });
  }
  if (expectedEnvironment === 'test' && isLive) {
    return jsonResponse(200, { ignored: true });
  }

  const newStatus = mapOrderStatus(order.status, order.status_detail);
  if (!newStatus) {
    await supabaseUpdate(
      'plan_deposit_payments',
      { id: row.id },
      {
        raw_status: order.status,
        status_detail: order.status_detail || null,
        updated_at: new Date().toISOString(),
      }
    );
    return jsonResponse(200, { unmapped_status: order.status });
  }

  // No se procesó antes -- mismo estado ya guardado, no repetir nada.
  if (row.status === newStatus) {
    return jsonResponse(200, { already_processed: true });
  }

  const patch = {
    status: newStatus,
    raw_status: order.status,
    status_detail: order.status_detail || null,
    mercado_pago_order_id: order.id,
    updated_at: new Date().toISOString(),
  };
  if (newStatus === 'rechazado') {
    patch.failure_reason = order.status_detail || 'Rechazado por Mercado Pago';
  }
  if (newStatus === 'pagado') {
    patch.paid_at = new Date().toISOString();
  }

  await supabaseUpdate('plan_deposit_payments', { id: row.id }, patch);

  return jsonResponse(200, { ok: true, status: newStatus });
};
