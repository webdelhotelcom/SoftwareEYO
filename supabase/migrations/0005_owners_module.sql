-- ════════════════════════════════════════════════════════════════
-- 0005 — OWNERS (Propietarios): segundo módulo migrado por completo.
-- También conecta de verdad properties.propietario_id, que hasta ahora
-- existía pero no tenía ninguna tabla real del otro lado.
-- ════════════════════════════════════════════════════════════════

create table public.owners (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  nombre text not null,
  telefono text,
  email text,
  cuenta text,
  notas text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.owners enable row level security;

create policy "owners_select_own_tenant" on public.owners
  for select using (tenant_id = public.current_tenant_id());

create policy "owners_insert_own_tenant" on public.owners
  for insert with check (tenant_id = public.current_tenant_id());

create policy "owners_update_own_tenant" on public.owners
  for update using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id());

create policy "owners_delete_own_tenant" on public.owners
  for delete using (tenant_id = public.current_tenant_id());

-- Función genérica de auditoría (igual a la que ya usa properties, con
-- nombre reutilizable para el resto de los módulos que se migren después).
create or replace function public.set_audit_fields()
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

create trigger trg_owners_insert_audit
  before insert on public.owners
  for each row execute function public.set_audit_fields();

create trigger trg_owners_update_audit
  before update on public.owners
  for each row execute function public.set_audit_fields();

-- Ahora que owners existe de verdad, conectamos la referencia que
-- properties.propietario_id ya tenía preparada desde la Fase 1.
alter table public.properties
  add constraint properties_propietario_id_fkey
  foreign key (propietario_id) references public.owners(id) on delete set null;
