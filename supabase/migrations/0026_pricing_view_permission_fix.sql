-- ════════════════════════════════════════════════════════════════
-- 0026 — Corrección detectada en la prueba en vivo de Inteligencia
-- de Precios: las políticas de SELECT de las 6 tablas del módulo
-- solo exigían has_pricing_intelligence() (el plan), pero nunca
-- has_permission('ver_analisis_precios') — el permiso quedaba en
-- el catálogo sin controlar nada de verdad. Se probó en vivo con un
-- usuario de rol limpieza (sin ese permiso, dentro de un tenant Plan
-- Hotel): podía leer los grupos de competidores igual.
-- ════════════════════════════════════════════════════════════════

drop policy if exists "competitor_sets_select_own_tenant" on public.competitor_sets;
create policy "competitor_sets_select_own_tenant" on public.competitor_sets
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('ver_analisis_precios'));

drop policy if exists "competitor_properties_select_own_tenant" on public.competitor_properties;
create policy "competitor_properties_select_own_tenant" on public.competitor_properties
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('ver_analisis_precios'));

drop policy if exists "pricing_property_config_select_own_tenant" on public.pricing_property_config;
create policy "pricing_property_config_select_own_tenant" on public.pricing_property_config
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('ver_analisis_precios'));

drop policy if exists "market_searches_select_own_tenant" on public.market_searches;
create policy "market_searches_select_own_tenant" on public.market_searches
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('ver_analisis_precios'));

drop policy if exists "market_snapshots_select_own_tenant" on public.market_snapshots;
create policy "market_snapshots_select_own_tenant" on public.market_snapshots
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('ver_analisis_precios'));

drop policy if exists "price_recommendations_select_own_tenant" on public.price_recommendations;
create policy "price_recommendations_select_own_tenant" on public.price_recommendations
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('ver_analisis_precios'));

-- market_data_sources se deja como está (auth.role()='authenticated'):
-- es el mismo catálogo compartido para todos, sin datos de ningún
-- tenant — no tiene sentido restringirlo por permiso.
