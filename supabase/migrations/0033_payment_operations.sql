-- ════════════════════════════════════════════════════════════════
-- 0033 — payment_operations: garantiza unicidad GLOBAL y real (a nivel
-- de motor, con primary key) de cada operación de cobro/anulación de
-- Caja para Modo Propietario. Una búsqueda-y-después-insertar puede
-- perder una condición de carrera entre dos requests simultáneas; un
-- "insert ... on conflict (payment_operation_id) do nothing" no.
--
-- No reemplaza cash_sessions.movimientos (que sigue siendo el detalle/
-- ficha de cada movimiento) — es exclusivamente la garantía de
-- unicidad + el registro de qué anula a qué.
--
-- RLS habilitada SIN políticas para "authenticated": esta tabla solo
-- se lee/escribe desde las funciones security definer de 0034 (que
-- corren con los privilegios del dueño y no pasan por RLS). Cero
-- acceso directo del frontend, ni de lectura ni de escritura.
-- ════════════════════════════════════════════════════════════════

create table if not exists public.payment_operations (
  payment_operation_id uuid primary key,
  tenant_id uuid not null references public.tenants(id),
  reserva_id uuid references public.reservations(id),
  cash_session_id uuid references public.cash_sessions(id),
  tipo text not null check (tipo in (
    'sena','pago-parcial','pago-final','cobro-checkin','cobro-checkout',
    'anulacion','devolucion'
  )),
  importe numeric not null,
  reversa_de uuid references public.payment_operations(payment_operation_id),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);

-- Como mucho UNA anulación por operación original.
create unique index if not exists payment_operations_reversa_unica
  on public.payment_operations (reversa_de) where reversa_de is not null;

create index if not exists idx_payment_operations_reserva
  on public.payment_operations (reserva_id);
create index if not exists idx_payment_operations_tenant
  on public.payment_operations (tenant_id);

alter table public.payment_operations enable row level security;
-- A propósito: ninguna policy para authenticated. Solo las funciones
-- security definer de 0034 tocan esta tabla.

-- Traza en Auditoría, igual que el resto de las tablas financieras
-- (cash_sessions ya tiene el mismo trigger desde 0011/0017).
create trigger trg_audit_payment_operations
  after insert on public.payment_operations
  for each row execute function public.log_audit_event();

-- ── Verificación ──
-- select relrowsecurity from pg_class where relname='payment_operations';  -- debe ser true
-- select count(*) from pg_policies where tablename='payment_operations';  -- debe ser 0
-- select count(*) from public.payment_operations;                        -- debe ser 0 recién creada

-- ── Rollback ──
-- drop table if exists public.payment_operations;
