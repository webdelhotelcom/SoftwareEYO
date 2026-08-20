-- ════════════════════════════════════════════════════════════════
-- 0027 — FORMALIZA LA COLUMNA "grupo" (Modo Propietario / Modo
-- Administrador). Hasta ahora existía en la base real por scripts
-- one-off, sin quedar documentada en ninguna migración versionada.
--
-- Preflight corrido en vivo antes de escribir esto (solo lectura,
-- sobre TODOS los tenants, no solo el de prueba): 0 filas con grupo
-- nulo o con un valor fuera de ('hostal','propiedades') en properties,
-- reservations, expenses, tasks y guests. Por eso esta migración va
-- directo a NOT NULL + CHECK, sin backfill.
--
-- A propósito NO se agrega ningún DEFAULT: cada alta debe declarar su
-- grupo explícitamente. Ya está verificado en el código (propertyToDb,
-- reservationToDb, expenseToDb, taskToDb, guestToDb en app/panel.html)
-- que el frontend siempre envía `grupo: data.grupo||grupoActual()` —
-- así que esto no cambia ningún comportamiento existente, solo agrega
-- una red de seguridad real: si algún día un insert se olvida de
-- mandar el grupo, la base lo rechaza en vez de clasificarlo mal.
-- ════════════════════════════════════════════════════════════════

alter table public.properties   add column if not exists grupo text;
alter table public.reservations add column if not exists grupo text;
alter table public.expenses     add column if not exists grupo text;
alter table public.tasks        add column if not exists grupo text;
alter table public.guests       add column if not exists grupo text;

-- set not null es inofensivo si ya estaba así (algunas de estas tablas
-- ya lo tenían por el script one-off anterior).
alter table public.properties   alter column grupo set not null;
alter table public.reservations alter column grupo set not null;
alter table public.expenses     alter column grupo set not null;
alter table public.tasks        alter column grupo set not null;
alter table public.guests       alter column grupo set not null;

-- Constraints siempre vía bloque DO idempotente: nunca falla si ya
-- existe (a diferencia de "add constraint" a secas), y nunca se toca
-- ni se elimina una constraint que no sea exactamente esta.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'properties_grupo_check') then
    alter table public.properties add constraint properties_grupo_check check (grupo in ('hostal','propiedades'));
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'reservations_grupo_check') then
    alter table public.reservations add constraint reservations_grupo_check check (grupo in ('hostal','propiedades'));
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'expenses_grupo_check') then
    alter table public.expenses add constraint expenses_grupo_check check (grupo in ('hostal','propiedades'));
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tasks_grupo_check') then
    alter table public.tasks add constraint tasks_grupo_check check (grupo in ('hostal','propiedades'));
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'guests_grupo_check') then
    alter table public.guests add constraint guests_grupo_check check (grupo in ('hostal','propiedades'));
  end if;
end $$;

-- ── Verificación (correr después de aplicar) ──
-- select conname, conrelid::regclass from pg_constraint where conname like '%_grupo_check';
-- Debe devolver 5 filas. Y esto debe dar 0 filas en las 5 tablas:
-- select count(*) from public.properties where grupo not in ('hostal','propiedades');

-- ── Rollback (si hiciera falta) ──
-- alter table public.properties   drop constraint if exists properties_grupo_check;
-- alter table public.reservations drop constraint if exists reservations_grupo_check;
-- alter table public.expenses     drop constraint if exists expenses_grupo_check;
-- alter table public.tasks        drop constraint if exists tasks_grupo_check;
-- alter table public.guests       drop constraint if exists guests_grupo_check;
-- (el "not null" no se revierte: no hay filas nulas que proteger, y quitar
--  la restricción no aportaría nada — se deja documentado por si hiciera
--  falta en algún escenario no previsto.)
