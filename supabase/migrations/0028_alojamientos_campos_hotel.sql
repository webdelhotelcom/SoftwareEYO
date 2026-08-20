-- ════════════════════════════════════════════════════════════════
-- 0028 — ALOJAMIENTOS: campos que hoy solo existen en room_types
-- (Modo Administrador), para que Alojamientos sea la fuente única
-- en Modo Propietario. Aditiva: todas nullable o con default neutro,
-- cero impacto en las filas existentes (incluidas las 6 de room_types
-- y 6 de rooms, que esta migración no toca en absoluto).
-- ════════════════════════════════════════════════════════════════

alter table public.properties
  add column if not exists categoria text,
  add column if not exists descripcion text,
  add column if not exists camas int,
  add column if not exists tipo_cama text,
  add column if not exists banio text,
  add column if not exists piso text,
  add column if not exists ac boolean not null default false,
  add column if not exists tv boolean not null default false,
  add column if not exists frigobar boolean not null default false,
  add column if not exists cocina boolean not null default false,
  add column if not exists estacionamiento boolean not null default false,
  add column if not exists comodidades text;

-- ── Verificación ──
-- select column_name from information_schema.columns
-- where table_schema='public' and table_name='properties'
--   and column_name in ('categoria','descripcion','camas','tipo_cama','banio','piso',
--                        'ac','tv','frigobar','cocina','estacionamiento','comodidades');
-- Debe devolver 12 filas.

-- ── Rollback ──
-- alter table public.properties
--   drop column if exists categoria, drop column if exists descripcion,
--   drop column if exists camas, drop column if exists tipo_cama,
--   drop column if exists banio, drop column if exists piso,
--   drop column if exists ac, drop column if exists tv,
--   drop column if exists frigobar, drop column if exists cocina,
--   drop column if exists estacionamiento, drop column if exists comodidades;
