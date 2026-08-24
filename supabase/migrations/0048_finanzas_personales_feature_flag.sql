-- ════════════════════════════════════════════════════════════════
-- 0048 — Finanzas personales (Fase 1): feature flag por usuario.
--
-- Fase 1 = solo base de datos + feature flag + navegación (placeholders
-- sin datos). El esquema completo de cuentas/movimientos/transferencias/
-- ahorro/presupuesto/importación se diseña recién en la Fase 2, cuando
-- se construya Cuenta Compartida de verdad — no se congela ahora para
-- no comprometer decisiones que todavía pueden cambiar.
--
-- POR QUÉ EN "profiles" Y NO EN "tenants":
-- El pedido original fue: visible solo para orielesymama@gmail.com, para
-- ningún otro usuario. Un flag en tenants (como is_founder, 0023) protege
-- por CLIENTE, no por usuario — si ese tenant llegara a tener un segundo
-- usuario (otro admin, un socio), también vería el módulo. profiles ya es
-- 1 fila por usuario (id = auth.uid()), así que ahí sí se garantiza
-- exactamente el aislamiento pedido.
--
-- POR QUÉ HACE FALTA TOCAR EL TRIGGER DE 0047:
-- A diferencia de tenants (sin política de UPDATE para el cliente),
-- profiles SÍ tiene "profiles_update_self" (0003), que deja a cada
-- usuario editar su propia fila. Es el mismo problema de fondo que 0047
-- cerró para role/active/tenant_id/owner_id: sin protección, cualquier
-- usuario podría auto-otorgarse la beta con un PATCH directo a la REST
-- API (PATCH /rest/v1/profiles?id=eq.<su_uid> {"personal_finance_beta":true}).
-- Se extiende esa misma función/trigger para bloquear también esta
-- columna — a diferencia de role/active (que un admin sí administra
-- legítimamente desde "Usuarios y permisos"), acá no existe ningún
-- flujo de UI que deba poder cambiarla, así que el chequeo va ANTES del
-- bypass de is_admin(): ni siquiera un admin del tenant puede tocarla
-- desde la app. Se habilita solo por SQL directo de un admin de EYO.
-- ════════════════════════════════════════════════════════════════

alter table public.profiles add column if not exists personal_finance_beta boolean not null default false;

comment on column public.profiles.personal_finance_beta is 'Feature flag de Finanzas personales (beta), por usuario (no por tenant). No se expone ninguna forma de cambiarlo desde el panel -- solo por SQL directo, por un admin de EYO. Protegido contra auto-escalada por trg_profiles_protect_privileged.';

update public.profiles set personal_finance_beta = true
where email = 'orielesymama@gmail.com';

create or replace function public.protect_profile_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sin excepción para nadie, ni siquiera admin: no hay ningún flujo de
  -- UI legítimo que cambie esta columna.
  if new.personal_finance_beta is distinct from old.personal_finance_beta then
    raise exception 'personal_finance_beta no se puede cambiar desde la aplicación.'
      using errcode = '42501';
  end if;

  -- Camino legítimo: un admin activo del mismo tenant administrando usuarios.
  -- is_admin() hace su propio SELECT sobre profiles y, al ser un trigger
  -- BEFORE, todavía lee el estado ANTERIOR de la fila — así que un usuario
  -- que justo esté intentando ascenderse a 'admin' no puede aprobarse solo.
  if public.is_admin() and new.tenant_id = public.current_tenant_id() then
    return new;
  end if;

  if new.role is distinct from old.role then
    raise exception 'No tenés permiso para cambiar el rol de un usuario.'
      using errcode = '42501';
  end if;

  if new.active is distinct from old.active then
    raise exception 'No tenés permiso para activar o desactivar un usuario.'
      using errcode = '42501';
  end if;

  if new.tenant_id is distinct from old.tenant_id then
    raise exception 'No tenés permiso para mover un usuario de cliente.'
      using errcode = '42501';
  end if;

  if new.owner_id is distinct from old.owner_id then
    raise exception 'No tenés permiso para cambiar el propietario asociado.'
      using errcode = '42501';
  end if;

  if new.id is distinct from old.id then
    raise exception 'El identificador de un perfil no se puede cambiar.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function public.protect_profile_privileged_columns() is
  'Impide que un usuario se cambie a sí mismo el rol, el estado activo, el tenant, el propietario asociado o el flag de beta de Finanzas personales. Solo un admin del mismo tenant puede modificar role/active/tenant_id/owner_id; personal_finance_beta queda bloqueado para todos los caminos del cliente, sin excepción -- solo se cambia por SQL directo.';

-- El trigger ya existe (creado en 0047) y apunta a esta misma función por
-- nombre — no hace falta recrearlo, create or replace function ya deja
-- la nueva lógica activa para el trigger existente.

-- ── Verificación (solo lectura, segura de correr en producción) ──
-- select email, personal_finance_beta from public.profiles where personal_finance_beta = true;
--   -> debe devolver solo orielesymama@gmail.com

-- ── Prueba de comportamiento (SOLO en local/staging) ──
-- 1) Logueado como un usuario cualquiera que no sea orielesymama@gmail.com:
--    update profiles set personal_finance_beta = true where id = auth.uid();
--    -> debe fallar con "personal_finance_beta no se puede cambiar desde la aplicación."
-- 2) Repetir logueado como admin del tenant, apuntando a la fila de otro
--    usuario de ese mismo tenant -> debe fallar igual (el chequeo va antes
--    del bypass de is_admin()).
-- 3) select personal_finance_beta from profiles where id = auth.uid(); logueado
--    como orielesymama@gmail.com -> true.

-- ── Rollback ──
-- update public.profiles set personal_finance_beta = false;
-- alter table public.profiles drop column if exists personal_finance_beta;
-- (y recrear protect_profile_privileged_columns() con el cuerpo de 0047, sin
-- el chequeo de personal_finance_beta)
