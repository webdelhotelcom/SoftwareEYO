-- ════════════════════════════════════════════════════════════════
-- 0044 — Arregla el error "record 'new' has no field 'id'" al registrar
-- cualquier movimiento de Caja en Modo Propietario (botón "Registrar" del
-- modal "Movimiento de caja", función registrar_movimiento_caja).
--
-- Causa: public.payment_operations (0033) usa payment_operation_id como
-- primary key, no id. La migración 0033 le agregó el trigger genérico de
-- auditoría (trg_audit_payment_operations → log_audit_event(), definida
-- en 0011), pero log_audit_event() asume que TODA tabla auditada tiene
-- una columna id (coalesce(new.id, old.id)) — falla en tiempo de
-- ejecución (no al aplicar la migración) apenas se intenta el primer
-- insert real en payment_operations.
--
-- Mismo tipo de problema ya resuelto antes en billing_config (0018,
-- ver docs/obsidian/Estado-actual.md): esa tabla también usa otra
-- columna como primary key (tenant_id) y necesitó una columna id
-- "de cortesía" solo para que el trigger genérico funcione. Se aplica
-- acá el mismo arreglo, aditivo y sin tocar la primary key real.
-- ════════════════════════════════════════════════════════════════

alter table public.payment_operations
  add column if not exists id uuid not null default gen_random_uuid();

-- ── Verificación ──
-- select column_name from information_schema.columns
--   where table_name='payment_operations' and column_name='id'; -- 1 fila
-- Después de aplicar, repetir en la app real: Caja (Modo Propietario)
-- → Movimiento → cargar un ingreso cualquiera → Registrar. Debe
-- guardar sin el toast "No se pudo registrar: record 'new' has no
-- field 'id'" y aparecer en "Movimientos del turno".

-- ── Rollback ──
-- alter table public.payment_operations drop column if exists id;
