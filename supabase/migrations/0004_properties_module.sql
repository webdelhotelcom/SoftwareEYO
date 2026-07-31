-- ════════════════════════════════════════════════════════════════
-- 0004 — PROPERTIES (Alojamientos): primer módulo migrado por completo
-- Mismos campos que el objeto "property" de la demo en localStorage,
-- para no perder ninguna función existente al migrar.
-- ════════════════════════════════════════════════════════════════

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  nombre text not null,
  direccion text,
  propietario_id uuid,          -- se conecta a la tabla owners en la Fase 2
  capacidad int not null default 4,
  precio numeric not null default 0,
  comision_pct numeric not null default 10,
  estado text not null default 'activo',
  cuenta text,
  checkin_h text,
  checkout_h text,
  wifi text,
  wifi_pass text,
  acceso text,
  normas text,
  info text,
  contacto text,
  notas text,
  seasons jsonb not null default '[]'::jsonb,   -- precios por temporada: [{nombre,desde,hasta,precio}, ...]
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.properties enable row level security;

create policy "properties_select_own_tenant" on public.properties
  for select using (tenant_id = public.current_tenant_id());

create policy "properties_insert_own_tenant" on public.properties
  for insert with check (tenant_id = public.current_tenant_id());

create policy "properties_update_own_tenant" on public.properties
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "properties_delete_own_tenant" on public.properties
  for delete using (tenant_id = public.current_tenant_id());

-- Mantiene created_by/updated_at/updated_by al día automáticamente
-- (base del futuro registro de auditoría — Fase 2).
create or replace function public.set_properties_audit_fields()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$;

create trigger trg_properties_insert_audit
  before insert on public.properties
  for each row execute function public.set_properties_audit_fields();

create trigger trg_properties_update_audit
  before update on public.properties
  for each row execute function public.set_properties_audit_fields();

-- ══════════════════════════════════════════════════════════════
-- Límite de alojamientos por contrato — validado en el servidor.
-- Corre pase lo que pase en el navegador: nadie puede saltarse esto
-- editando el JavaScript del panel.
-- ══════════════════════════════════════════════════════════════
create or replace function public.check_properties_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_plan_max int;
  v_client_max int;
  v_effective int;
  v_count int;
begin
  select plan into v_plan from public.tenants where id = new.tenant_id;
  select max_properties into v_plan_max from public.plan_config where plan = v_plan;
  select max_properties into v_client_max from public.client_limits where tenant_id = new.tenant_id;
  v_effective := coalesce(v_client_max, v_plan_max);

  if v_effective is null then
    raise exception 'Límite de alojamientos no configurado para este cliente. Contactá al administrador de EYO.';
  end if;

  select count(*) into v_count from public.properties where tenant_id = new.tenant_id;
  if v_count >= v_effective then
    raise exception 'Alcanzaste el límite de % alojamientos de tu plan.', v_effective;
  end if;

  return new;
end;
$$;

create trigger trg_properties_limit
  before insert on public.properties
  for each row execute function public.check_properties_limit();
