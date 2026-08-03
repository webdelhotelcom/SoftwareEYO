-- ════════════════════════════════════════════════════════════════
-- 0028 — Corrección: get_market_scan_status() no exigía
-- has_pricing_intelligence(), solo el permiso ver_analisis_precios.
--
-- Como el permiso se otorga por rol independientemente del plan (un
-- admin de un tenant Plan Profesional ya tiene ver_analisis_precios=
-- true desde el backfill de la migración 0025), un tenant Profesional
-- podía llamar esta función manipulando el navegador/consola y ver su
-- cupo aunque el plan todavía no tenga el módulo habilitado. Hoy no
-- es explotable desde la interfaz normal (el ítem de navegación de
-- Precios solo existe para Plan Hotel), pero el propio criterio de
-- este proyecto es no depender de que la interfaz oculte algo — cada
-- función debe validar plan Y permiso, igual que register_market_scan
-- ya hacía. Detectado por revisión, no por explotación real.
-- ════════════════════════════════════════════════════════════════

create or replace function public.get_market_scan_status(p_tenant_id uuid)
returns table(
  plan_code text,
  monthly_limit int,
  automatic_scans_used int,
  manual_scans_used int,
  total_scans_used int,
  last_scan_at timestamptz,
  next_scan_at date,
  calendar_mondays int[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.tenant_market_scan_usage;
  v_calendar int[];
  v_remaining int;
begin
  if p_tenant_id <> public.current_tenant_id() then
    raise exception 'No autorizado';
  end if;
  if not public.has_pricing_intelligence() then
    raise exception 'Este plan no tiene habilitada Inteligencia de Precios';
  end if;
  if not public.has_permission('ver_analisis_precios') then
    raise exception 'No tenés permiso para ver esta información';
  end if;

  v_row := public.sync_market_scan_usage(p_tenant_id);
  v_calendar := case v_row.plan_code
    when 'profesional' then array[1,3]
    when 'hotel' then array[1,2,3,4]
    else array[]::int[]
  end;
  v_remaining := greatest(v_row.monthly_limit - v_row.automatic_scans_used, 0);

  return query select
    v_row.plan_code,
    v_row.monthly_limit,
    v_row.automatic_scans_used,
    v_row.manual_scans_used,
    v_row.automatic_scans_used + v_row.manual_scans_used,
    v_row.last_scan_at,
    public.next_allowed_monday(v_row.plan_code, current_date, v_remaining),
    v_calendar;
end;
$$;

comment on function public.get_market_scan_status(uuid) is 'Estado de cupo del mes en curso para el panel: plan, límite, usadas, restantes, última/próxima fecha habilitada. Exige has_pricing_intelligence() además del permiso — corregido en 0028.';
