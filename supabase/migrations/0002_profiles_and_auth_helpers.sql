-- ════════════════════════════════════════════════════════════════
-- 0002 — PROFILES (usuarios) + función current_tenant_id()
-- ════════════════════════════════════════════════════════════════

-- PROFILES — extiende auth.users (que gestiona Supabase Auth) con el dato
-- que a nosotros nos importa: a qué cliente (tenant) pertenece cada usuario
-- y qué rol tiene. auth.users NUNCA guarda la contraseña en texto plano —
-- eso lo maneja Supabase Auth internamente con hash seguro.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id),
  email text,
  role text not null default 'admin' check (role in
    ('admin','gerencia','encargado','recepcion','limpieza','mantenimiento','contador','propietario')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.profiles is 'Un perfil por usuario de auth.users. tenant_id determina a qué cliente pertenece: es la base de todo el aislamiento entre clientes.';

-- Función que resuelve el tenant del usuario actualmente logueado.
-- security definer: puede leer profiles saltando su propia política RLS
-- (si no, se produciría una recursión infinita al evaluar esa política).
-- Solo devuelve el tenant_id del usuario que hace la consulta (auth.uid());
-- no recibe parámetros externos, así que no hay forma de pedir el tenant de otro.
create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select tenant_id from public.profiles where id = auth.uid()
$$;

comment on function public.current_tenant_id() is 'Tenant del usuario logueado actual. La usan todas las políticas RLS del sistema.';
