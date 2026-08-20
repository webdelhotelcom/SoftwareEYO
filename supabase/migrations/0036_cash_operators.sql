-- ════════════════════════════════════════════════════════════════
-- 0036 — CASH_OPERATORS: empleados de Caja (solo Modo Propietario).
-- Datos visibles y secreto SEPARADOS EN DOS TABLAS a propósito: RLS es
-- por fila, no por columna. Si "authenticated" tuviera SELECT sobre una
-- tabla con pin_hash, un cliente manual podría pedir esa columna igual
-- (un "select id,nombre" en el frontend no es una protección real). La
-- única forma de que el navegador nunca reciba el hash es que viva en
-- una tabla sin NINGUNA policy de select para authenticated.
-- ════════════════════════════════════════════════════════════════

insert into public.permissions_catalog (key,label,sort_order) values
  ('administrar_operadores_caja','Administrar operadores de Caja (Modo Propietario)',77)
on conflict (key) do nothing;

-- Backfill para tenants que ya existen (los futuros lo reciben solos vía
-- seed_default_role_permissions(), que ya hace cross join con
-- permissions_catalog completo — admin/gerencia son reglas "todo menos X",
-- así que ya van a incluir esta clave nueva sin tocar esa función).
insert into public.role_permissions (tenant_id, role, permission_key, allowed)
select t.id, r.role, 'administrar_operadores_caja',
  case when r.role in ('admin','gerencia') then true else false end
from public.tenants t
cross join (values ('admin'),('gerencia'),('encargado'),('recepcion'),('limpieza'),('mantenimiento'),('contador'),('propietario')) as r(role)
on conflict (tenant_id, role, permission_key) do nothing;

create table public.cash_operators (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  nombre text not null,
  activo boolean not null default true,
  notas text,
  intentos_fallidos int not null default 0,
  bloqueado_hasta timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  last_used_at timestamptz
);
create index idx_cash_operators_tenant on public.cash_operators(tenant_id);
alter table public.cash_operators enable row level security;

create policy "cash_operators_select_own_tenant" on public.cash_operators
  for select using (tenant_id = public.current_tenant_id());
-- A propósito SIN policy de insert/update/delete para "authenticated":
-- alta, activar/desactivar y cambio de PIN quedan EXCLUSIVAMENTE detrás
-- de las RPC security definer de 0040 (que sí escriben auditoría). Un
-- update directo del navegador contra esta tabla, aunque el usuario
-- tenga el permiso, no matchea ninguna policy y queda rechazado por RLS.
-- Tampoco hay DELETE nunca: un operador es parte del historial
-- financiero, se desactiva (activo=false), no desaparece.

create trigger trg_cash_operators_insert_audit before insert on public.cash_operators for each row execute function public.set_audit_fields();
create trigger trg_cash_operators_update_audit before update on public.cash_operators for each row execute function public.set_audit_fields();
-- Sin trigger de log_audit_event(): esa función copia la fila COMPLETA a
-- old_data/new_data — como cash_operators nunca tiene el pin_hash (vive
-- en la tabla de abajo) esto ya sería seguro en teoría, pero además cada
-- RPC de 0040 escribe a mano una fila de cash_audit_log con acciones
-- explícitas ('operador_creado','operador_desactivado', etc.), que es
-- justo el formato campo/motivo que pidió el usuario — el genérico no
-- aporta nada acá y se evita por completo.

-- Tabla privada del secreto. RLS habilitada, CERO policies: nadie con rol
-- "authenticated" puede leer ni escribir esto directo, ni con select *,
-- ni sabiendo el nombre exacto de la columna. Solo las funciones
-- security definer de 0040 (que corren como dueño) la tocan.
create table public.cash_operator_secrets (
  operator_id uuid primary key references public.cash_operators(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id),
  pin_hash text not null
);
alter table public.cash_operator_secrets enable row level security;

-- ── Verificación ──
-- select count(*) from pg_policies where tablename='cash_operator_secrets'; -- debe ser 0
-- select count(*) from pg_policies where tablename='cash_operators'; -- debe ser 1 (solo select)
-- select key from permissions_catalog where key='administrar_operadores_caja'; -- 1 fila

-- ── Rollback ──
-- drop table if exists public.cash_operator_secrets;
-- drop table if exists public.cash_operators;
-- delete from public.role_permissions where permission_key='administrar_operadores_caja';
-- delete from public.permissions_catalog where key='administrar_operadores_caja';
