-- ════════════════════════════════════════════════════════════════
-- 0020 — CORRECCIÓN ALTA DE LA AUDITORÍA (2026-08-02): un usuario
-- desactivado (profiles.active=false) dejaba de poder iniciar sesión
-- de nuevo, pero si ya tenía la sesión abierta, PostgreSQL lo seguía
-- dejando leer y escribir datos con total normalidad — se probó en
-- vivo creando una tarea con una sesión ya desactivada.
--
-- Esta migración hace que current_tenant_id(), has_permission() y
-- current_owner_id() dejen de reconocer a un usuario inactivo,
-- pase lo que pase con su token: para PostgreSQL, un perfil con
-- active=false directamente NO TIENE tenant, así que toda política
-- "tenant_id = current_tenant_id()" empieza a fallar de inmediato,
-- sin depender de que el navegador cierre la sesión.
-- ════════════════════════════════════════════════════════════════

create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select tenant_id from public.profiles where id = auth.uid() and active = true
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
     join public.role_permissions rp
       on rp.tenant_id = pr.tenant_id and rp.role = pr.role and rp.permission_key = perm_key
     where pr.id = auth.uid() and pr.active = true),
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
  select owner_id from public.profiles where id = auth.uid() and active = true
$$;

-- is_admin() ya exigía active=true desde 0009 — no se toca.

-- profiles_select_same_tenant usa current_tenant_id(), que ahora
-- devuelve NULL para un usuario desactivado: un usuario inactivo deja
-- de poder ver incluso su propia fila de profiles vía esa política.
-- Le agregamos una política aparte, mínima, para que un usuario
-- desactivado todavía pueda leer SU PROPIA fila (id = auth.uid()) —
-- necesario para que el panel pueda detectar "estoy desactivado" y
-- mostrar el aviso, en vez de simplemente fallar en seco.
drop policy if exists "profiles_select_self_always" on public.profiles;
create policy "profiles_select_self_always" on public.profiles
  for select using (id = auth.uid());
