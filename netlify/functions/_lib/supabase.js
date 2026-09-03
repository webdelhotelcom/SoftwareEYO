// Helper mínimo para hablar con la REST API de Supabase usando
// service_role -- sin agregar @supabase/supabase-js como dependencia
// npm (este repo no tiene build step ni package.json, y no hace falta
// uno solo para esto: fetch/crypto ya son globales en el runtime de
// Netlify Functions).
'use strict';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

function headers(extra) {
  return {
    'Content-Type': 'application/json',
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    ...extra,
  };
}

async function supabaseRpc(fnName, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fnName}`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify(args),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supabase RPC ${fnName} failed: ${res.status} ${text}`);
  }
  return res.json();
}

async function supabaseSelectOne(table, match, columns) {
  const params = new URLSearchParams();
  if (columns) params.set('select', columns);
  for (const [k, v] of Object.entries(match)) params.append(k, `eq.${v}`);
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${params.toString()}&limit=1`, {
    headers: headers(),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supabase select ${table} failed: ${res.status} ${text}`);
  }
  const rows = await res.json();
  return rows[0] || null;
}

async function supabaseUpdate(table, match, patch) {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(match)) params.append(k, `eq.${v}`);
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${params.toString()}`, {
    method: 'PATCH',
    headers: headers({ Prefer: 'return=representation' }),
    body: JSON.stringify(patch),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supabase update ${table} failed: ${res.status} ${text}`);
  }
  const rows = await res.json();
  return rows[0] || null;
}

module.exports = { supabaseRpc, supabaseSelectOne, supabaseUpdate };
