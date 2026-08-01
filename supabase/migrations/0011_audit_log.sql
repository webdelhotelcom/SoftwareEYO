-- ════════════════════════════════════════════════════════════════
-- 0011 — AUDITORÍA: quién hizo qué, cuándo, con qué valor antes y después.
-- Registrado automáticamente por triggers en las tablas de negocio — no
-- depende de que el panel se acuerde de avisar, así que no se puede
-- saltear ni desde la consola del navegador. Nadie puede borrar ni
-- editar el historial desde el cliente (no hay política de insert/
-- update/delete para authenticated/anon, solo la función de abajo).
-- ════════════════════════════════════════════════════════════════

create table public.audit_log (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id),
  user_id uuid references auth.users(id),
  user_email text,
  action text not null,        -- INSERT | UPDATE | DELETE
  table_name text not null,    -- properties | owners | reservations | expenses | guests | profiles
  record_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index audit_log_tenant_idx on public.audit_log(tenant_id, created_at desc);

alter table public.audit_log enable row level security;

-- Solo administradores de su propio tenant pueden leer el historial.
create policy "audit_log_select_admin_only" on public.audit_log
  for select using (tenant_id = public.current_tenant_id() and public.is_admin());

create or replace function public.log_audit_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_user_email text;
  v_record_id text;
begin
  v_tenant := coalesce(new.tenant_id, old.tenant_id);
  v_record_id := coalesce(new.id, old.id)::text;
  select email into v_user_email from public.profiles where id = auth.uid();

  insert into public.audit_log (tenant_id, user_id, user_email, action, table_name, record_id, old_data, new_data)
  values (
    v_tenant,
    auth.uid(),
    v_user_email,
    tg_op,
    tg_table_name,
    v_record_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;

create trigger trg_audit_properties
  after insert or update or delete on public.properties
  for each row execute function public.log_audit_event();

create trigger trg_audit_owners
  after insert or update or delete on public.owners
  for each row execute function public.log_audit_event();

create trigger trg_audit_reservations
  after insert or update or delete on public.reservations
  for each row execute function public.log_audit_event();

create trigger trg_audit_expenses
  after insert or update or delete on public.expenses
  for each row execute function public.log_audit_event();

create trigger trg_audit_guests
  after insert or update or delete on public.guests
  for each row execute function public.log_audit_event();

create trigger trg_audit_profiles
  after insert or update or delete on public.profiles
  for each row execute function public.log_audit_event();
