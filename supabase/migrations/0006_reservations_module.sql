-- ════════════════════════════════════════════════════════════════
-- 0006 — RESERVATIONS (Reservas): el módulo más grande y más usado.
-- Primera vez que hay una FK real de reservas hacia alojamientos
-- (propiedad_id), ya que ambos viven en Supabase.
-- ════════════════════════════════════════════════════════════════

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  propiedad_id uuid not null references public.properties(id),
  huesped text not null,
  telefono text,
  email text,
  huespedes int not null default 1,
  checkin date not null,
  checkout date not null,
  noches int not null default 0,
  precio numeric not null default 0,
  descuento numeric not null default 0,
  tiene_comision_plat text not null default 'no' check (tiene_comision_plat in ('si','no')),
  comision_plat_pct numeric not null default 0,
  quien_cobra text not null default 'yo',
  estado text not null default 'consulta' check (estado in
    ('consulta','esperando-sena','sena-parcial','sena-confirmada','confirmada',
     'checkin-pendiente','alojado','checkout-realizado','saldo-pendiente',
     'finalizada','cancelada','no-presentada')),
  canal text,
  metodo_pago text,
  notas text,
  comision_pagada text not null default 'no' check (comision_pagada in ('si','no')),
  fecha_comision date,
  deposito_pagado text not null default 'no' check (deposito_pagado in ('si','no')),
  fecha_deposito date,
  sena_parcial numeric not null default 0,
  comprobante text,
  horario text,
  -- guest_id queda como texto (no FK) porque Huéspedes todavía vive en
  -- localStorage con IDs numéricos de la demo — se conecta de verdad
  -- cuando ese módulo se migre.
  guest_id text,
  history jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index reservations_tenant_idx on public.reservations(tenant_id);
create index reservations_propiedad_idx on public.reservations(propiedad_id);

alter table public.reservations enable row level security;

create policy "reservations_select_own_tenant" on public.reservations
  for select using (tenant_id = public.current_tenant_id());

create policy "reservations_insert_own_tenant" on public.reservations
  for insert with check (tenant_id = public.current_tenant_id());

create policy "reservations_update_own_tenant" on public.reservations
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "reservations_delete_own_tenant" on public.reservations
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_reservations_insert_audit
  before insert on public.reservations
  for each row execute function public.set_audit_fields();

create trigger trg_reservations_update_audit
  before update on public.reservations
  for each row execute function public.set_audit_fields();
