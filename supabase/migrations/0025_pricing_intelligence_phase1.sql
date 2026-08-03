-- ════════════════════════════════════════════════════════════════
-- 0025 — Inteligencia de Precios, FASE 1 (beta, solo Plan Hotel).
--
-- Esquema mínimo para la primera versión real y probable: cargar
-- competidores a mano o por CSV, configurar el alojamiento propio,
-- y generar una recomendación con estadística explicable (mediana
-- ponderada por similitud, percentiles, confianza). Deliberadamente
-- NO incluye todavía: calendario de precios, simulador, alertas
-- automáticas, ni historial/aprendizaje — quedan para una fase
-- siguiente, sobre esta misma base. Ver docs/obsidian/
-- Inteligencia-de-Precios.md para el detalle completo de qué se
-- construyó y qué se dejó pendiente a propósito.
-- ════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1) FEATURE FLAG POR PLAN — igual criterio que el resto del
-- proyecto: se valida en la base de datos (RLS), no solo en el
-- navegador. Nunca "todo o nada" hardcodeado por email ni por
-- variable de front — el plan real del tenant es la única fuente.
-- ────────────────────────────────────────────────────────────────
alter table public.plan_config add column if not exists pricing_intelligence_enabled boolean not null default false;
update public.plan_config set pricing_intelligence_enabled = true where plan = 'hotel';

comment on column public.plan_config.pricing_intelligence_enabled is 'Feature flag de Inteligencia de Precios (beta) por plan. Hotel=true, Profesional/Inicial=false por ahora — preparado para habilitar Profesional en el futuro cambiando este valor, sin tocar código.';

create or replace function public.has_pricing_intelligence()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select pc.pricing_intelligence_enabled
     from public.profiles pr
     join public.tenants t on t.id = pr.tenant_id
     join public.plan_config pc on pc.plan = t.plan
     where pr.id = auth.uid() and pr.active = true),
    false
  )
$$;

comment on function public.has_pricing_intelligence is 'Si el plan del tenant del usuario logueado tiene habilitada la Inteligencia de Precios. Se usa en TODAS las políticas RLS de este módulo — nunca alcanza con ocultar el menú en el navegador.';

-- ────────────────────────────────────────────────────────────────
-- 2) PERMISOS — separados de la habilitación por plan. Que un
-- tenant tenga el módulo habilitado no significa que cualquier
-- empleado pueda tocar el precio mínimo o conectar una fuente.
-- ────────────────────────────────────────────────────────────────
insert into public.permissions_catalog (key,label,sort_order) values
  ('ver_analisis_precios','Ver análisis de precios',80),
  ('crear_analisis_precios','Crear análisis de precios',81),
  ('importar_datos_precios','Importar datos de competidores',82),
  ('modificar_competidores_precios','Modificar competidores',83),
  ('configurar_precio_minimo','Configurar precio mínimo rentable',84),
  ('aceptar_recomendaciones_precios','Aceptar recomendaciones de precio',85),
  ('administrar_fuentes_precios','Administrar fuentes de datos externas',86),
  ('ver_historial_precios','Ver historial de precios',87),
  ('exportar_precios','Exportar información de precios',88)
on conflict (key) do nothing;

-- Backfill para tenants que ya existían antes de esta migración.
-- admin y gerencia ya quedan cubiertos por la lógica genérica de
-- seed_default_role_permissions() (admin=todo, gerencia=todo menos
-- administrar_usuarios) para tenants NUEVOS; acá lo replicamos a
-- mano para los que ya existían, sin pisar nada que un admin haya
-- configurado distinto.
insert into public.role_permissions (tenant_id, role, permission_key, allowed)
select t.id, r.role, p.key,
  case
    when r.role = 'admin' then true
    when r.role = 'gerencia' then true
    else false
  end
from public.tenants t
cross join (values ('admin'),('gerencia'),('encargado'),('recepcion'),('limpieza'),('mantenimiento'),('contador'),('propietario')) as r(role)
cross join (values
  ('ver_analisis_precios'),('crear_analisis_precios'),('importar_datos_precios'),
  ('modificar_competidores_precios'),('configurar_precio_minimo'),('aceptar_recomendaciones_precios'),
  ('administrar_fuentes_precios'),('ver_historial_precios'),('exportar_precios')
) as p(key)
on conflict (tenant_id, role, permission_key) do nothing;

-- ────────────────────────────────────────────────────────────────
-- 3) CATÁLOGO DE FUENTES DE DATOS — no es una tabla por tenant: es
-- el mismo catálogo para todos, con qué fuentes están realmente
-- conectadas hoy (available=true) y cuáles quedan preparadas pero
-- todavía no ("Esta fuente todavía no está conectada..."). Nunca
-- se activa una fuente en este catálogo sin que exista de verdad.
-- ────────────────────────────────────────────────────────────────
create table public.market_data_sources (
  key text primary key,
  label text not null,
  available boolean not null default false,
  description text
);

comment on table public.market_data_sources is 'Catálogo de proveedores de datos de mercado. available=false para Booking/Airbnb hasta que EYO tenga credenciales y autorización oficial reales — nunca se marca true sin eso.';

insert into public.market_data_sources (key, label, available, description) values
  ('manual', 'Carga manual', true, 'Ingresar competidores a mano, uno por uno.'),
  ('csv', 'Importar CSV', true, 'Importar un archivo con varios competidores a la vez.'),
  ('demo', 'Datos de demostración', true, 'Solo para probar la interfaz — nunca datos de mercado reales.'),
  ('booking_authorized', 'Booking.com (oficial)', false, 'Requiere acceso autorizado a la Booking.com Demand/Connectivity API. Ver docs/obsidian/Inteligencia-de-Precios.md para los pasos pendientes.'),
  ('airbnb_authorized', 'Airbnb (oficial)', false, 'Requiere acceso autorizado como partner de software de Airbnb. Ver docs/obsidian/Inteligencia-de-Precios.md para los pasos pendientes.')
on conflict (key) do nothing;

alter table public.market_data_sources enable row level security;
create policy "market_data_sources_select_all" on public.market_data_sources
  for select using (auth.role() = 'authenticated');

-- ────────────────────────────────────────────────────────────────
-- 4) CONFIGURACIÓN DEL ALOJAMIENTO PROPIO PARA PRECIOS
-- Una fila por alojamiento (no por tenant): cada propiedad tiene
-- su propio mínimo rentable, capacidad, comodidades, etc.
-- ────────────────────────────────────────────────────────────────
create table public.pricing_property_config (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  property_id uuid not null references public.properties(id) on delete cascade,
  tipo text,
  capacidad int,
  camas int,
  dormitorios int,
  banos int,
  bano_privado boolean,
  aire_acondicionado boolean,
  cocina boolean,
  estacionamiento boolean,
  wifi boolean,
  distancia_centro_km numeric,
  puntuacion numeric,
  cantidad_resenas int,
  precio_minimo_rentable numeric,
  precio_minimo_permitido numeric,
  precio_habitual numeric,
  precio_maximo_recomendado numeric,
  costo_variable_por_noche numeric,
  comision_plataforma_pct numeric,
  gastos_limpieza numeric,
  moneda text not null default 'UYU',
  ocupacion_objetivo_pct numeric,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  unique(tenant_id, property_id)
);

comment on table public.pricing_property_config is 'Configuración de precios de cada alojamiento propio: mínimo rentable, comodidades, costos. precio_minimo_rentable es el piso que el motor de recomendación nunca cruza sin advertirlo.';

alter table public.pricing_property_config enable row level security;

create policy "pricing_property_config_select_own_tenant" on public.pricing_property_config
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence());

create policy "pricing_property_config_insert_own_tenant" on public.pricing_property_config
  for insert with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('configurar_precio_minimo'));

create policy "pricing_property_config_update_own_tenant" on public.pricing_property_config
  for update using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence())
  with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('configurar_precio_minimo'));

create index idx_pricing_property_config_tenant on public.pricing_property_config(tenant_id);
create index idx_pricing_property_config_property on public.pricing_property_config(property_id);

-- ────────────────────────────────────────────────────────────────
-- 5) GRUPOS DE COMPETIDORES
-- ────────────────────────────────────────────────────────────────
create table public.competitor_sets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  property_id uuid references public.properties(id) on delete set null,
  nombre text not null,
  zona text,
  source_key text not null default 'manual' references public.market_data_sources(key),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

comment on table public.competitor_sets is 'Un grupo nombrado de competidores (ej: "Chuy — centro", 5 a 30 alojamientos) para comparar contra un alojamiento propio.';

alter table public.competitor_sets enable row level security;

create policy "competitor_sets_select_own_tenant" on public.competitor_sets
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence());

create policy "competitor_sets_insert_own_tenant" on public.competitor_sets
  for insert with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('crear_analisis_precios'));

create policy "competitor_sets_update_own_tenant" on public.competitor_sets
  for update using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence())
  with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('modificar_competidores_precios'));

create policy "competitor_sets_delete_own_tenant" on public.competitor_sets
  for delete using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('modificar_competidores_precios'));

create index idx_competitor_sets_tenant on public.competitor_sets(tenant_id);
create index idx_competitor_sets_property on public.competitor_sets(property_id);

-- ────────────────────────────────────────────────────────────────
-- 6) COMPETIDORES (cada fila = una observación de un alojamiento
-- competidor, cargada a mano, por CSV, o de demostración).
-- ────────────────────────────────────────────────────────────────
create table public.competitor_properties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  set_id uuid not null references public.competitor_sets(id) on delete cascade,
  source_key text not null default 'manual' references public.market_data_sources(key),
  nombre text not null,
  plataforma text,
  zona text,
  checkin date,
  checkout date,
  noches int,
  capacidad int,
  tipo_alojamiento text,
  precio_total numeric,
  moneda text not null default 'UYU',
  impuestos_incluidos text check (impuestos_incluidos in ('si','no','desconocido')) default 'desconocido',
  cargos_adicionales numeric,
  precio_final numeric,
  disponible text check (disponible in ('si','no','desconocido','no_aparecio','fuera_de_filtros')) default 'desconocido',
  distancia_km numeric,
  puntuacion numeric,
  cantidad_resenas int,
  bano_privado boolean,
  aire_acondicionado boolean,
  cocina boolean,
  estacionamiento boolean,
  cancelacion_gratuita boolean,
  desayuno boolean,
  enlace text,
  observado_en timestamptz not null default now(),
  similarity_score int,
  similarity_reasons text,
  incluido_en_analisis boolean not null default true,
  excluido_motivo text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  constraint similarity_score_range check (similarity_score is null or (similarity_score >= 0 and similarity_score <= 100))
);

comment on table public.competitor_properties is 'Una fila por competidor observado. similarity_score (0-100) y similarity_reasons se calculan al cargar/editar, no se inventan si faltan datos. incluido_en_analisis permite que el usuario excluya un competidor sin borrarlo.';

alter table public.competitor_properties enable row level security;

create policy "competitor_properties_select_own_tenant" on public.competitor_properties
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence());

create policy "competitor_properties_insert_own_tenant" on public.competitor_properties
  for insert with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and (public.has_permission('crear_analisis_precios') or public.has_permission('importar_datos_precios')));

create policy "competitor_properties_update_own_tenant" on public.competitor_properties
  for update using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence())
  with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('modificar_competidores_precios'));

create policy "competitor_properties_delete_own_tenant" on public.competitor_properties
  for delete using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('modificar_competidores_precios'));

create index idx_competitor_properties_tenant on public.competitor_properties(tenant_id);
create index idx_competitor_properties_set on public.competitor_properties(set_id);
create index idx_competitor_properties_observado on public.competitor_properties(observado_en);
create index idx_competitor_properties_disponible on public.competitor_properties(disponible);

-- ────────────────────────────────────────────────────────────────
-- 7) BÚSQUEDAS DE MERCADO (una consulta: qué alojamiento, qué
-- fechas, qué estrategia) + su resultado estadístico + su
-- recomendación. Tres tablas separadas porque cada una tiene un
-- ciclo de vida propio (una búsqueda puede recalcularse sin perder
-- el historial de resultados anteriores, pensado para la fase de
-- historial/evolución más adelante).
-- ────────────────────────────────────────────────────────────────
create table public.market_searches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  property_id uuid not null references public.properties(id),
  set_id uuid references public.competitor_sets(id),
  zona text,
  checkin date not null,
  checkout date not null,
  adultos int not null default 2,
  ninos int not null default 0,
  habitaciones int not null default 1,
  moneda text not null default 'UYU',
  estrategia text not null check (estrategia in ('ganar_reservas','equilibrado','maximizar_ingresos','personalizado')) default 'equilibrado',
  precio_actual numeric,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

comment on table public.market_searches is 'Una consulta de precio: alojamiento + fechas + estrategia elegida. stay_date=checkin para el índice.';

alter table public.market_searches enable row level security;

create policy "market_searches_select_own_tenant" on public.market_searches
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence());

create policy "market_searches_insert_own_tenant" on public.market_searches
  for insert with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('crear_analisis_precios'));

create policy "market_searches_delete_own_tenant" on public.market_searches
  for delete using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('crear_analisis_precios'));

create index idx_market_searches_tenant on public.market_searches(tenant_id);
create index idx_market_searches_property on public.market_searches(property_id);
create index idx_market_searches_checkin on public.market_searches(checkin);

create table public.market_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  search_id uuid not null references public.market_searches(id) on delete cascade,
  sample_count int not null default 0,
  valid_count int not null default 0,
  excluded_count int not null default 0,
  min_price numeric,
  p10 numeric,
  p25 numeric,
  median_price numeric,
  avg_price numeric,
  p75 numeric,
  p90 numeric,
  max_price numeric,
  dispersion numeric,
  availability_estimate_pct numeric,
  confidence text check (confidence in ('alta','media','baja','insuficiente')),
  confidence_reasons text,
  created_at timestamptz not null default now()
);

comment on table public.market_snapshots is 'Resultado estadístico de una búsqueda: percentiles, cuántas muestras válidas/excluidas, disponibilidad ESTIMADA de la muestra (nunca "del mercado real"), y confianza.';

alter table public.market_snapshots enable row level security;

create policy "market_snapshots_select_own_tenant" on public.market_snapshots
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence());

create policy "market_snapshots_insert_own_tenant" on public.market_snapshots
  for insert with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('crear_analisis_precios'));

create index idx_market_snapshots_tenant on public.market_snapshots(tenant_id);
create index idx_market_snapshots_search on public.market_snapshots(search_id);

create table public.price_recommendations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  search_id uuid not null references public.market_searches(id) on delete cascade,
  snapshot_id uuid not null references public.market_snapshots(id) on delete cascade,
  precio_actual numeric,
  precio_recomendado numeric,
  diferencia_monto numeric,
  diferencia_pct numeric,
  rango_bajo numeric,
  rango_alto numeric,
  confidence text check (confidence in ('alta','media','baja','insuficiente')),
  motivos text,
  riesgos text,
  accion_sugerida text,
  limitado_por_minimo boolean not null default false,
  calculado_en timestamptz not null default now(),
  accion_usuario text check (accion_usuario in ('pendiente','aceptada','rechazada','precio_personalizado','recordar_mas_tarde')) not null default 'pendiente',
  precio_aplicado numeric,
  accion_usuario_en timestamptz,
  accion_usuario_por uuid references auth.users(id)
);

comment on table public.price_recommendations is 'La recomendación final de una búsqueda, con explicación (motivos/riesgos) y qué decidió el usuario. limitado_por_minimo=true cuando el precio competitivo hubiera quedado debajo del mínimo rentable configurado, y se lo respetó en vez de bajar más.';

alter table public.price_recommendations enable row level security;

create policy "price_recommendations_select_own_tenant" on public.price_recommendations
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence());

create policy "price_recommendations_insert_own_tenant" on public.price_recommendations
  for insert with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('crear_analisis_precios'));

create policy "price_recommendations_update_own_tenant" on public.price_recommendations
  for update using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence())
  with check (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('aceptar_recomendaciones_precios'));

create index idx_price_recommendations_tenant on public.price_recommendations(tenant_id);
create index idx_price_recommendations_search on public.price_recommendations(search_id);
