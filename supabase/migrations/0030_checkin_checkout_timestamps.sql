-- ════════════════════════════════════════════════════════════════
-- 0030 — HORA REAL DE CHECK-IN/CHECK-OUT en reservations. Hasta ahora
-- solo existían checkin/checkout como DATE (la fecha planeada de la
-- reserva) — esto agrega el momento REAL en que se registró la
-- llegada/salida, más quién lo hizo.
--
-- checkin_by/checkout_by referencian profiles(id) — confirmado en el
-- preflight que profiles.id = auth.uid() (mismo patrón que created_by/
-- updated_by de otras tablas, que referencian auth.users(id); acá se
-- usa profiles porque es contra esa tabla que resuelve current_tenant_id()
-- y has_permission(), y así se puede hacer join directo a profiles.role
-- si hiciera falta mostrar quién hizo el check-in sin otro join).
-- ════════════════════════════════════════════════════════════════

alter table public.reservations
  add column if not exists checkin_real_at timestamptz,
  add column if not exists checkout_real_at timestamptz,
  add column if not exists checkin_by uuid references public.profiles(id),
  add column if not exists checkout_by uuid references public.profiles(id);

-- ── Verificación ──
-- select column_name from information_schema.columns where table_schema='public'
--   and table_name='reservations' and column_name in
--   ('checkin_real_at','checkout_real_at','checkin_by','checkout_by');
-- Debe devolver 4 filas. Y esto debe seguir dando 816 (nada cambió en las
-- reservas existentes):
-- select count(*) from public.reservations where checkin_real_at is null and checkout_real_at is null;

-- ── Rollback ──
-- alter table public.reservations
--   drop column if exists checkin_real_at, drop column if exists checkout_real_at,
--   drop column if exists checkin_by, drop column if exists checkout_by;
