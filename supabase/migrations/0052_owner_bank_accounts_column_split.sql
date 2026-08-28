-- ════════════════════════════════════════════════════════════════
-- 0052 — owners.cuenta (dato bancario del propietario) era un caso que
-- RLS por fila no puede resolver: el permiso "ver_datos_bancarios" existe
-- en el catálogo desde 0019 pero era imposible de aplicar porque toda la
-- fila de owners comparte una sola política de SELECT. Se separa la
-- columna a su propia tabla, con su propio RLS gateado por ese permiso.
--
-- No se pierde ningún dato: se copia primero, se dropea la columna después.
-- Los propietarios sin cuenta cargada (null/vacío) no generan fila nueva.
-- ════════════════════════════════════════════════════════════════

create table public.owner_bank_accounts (
  owner_id uuid primary key references public.owners(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id),
  cuenta text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.owner_bank_accounts enable row level security;

-- Ver: exige el permiso específico, no alcanza con ver_propietarios ni con
-- pertenecer al tenant.
create policy "owner_bank_accounts_select_own_tenant" on public.owner_bank_accounts
  for select using (tenant_id = public.current_tenant_id() and public.has_permission('ver_datos_bancarios'));

-- Escribir: exige AMBOS permisos -- poder editar propietarios en general Y
-- poder ver datos bancarios. Alguien sin ver_datos_bancarios no debería
-- poder sobrescribir a ciegas un dato que ni siquiera puede leer.
create policy "owner_bank_accounts_insert_own_tenant" on public.owner_bank_accounts
  for insert with check (
    tenant_id = public.current_tenant_id()
    and public.has_permission('editar_propietarios')
    and public.has_permission('ver_datos_bancarios')
  );

create policy "owner_bank_accounts_update_own_tenant" on public.owner_bank_accounts
  for update using (tenant_id = public.current_tenant_id())
  with check (
    tenant_id = public.current_tenant_id()
    and public.has_permission('editar_propietarios')
    and public.has_permission('ver_datos_bancarios')
  );

create policy "owner_bank_accounts_delete_own_tenant" on public.owner_bank_accounts
  for delete using (
    tenant_id = public.current_tenant_id()
    and public.has_permission('editar_propietarios')
    and public.has_permission('ver_datos_bancarios')
  );

create trigger trg_owner_bank_accounts_update_audit
  before update on public.owner_bank_accounts
  for each row execute function public.set_audit_fields();

-- Copiar los datos reales antes de dropear la columna. Solo propietarios
-- con algo cargado (no null, no cadena vacía) generan fila.
insert into public.owner_bank_accounts (owner_id, tenant_id, cuenta)
select id, tenant_id, cuenta
from public.owners
where cuenta is not null and btrim(cuenta) <> '';

alter table public.owners drop column cuenta;
