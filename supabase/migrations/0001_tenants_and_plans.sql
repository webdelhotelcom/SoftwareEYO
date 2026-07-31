-- ════════════════════════════════════════════════════════════════
-- 0001 — TENANTS, PLAN_CONFIG, CLIENT_LIMITS
-- Correr en el SQL Editor de Supabase, en orden (0001, 0002, 0003, 0004).
-- ════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- TENANTS — un registro por cliente de EYO. Todo el resto de las tablas
-- del sistema cuelga de tenant_id: es la base de la separación entre clientes.
create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  plan text not null check (plan in ('inicial','profesional','hotel')),
  created_at timestamptz not null default now()
);

comment on table public.tenants is 'Un registro por cliente de EYO. Todas las demás tablas cuelgan de tenant_id.';

-- PLAN_CONFIG — catálogo de planes (no es por cliente, es el mismo para todos).
-- max_* en null para 'hotel' significa "no hay default de plan": el límite
-- real de un cliente Hotel se define pieza por pieza en client_limits.
-- Nunca se usa Infinity ni un número gigante como sustituto de "sin límite".
create table public.plan_config (
  plan text primary key,
  label text not null,
  max_properties int,
  max_users int,
  max_rooms int,
  includes_website boolean not null default false,
  includes_google_business boolean not null default false
);

comment on table public.plan_config is 'Límites por defecto de cada plan. max_* en null para hotel = se define por cliente en client_limits, nunca "ilimitado".';

insert into public.plan_config (plan, label, max_properties, max_users, max_rooms, includes_website, includes_google_business) values
  ('inicial',     'Plan Inicial',        5,  1,    0, false, false),
  ('profesional', 'Plan Profesional',   15,  3,    0, true,  true),
  ('hotel',       'Plan Hotel Uruguay', null, null, null, true,  true);

-- CLIENT_LIMITS — override de límites por contrato individual.
-- Para un cliente del plan Hotel es OBLIGATORIO cargar esta fila antes de
-- que pueda usar el sistema (si no existe y el plan tampoco trae default,
-- el trigger de properties bloquea la carga en vez de permitir "infinito").
create table public.client_limits (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  max_properties int,
  max_rooms int,
  max_users int,
  notes text,
  updated_at timestamptz not null default now()
);

comment on table public.client_limits is 'Override de límites por contrato individual, obligatorio para plan hotel.';
