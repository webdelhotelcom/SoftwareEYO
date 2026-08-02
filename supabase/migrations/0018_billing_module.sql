-- ════════════════════════════════════════════════════════════════
-- 0018 — PRE-FACTURACIÓN: último módulo pendiente de Fase 3.
-- billing_config es una fila por tenant (configuración del emisor y
-- numeración); facturas guarda cada comprobante con una copia (jsonb)
-- del emisor tal como estaba al momento de emitirlo, para que un
-- cambio posterior en billing_config no altere comprobantes ya
-- emitidos.
-- ════════════════════════════════════════════════════════════════

create table public.billing_config (
  id uuid not null default gen_random_uuid(),
  tenant_id uuid primary key references public.tenants(id),
  razon text,
  fantasia text,
  rut text,
  giro text,
  domicilio text,
  sucursal text,
  cae text,
  cae_venc text,
  serie text not null default 'A',
  desde int not null default 1,
  hasta int not null default 1000,
  prox int not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.billing_config enable row level security;

create policy "billing_config_select_own_tenant" on public.billing_config
  for select using (tenant_id = public.current_tenant_id());

create policy "billing_config_insert_own_tenant" on public.billing_config
  for insert with check (tenant_id = public.current_tenant_id());

create policy "billing_config_update_own_tenant" on public.billing_config
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create trigger trg_billing_config_insert_audit
  before insert on public.billing_config
  for each row execute function public.set_audit_fields();

create trigger trg_billing_config_update_audit
  before update on public.billing_config
  for each row execute function public.set_audit_fields();

create trigger trg_audit_billing_config
  after insert or update on public.billing_config
  for each row execute function public.log_audit_event();

create table public.facturas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  tipo text not null,
  serie text not null,
  numero int not null,
  fecha date not null default current_date,
  moneda text not null default 'UYU',
  receptor_nombre text,
  doc_tipo text,
  doc_num text,
  domicilio text,
  lines jsonb not null default '[]'::jsonb,
  neto numeric(12,2) not null default 0,
  iva_total numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  codigo_seguridad text,
  cae text,
  cae_venc text,
  emisor jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index facturas_tenant_idx on public.facturas(tenant_id);

alter table public.facturas enable row level security;

create policy "facturas_select_own_tenant" on public.facturas
  for select using (tenant_id = public.current_tenant_id());

create policy "facturas_insert_own_tenant" on public.facturas
  for insert with check (tenant_id = public.current_tenant_id());

create policy "facturas_update_own_tenant" on public.facturas
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "facturas_delete_own_tenant" on public.facturas
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_facturas_insert_audit
  before insert on public.facturas
  for each row execute function public.set_audit_fields();

create trigger trg_facturas_update_audit
  before update on public.facturas
  for each row execute function public.set_audit_fields();

create trigger trg_audit_facturas
  after insert or update or delete on public.facturas
  for each row execute function public.log_audit_event();
