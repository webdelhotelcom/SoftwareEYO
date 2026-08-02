-- ════════════════════════════════════════════════════════════════
-- 0014 — CHECK-IN / CHECK-OUT: estadías (stays), con la cuenta del
-- huésped (folio) guardada como jsonb dentro de la misma fila —
-- mismo patrón que properties.seasons (0004).
-- ════════════════════════════════════════════════════════════════

create table public.stays (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  room_id uuid references public.rooms(id),
  huesped text not null,
  doc text,
  pais text,
  checkin date not null,
  checkout date not null,
  hora_llegada text,
  estado text not null default 'in_house',
  precio_noche numeric(12,2) not null default 0,
  notas text,
  folio jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index stays_tenant_idx on public.stays(tenant_id);

alter table public.stays enable row level security;

create policy "stays_select_own_tenant" on public.stays
  for select using (tenant_id = public.current_tenant_id());

create policy "stays_insert_own_tenant" on public.stays
  for insert with check (tenant_id = public.current_tenant_id());

create policy "stays_update_own_tenant" on public.stays
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "stays_delete_own_tenant" on public.stays
  for delete using (tenant_id = public.current_tenant_id());

create trigger trg_stays_insert_audit
  before insert on public.stays
  for each row execute function public.set_audit_fields();

create trigger trg_stays_update_audit
  before update on public.stays
  for each row execute function public.set_audit_fields();

create trigger trg_audit_stays
  after insert or update or delete on public.stays
  for each row execute function public.log_audit_event();
