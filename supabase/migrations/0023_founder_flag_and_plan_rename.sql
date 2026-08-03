-- ════════════════════════════════════════════════════════════════
-- 0023 — Bandera de cuenta "Founder" (para mostrar "Plan Hotel -
-- Founder" en pantalla) + renombrar el plan Hotel (sacarle "Uruguay").
--
-- is_founder vive en tenants, no en el código ni en un chequeo de
-- email hardcodeado: así no depende de qué correo tenga la cuenta,
-- y no se puede activar/desactivar desde el panel (no hay política
-- de UPDATE de tenants para el cliente — solo se cambia por SQL
-- directo, a propósito).
-- ════════════════════════════════════════════════════════════════

alter table public.tenants add column if not exists is_founder boolean not null default false;

comment on column public.tenants.is_founder is 'Marca la cuenta fundadora de EYO, para mostrar "<Plan> - Founder" en pantalla. No se expone ninguna forma de cambiarlo desde el panel — solo por SQL directo, por un admin de EYO.';

-- Marca la cuenta founder real (orielesymama@gmail.com) si ya existe.
-- No falla si todavía no existe ese tenant (entornos nuevos/de prueba).
update public.tenants set is_founder = true
where id = (
  select tenant_id from public.profiles where email = 'orielesymama@gmail.com' limit 1
);
