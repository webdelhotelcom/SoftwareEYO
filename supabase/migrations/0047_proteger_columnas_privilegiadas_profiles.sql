-- =============================================================================
-- 0047 — Cierra una escalada de privilegios en profiles (hallazgo de auditoría)
-- =============================================================================
--
-- EL PROBLEMA
-- La política de 0003:
--
--   create policy "profiles_update_self" on public.profiles
--     for update using (id = auth.uid())
--     with check (id = auth.uid() and tenant_id = public.current_tenant_id());
--
-- deja que cada usuario edite SU PROPIA fila. En PostgreSQL una política RLS
-- autoriza la FILA, no las COLUMNAS: mientras el id y el tenant_id no cambien,
-- la política acepta el UPDATE sin importar qué otra columna se toque.
--
-- Como en esa misma fila viven `role` y `active`, cualquier usuario logueado
-- (por ejemplo uno con rol 'limpieza') podía llamar directo a la API REST:
--
--   PATCH /rest/v1/profiles?id=eq.<su_propio_uid>
--   { "role": "admin" }
--
-- y convertirse en administrador de su cliente. Desde ahí heredaba todos los
-- permisos del tenant: ver y borrar reservas, gastos, huéspedes, auditoría, y
-- administrar a los demás usuarios. La UI nunca ofrece ese botón, pero la UI
-- no es una defensa: la petición se puede armar a mano con la clave anon, que
-- es pública por diseño.
--
-- Lo mismo aplicaba a `owner_id`: un usuario con rol 'propietario' podía
-- apuntarse a otro propietario del mismo tenant y pasar a ver la facturación
-- y las reservas de ese otro propietario.
--
-- LA SOLUCIÓN
-- Un trigger BEFORE UPDATE que congela las columnas con privilegio salvo que
-- quien hace el cambio sea admin del mismo tenant (el flujo legítimo del
-- módulo "Usuarios y permisos", que hace update({role, active})).
--
-- No se toca la política RLS: se mantiene, porque el update de la propia fila
-- SÍ es legítimo para las columnas sin privilegio. Hoy la app solo escribe
-- `last_active_at` sobre la fila propia, y eso sigue funcionando igual.
--
-- Por qué un trigger y no una política: en una política RLS, `using` ve la
-- fila vieja y `with check` la nueva, pero no se pueden comparar entre sí.
-- Detectar "esta columna cambió" requiere ver OLD y NEW a la vez, y eso solo
-- se puede en un trigger.
-- =============================================================================

create or replace function public.protect_profile_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
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
  'Impide que un usuario se cambie a sí mismo el rol, el estado activo, el tenant o el propietario asociado. Solo un admin del mismo tenant puede modificar esas columnas.';

drop trigger if exists trg_profiles_protect_privileged on public.profiles;
create trigger trg_profiles_protect_privileged
  before update on public.profiles
  for each row execute function public.protect_profile_privileged_columns();
