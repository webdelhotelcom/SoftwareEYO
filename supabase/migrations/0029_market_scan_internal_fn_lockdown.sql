-- ════════════════════════════════════════════════════════════════
-- 0029 — Corrección CRÍTICA: sync_market_scan_usage(uuid) era
-- ejecutable directamente por cualquier usuario autenticado, sin
-- validar tenant/plan/permiso, porque es SECURITY DEFINER y Postgres
-- otorga EXECUTE a PUBLIC por defecto al crear una función.
--
-- Probado en vivo: un usuario de un tenant Plan Profesional (sin
-- relación alguna con otro tenant de prueba en Plan Hotel) llamó
-- supabaseClient.rpc('sync_market_scan_usage', {p_tenant_id: <tenant
-- ajeno>}) y obtuvo el cupo completo de ese tenant ajeno (plan,
-- límite, investigaciones usadas, última fecha) — la función solo
-- estaba pensada para ser invocada INTERNAMENTE por
-- get_market_scan_status()/register_market_scan(), que sí validan
-- tenant/plan/permiso, pero nada impedía llamarla directo por RPC.
--
-- Corrección: revocar EXECUTE de PUBLIC/authenticated/anon. Las dos
-- funciones que sí deben quedar accesibles la siguen llamando sin
-- problema — una función SECURITY DEFINER que invoca a otra
-- internamente no vuelve a chequear el permiso EXECUTE del rol
-- original, eso solo se evalúa en la llamada RPC de primer nivel.
-- ════════════════════════════════════════════════════════════════

revoke execute on function public.sync_market_scan_usage(uuid) from public;
revoke execute on function public.sync_market_scan_usage(uuid) from authenticated;
revoke execute on function public.sync_market_scan_usage(uuid) from anon;

comment on function public.sync_market_scan_usage(uuid) is 'Helper INTERNO — no invocar directo por RPC. Sin EXECUTE público desde la migración 0029 (probado en vivo: filtraba cupo de otros tenants). Solo lo llaman get_market_scan_status() y register_market_scan(), que sí validan tenant/plan/permiso antes.';
