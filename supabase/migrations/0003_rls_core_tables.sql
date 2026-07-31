-- ════════════════════════════════════════════════════════════════
-- 0003 — RLS de las tablas base: tenants, plan_config, client_limits, profiles
-- Esto es lo que garantiza, a nivel de base de datos (no solo en JavaScript),
-- que un cliente no pueda ver ni tocar datos de otro cliente.
-- ════════════════════════════════════════════════════════════════

alter table public.tenants enable row level security;
alter table public.plan_config enable row level security;
alter table public.client_limits enable row level security;
alter table public.profiles enable row level security;

-- TENANTS: cada usuario ve únicamente su propio tenant.
-- Sin política de insert/update/delete: el alta de un cliente nuevo la hace
-- el administrador de EYO directamente por SQL (todavía no existe un módulo
-- de alta de clientes en el panel — es trabajo de fases siguientes).
create policy "tenants_select_own" on public.tenants
  for select using (id = public.current_tenant_id());

-- PLAN_CONFIG: catálogo de referencia, mismo contenido para todos los
-- usuarios logueados. No hay datos sensibles ni de un cliente en particular.
create policy "plan_config_select_all" on public.plan_config
  for select using (auth.role() = 'authenticated');

-- CLIENT_LIMITS: cada tenant ve solo su propio override de límites.
create policy "client_limits_select_own" on public.client_limits
  for select using (tenant_id = public.current_tenant_id());

-- PROFILES: cada usuario ve los perfiles de su mismo tenant (necesario para
-- el futuro módulo de Usuarios y Permisos) y solo puede editar su propia fila.
create policy "profiles_select_same_tenant" on public.profiles
  for select using (tenant_id = public.current_tenant_id());

create policy "profiles_update_self" on public.profiles
  for update using (id = auth.uid())
  with check (id = auth.uid() and tenant_id = public.current_tenant_id());

-- Nota: no hay política de insert en profiles todavía. La creación de
-- usuarios nuevos (con su tenant y rol asignado) la hace el administrador
-- de EYO por SQL en esta fase; el módulo "Usuarios y permisos" que lo haga
-- desde el panel es una fase posterior.
