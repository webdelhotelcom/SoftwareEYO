'use strict';

function jsonResponse(statusCode, bodyObj) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(bodyObj),
  };
}

function getClientIp(event) {
  return (
    event.headers['x-nf-client-connection-ip'] ||
    (event.headers['x-forwarded-for'] || '').split(',')[0].trim() ||
    'unknown'
  );
}

// PUBLIC_SITE_URL es la única fuente de verdad para qué origen se
// acepta -- nunca se refleja/confía en lo que mande el propio request.
function isAllowedOrigin(event) {
  const publicSiteUrl = process.env.PUBLIC_SITE_URL;
  if (!publicSiteUrl) return false;
  let allowedHost;
  try {
    allowedHost = new URL(publicSiteUrl).host;
  } catch {
    return false;
  }
  const originHeader = event.headers['origin'] || event.headers['referer'];
  if (!originHeader) return false;
  try {
    return new URL(originHeader).host === allowedHost;
  } catch {
    return false;
  }
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
function isValidEmail(email) {
  return typeof email === 'string' && email.length <= 200 && EMAIL_RE.test(email);
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function isValidUuid(value) {
  return typeof value === 'string' && UUID_RE.test(value);
}

// Ventanas de 1 minuto, truncadas -- ver bump_plan_order_rate_limit() en
// la migración 0055. maxPerWindow distinto según el endpoint (más
// permisivo para el de solo-status, que se llama repetidas veces por
// diseño durante el polling).
async function checkRateLimit(supabaseRpc, ip, maxPerWindow) {
  const windowStart = new Date(Math.floor(Date.now() / 60000) * 60000).toISOString();
  const count = await supabaseRpc('bump_plan_order_rate_limit', {
    p_ip: ip,
    p_window_start: windowStart,
  });
  return count <= maxPerWindow;
}

async function verifyTurnstile(token, ip) {
  if (!token) return false;
  const secret = process.env.TURNSTILE_SECRET_KEY;
  const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ secret, response: token, remoteip: ip }),
  });
  if (!res.ok) return false;
  const data = await res.json();
  return data.success === true;
}

module.exports = {
  jsonResponse,
  getClientIp,
  isAllowedOrigin,
  isValidEmail,
  isValidUuid,
  checkRateLimit,
  verifyTurnstile,
};
