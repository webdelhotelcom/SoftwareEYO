-- ════════════════════════════════════════════════════════════════
-- 0027 — Frecuencia de investigaciones de mercado según el plan
-- contratado (Inteligencia de Precios).
--
-- IMPORTANTE — alcance real de esta migración: NO agrega ningún bot
-- de scraping. Se decidió explícitamente no construir un navegador
-- automatizado que abra Google Maps/Hotels, Booking o Airbnb, porque
-- eso viola los términos de servicio de esas plataformas (todas
-- prohíben la extracción automatizada sin autorización) y además
-- contradice la propia regla que se había fijado para este módulo:
-- "NO scraping/bots/crawlers/evasión CAPTCHA". Ver la sección
-- "Frecuencia por plan" en docs/obsidian/Inteligencia-de-Precios.md.
--
-- Lo que SÍ agrega esta migración es el sistema de cupos: cuántas
-- "investigaciones completas" (ejecuciones del motor de recomendación
-- ya existente, migración 0025) puede hacer cada tenant por mes según
-- su plan, validado en el servidor y en la base de datos — no solo en
-- pantalla — con un botón manual para administradores autorizados.
-- Cuando en el futuro exista una fuente automática real (API oficial
-- de Booking/Airbnb autorizada), se conecta a este mismo sistema de
-- cupos sin tener que rehacerlo.
-- ════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1) CUPO MENSUAL POR PLAN
-- ────────────────────────────────────────────────────────────────
alter table public.plan_config add column if not exists pricing_market_scans_monthly int not null default 0;
update public.plan_config set pricing_market_scans_monthly = 0 where plan = 'inicial';
update public.plan_config set pricing_market_scans_monthly = 2 where plan = 'profesional';
update public.plan_config set pricing_market_scans_monthly = 4 where plan = 'hotel';

comment on column public.plan_config.pricing_market_scans_monthly is 'Investigaciones completas de mercado incluidas por mes. Profesional=2 (1er y 3er lunes), Hotel=4 (1er a 4to lunes). El valor de Profesional queda preparado pero sin efecto real mientras pricing_intelligence_enabled siga en false para ese plan.';

-- Permiso separado para el botón manual "Ejecutar investigación
-- ahora" — no todo el que puede VER análisis de precios debe poder
-- disparar una ejecución extraordinaria.
insert into public.permissions_catalog (key,label,sort_order) values
  ('ejecutar_investigacion_manual_precios','Ejecutar investigación de mercado manual',89)
on conflict (key) do nothing;

insert into public.role_permissions (tenant_id, role, permission_key, allowed)
select t.id, r.role, 'ejecutar_investigacion_manual_precios',
  case when r.role in ('admin','gerencia') then true else false end
from public.tenants t
cross join (values ('admin'),('gerencia'),('encargado'),('recepcion'),('limpieza'),('mantenimiento'),('contador'),('propietario')) as r(role)
on conflict (tenant_id, role, permission_key) do nothing;

-- ────────────────────────────────────────────────────────────────
-- 2) CONTADOR MENSUAL POR TENANT
-- Una fila por (tenant, año, mes). plan_code/monthly_limit reflejan
-- el plan VIGENTE al momento de la última sincronización (ver
-- sync_market_scan_usage más abajo) — si el tenant cambia de plan a
-- mitad de mes, estos dos campos se actualizan pero
-- automatic_scans_used/manual_scans_used NUNCA se reinician.
-- ────────────────────────────────────────────────────────────────
create table public.tenant_market_scan_usage (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  year int not null,
  month int not null check (month between 1 and 12),
  plan_code text not null,
  monthly_limit int not null default 0,
  automatic_scans_used int not null default 0,
  manual_scans_used int not null default 0,
  last_scan_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id, year, month)
);

comment on table public.tenant_market_scan_usage is 'Cupo e investigaciones usadas por tenant y mes. automatic_scans_used/manual_scans_used solo se modifican mediante register_market_scan()/sync_market_scan_usage() (security definer) — nunca por escritura directa del cliente.';

alter table public.tenant_market_scan_usage enable row level security;

create policy "tenant_market_scan_usage_select_own_tenant" on public.tenant_market_scan_usage
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('ver_analisis_precios'));

-- Sin políticas de insert/update/delete: toda escritura pasa por las
-- funciones security definer de más abajo, que validan permiso, plan,
-- calendario y límite antes de tocar la tabla.

create index idx_tenant_market_scan_usage_tenant on public.tenant_market_scan_usage(tenant_id);

-- ────────────────────────────────────────────────────────────────
-- 3) REGISTRO DE CADA INVESTIGACIÓN (para auditoría e idempotencia)
-- ────────────────────────────────────────────────────────────────
create table public.market_scan_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  scan_type text not null check (scan_type in ('automatico','manual')),
  scan_date date not null default current_date,
  period_start date not null,
  period_end date not null,
  competitor_set_id uuid references public.competitor_sets(id) on delete set null,
  search_id uuid references public.market_searches(id) on delete set null,
  triggered_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

comment on table public.market_scan_log is 'Una fila por investigación ejecutada (automática o manual). El índice único de abajo es el mecanismo de idempotencia: no permite repetir el mismo tenant + mismo día + mismo tipo + mismo período analizado.';

alter table public.market_scan_log enable row level security;

create policy "market_scan_log_select_own_tenant" on public.market_scan_log
  for select using (tenant_id = public.current_tenant_id() and public.has_pricing_intelligence() and public.has_permission('ver_analisis_precios'));

create unique index market_scan_log_dedupe
  on public.market_scan_log(tenant_id, scan_date, scan_type, period_start, period_end);

create index idx_market_scan_log_tenant on public.market_scan_log(tenant_id);
create index idx_market_scan_log_scan_date on public.market_scan_log(scan_date);

-- ────────────────────────────────────────────────────────────────
-- 4) FUNCIONES
-- ────────────────────────────────────────────────────────────────

-- Trae (o crea) la fila del mes actual, sincronizando plan_code y
-- monthly_limit con el plan vigente del tenant SIN tocar los
-- contadores ya acumulados este mes.
create or replace function public.sync_market_scan_usage(p_tenant_id uuid)
returns public.tenant_market_scan_usage
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_limit int;
  v_year int := extract(year from current_date)::int;
  v_month int := extract(month from current_date)::int;
  v_row public.tenant_market_scan_usage;
begin
  select t.plan into v_plan from public.tenants t where t.id = p_tenant_id;
  if v_plan is null then
    raise exception 'Tenant % no encontrado', p_tenant_id;
  end if;
  select coalesce(pc.pricing_market_scans_monthly, 0) into v_limit
    from public.plan_config pc where pc.plan = v_plan;

  insert into public.tenant_market_scan_usage(tenant_id, year, month, plan_code, monthly_limit)
  values (p_tenant_id, v_year, v_month, v_plan, coalesce(v_limit, 0))
  on conflict (tenant_id, year, month) do update
    set plan_code = excluded.plan_code,
        monthly_limit = excluded.monthly_limit,
        updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

comment on function public.sync_market_scan_usage(uuid) is 'Crea/actualiza la fila del mes actual con el plan vigente, sin resetear los contadores — así un cambio de plan a mitad de mes aplica el nuevo límite de inmediato sin perder lo ya usado.';

-- Qué lunes del mes es una fecha (1 a 5).
create or replace function public.monday_ordinal_of_month(d date)
returns int
language sql
immutable
as $$
  select ((extract(day from d)::int - 1) / 7) + 1
$$;

-- Próximo lunes habilitado según el calendario del plan, a partir de
-- una fecha, considerando el cupo restante del mes en curso. Los
-- meses futuros se asumen con cupo completo (aproximación razonable:
-- lo único que importa gobernar en vivo es el mes actual).
create or replace function public.next_allowed_monday(p_plan text, p_from date, p_current_month_remaining int)
returns date
language plpgsql
immutable
as $$
declare
  d date;
  ord int;
  allowed int[] := case p_plan
    when 'profesional' then array[1,3]
    when 'hotel' then array[1,2,3,4]
    else array[]::int[]
  end;
  i int := 0;
begin
  if array_length(allowed,1) is null then
    return null;
  end if;
  d := p_from + (((8 - extract(isodow from p_from)::int) % 7));
  while i < 60 loop
    ord := public.monday_ordinal_of_month(d);
    if ord = any(allowed) then
      if date_trunc('month', d) = date_trunc('month', p_from) then
        if p_current_month_remaining > 0 then
          return d;
        end if;
      else
        return d;
      end if;
    end if;
    d := d + 7;
    i := i + 1;
  end loop;
  return null;
end;
$$;

-- Estado de cupo para mostrar en el panel.
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

comment on function public.get_market_scan_status(uuid) is 'Estado de cupo del mes en curso para el panel: plan, límite, usadas, restantes, última/próxima fecha habilitada.';

-- Registra una investigación (automática o manual), validando plan,
-- permiso, calendario y límite EN EL SERVIDOR — nunca confía en lo
-- que mande el navegador. Lanza una excepción si algo no corresponde;
-- el índice único de market_scan_log impide duplicados.
create or replace function public.register_market_scan(
  p_tenant_id uuid,
  p_scan_type text,
  p_period_start date,
  p_period_end date,
  p_competitor_set_id uuid default null,
  p_search_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.tenant_market_scan_usage;
  v_calendar int[];
  v_ord int;
  v_log_id uuid;
  v_today date := current_date;
begin
  if p_tenant_id <> public.current_tenant_id() then
    raise exception 'No autorizado';
  end if;
  if p_scan_type not in ('automatico','manual') then
    raise exception 'Tipo de investigación inválido: %', p_scan_type;
  end if;
  if not public.has_pricing_intelligence() then
    raise exception 'Este plan no tiene habilitada Inteligencia de Precios';
  end if;
  if not public.has_permission('crear_analisis_precios') then
    raise exception 'No tenés permiso para crear análisis de precios';
  end if;
  if p_scan_type = 'manual' and not public.has_permission('ejecutar_investigacion_manual_precios') then
    raise exception 'No tenés permiso para ejecutar una investigación manual';
  end if;

  v_row := public.sync_market_scan_usage(p_tenant_id);
  v_calendar := case v_row.plan_code
    when 'profesional' then array[1,3]
    when 'hotel' then array[1,2,3,4]
    else array[]::int[]
  end;

  if p_scan_type = 'automatico' then
    if array_length(v_calendar,1) is null then
      raise exception 'El plan % no incluye investigaciones automáticas', v_row.plan_code;
    end if;
    if extract(isodow from v_today)::int <> 1 then
      raise exception 'Las investigaciones automáticas solo se ejecutan los lunes';
    end if;
    v_ord := public.monday_ordinal_of_month(v_today);
    if not (v_ord = any(v_calendar)) then
      raise exception 'Este lunes no está habilitado para el plan %', v_row.plan_code;
    end if;
    if v_row.automatic_scans_used >= v_row.monthly_limit then
      raise exception 'Se alcanzó el límite mensual de investigaciones automáticas (% de %)', v_row.automatic_scans_used, v_row.monthly_limit;
    end if;
  end if;

  begin
    insert into public.market_scan_log(
      tenant_id, scan_type, scan_date, period_start, period_end,
      competitor_set_id, search_id, triggered_by
    ) values (
      p_tenant_id, p_scan_type, v_today, p_period_start, p_period_end,
      p_competitor_set_id, p_search_id, auth.uid()
    ) returning id into v_log_id;
  exception when unique_violation then
    raise exception 'Ya existe una investigación % registrada hoy para ese período', p_scan_type;
  end;

  if p_scan_type = 'automatico' then
    update public.tenant_market_scan_usage
      set automatic_scans_used = automatic_scans_used + 1, last_scan_at = now(), updated_at = now()
      where tenant_id = p_tenant_id and year = v_row.year and month = v_row.month;
  else
    update public.tenant_market_scan_usage
      set manual_scans_used = manual_scans_used + 1, last_scan_at = now(), updated_at = now()
      where tenant_id = p_tenant_id and year = v_row.year and month = v_row.month;
  end if;

  return v_log_id;
end;
$$;

comment on function public.register_market_scan(uuid, text, date, date, uuid, uuid) is 'Única puerta de entrada para registrar una investigación. Valida plan, permiso, calendario (lunes habilitado) y límite mensual server-side antes de escribir nada — no se puede superar el cupo modificando el frontend ni llamando directo a Supabase sin pasar por acá.';
