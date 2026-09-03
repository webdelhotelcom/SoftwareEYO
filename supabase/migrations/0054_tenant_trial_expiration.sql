-- ════════════════════════════════════════════════════════════════
-- 0054 — Vencimiento automático real para clientes de prueba.
--
-- Agrega tenants.trial_expires_at (nullable -- NULL = nunca vence,
-- todos los clientes reales de hoy quedan sin cambios). Las 4 funciones
-- que gatean el acceso a TODA la base (current_tenant_id/has_permission/
-- is_admin/current_owner_id) pasan a exigir además que el tenant no haya
-- vencido -- mismo mecanismo exacto que 0020_deactivated_user_lockout.sql
-- ya usa para active=false: en cuanto pasan las 24hs, Postgres deja de
-- reconocerle tenant al usuario, así que TODA política "tenant_id =
-- current_tenant_id()" empieza a fallar de inmediato, sin depender de
-- que nadie lo desactive a mano ni de que el navegador cierre la sesión.
-- ════════════════════════════════════════════════════════════════

alter table public.tenants add column trial_expires_at timestamptz;

comment on column public.tenants.trial_expires_at is 'NULL = el cliente no vence nunca (caso normal). Si tiene fecha, current_tenant_id()/has_permission()/is_admin()/current_owner_id() dejan de reconocer a cualquier usuario de este tenant apenas se cumple -- vencimiento real, no solo un aviso de UI.';

create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.tenant_id
  from public.profiles p
  join public.tenants t on t.id = p.tenant_id
  where p.id = auth.uid() and p.active = true
    and (t.trial_expires_at is null or t.trial_expires_at > now())
$$;

create or replace function public.has_permission(perm_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select rp.allowed
     from public.profiles pr
     join public.tenants t on t.id = pr.tenant_id
     join public.role_permissions rp
       on rp.tenant_id = pr.tenant_id and rp.role = pr.role and rp.permission_key = perm_key
     where pr.id = auth.uid() and pr.active = true
       and (t.trial_expires_at is null or t.trial_expires_at > now())),
    false
  )
$$;

create or replace function public.current_owner_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.owner_id
  from public.profiles p
  join public.tenants t on t.id = p.tenant_id
  where p.id = auth.uid() and p.active = true
    and (t.trial_expires_at is null or t.trial_expires_at > now())
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles p
    join public.tenants t on t.id = p.tenant_id
    where p.id = auth.uid() and p.role = 'admin' and p.active = true
      and (t.trial_expires_at is null or t.trial_expires_at > now())
  )
$$;

-- Igual que profiles_select_self_always (0020): sin esto, "tenants_select_own"
-- (que depende de current_tenant_id()) también dejaría de ver la fila del
-- propio tenant apenas vence -- el panel necesita poder leer trial_expires_at
-- de SU PROPIO tenant incluso vencido, para mostrar "Tu prueba venció" en vez
-- de un error suelto. No depende de active ni del vencimiento -- un usuario
-- siempre puede saber a qué tenant pertenece y si ese tenant venció.
create policy "tenants_select_own_via_profile" on public.tenants
  for select using (
    id = (select tenant_id from public.profiles where id = auth.uid())
  );
