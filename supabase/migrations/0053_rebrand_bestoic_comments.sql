-- ════════════════════════════════════════════════════════════════
-- 0053 — Rebranding del producto de software "Software EYO" → "Bestoic".
--
-- Alcance de esta migración: SOLO metadatos de base de datos que
-- mencionan la marca del producto (comentarios `comment on ...` y los
-- 2 mensajes de error que el usuario ve cuando falta configurar un
-- límite de contrato). No hay ningún identificador (tabla/columna/
-- función/policy/trigger) con "eyo" en el nombre -- confirmado por
-- auditoría, nada que renombrar ahí.
--
-- Los comentarios `--` dentro de migraciones YA APLICADAS (0001, 0003,
-- 0038, 0043, 0048, 0049) no se tocan: son texto del archivo .sql, no
-- metadata viva en la base, y este proyecto nunca edita una migración
-- ya aplicada (ver CLAUDE.md). Quedan como registro histórico de que en
-- ese momento el producto se llamaba "Software EYO" -- no tienen ningún
-- efecto funcional ni son visibles para un usuario del panel.
--
-- Todo lo que sea "EYO" como nombre del NEGOCIO HOTELERO real del
-- usuario (categorías financieras históricas, "Hostal EYO", etc.) queda
-- intacto -- es la marca real de su negocio, no la del software.
-- ════════════════════════════════════════════════════════════════

comment on table public.tenants is 'Un registro por cliente de Bestoic. Todas las demás tablas cuelgan de tenant_id.';

comment on table public.tenant_settings is 'Personalización visual por cliente: nombre comercial, colores y logo. Una fila por tenant, valores NULL = usar el default de Bestoic.';

comment on column public.tenants.is_founder is 'Marca la cuenta fundadora de Bestoic, para mostrar "<Plan> - Founder" en pantalla. No se expone ninguna forma de cambiarlo desde el panel — solo por SQL directo, por un admin de Bestoic.';

comment on table public.market_data_sources is 'Catálogo de proveedores de datos de mercado. available=false para Booking/Airbnb hasta que Bestoic tenga credenciales y autorización oficial reales — nunca se marca true sin eso.';

comment on column public.profiles.personal_finance_beta is 'Feature flag de Finanzas personales (beta), por usuario (no por tenant). No se expone ninguna forma de cambiarlo desde el panel -- solo por SQL directo, por un admin de Bestoic. Protegido contra auto-escalada por trg_profiles_protect_privileged.';

-- Mensajes de error visibles para el usuario cuando un cliente no tiene
-- configurado un límite de contrato. Mismo cuerpo/firma/seguridad ya
-- aplicados (security definer, search_path=public tal como ya estaba —
-- no se aprovecha este redeploy para endurecerlo, sería un cambio de
-- comportamiento fuera del alcance de un rebranding de texto), solo
-- cambia el texto del mensaje.
create or replace function public.check_properties_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_plan_max int;
  v_client_max int;
  v_effective int;
  v_count int;
begin
  select plan into v_plan from public.tenants where id = new.tenant_id;
  select max_properties into v_plan_max from public.plan_config where plan = v_plan;
  select max_properties into v_client_max from public.client_limits where tenant_id = new.tenant_id;
  v_effective := coalesce(v_client_max, v_plan_max);

  if v_effective is null then
    raise exception 'Límite de alojamientos no configurado para este cliente. Contactá al administrador de Bestoic.';
  end if;

  select count(*) into v_count from public.properties where tenant_id = new.tenant_id;
  if v_count >= v_effective then
    raise exception 'Alcanzaste el límite de % alojamientos de tu plan.', v_effective;
  end if;

  return new;
end;
$$;

create or replace function public.check_users_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_plan_max int;
  v_client_max int;
  v_effective int;
  v_count int;
begin
  select plan into v_plan from public.tenants where id = new.tenant_id;
  select max_users into v_plan_max from public.plan_config where plan = v_plan;
  select max_users into v_client_max from public.client_limits where tenant_id = new.tenant_id;
  v_effective := coalesce(v_client_max, v_plan_max);

  if v_effective is null then
    raise exception 'Límite de usuarios no configurado para este cliente. Contactá al administrador de Bestoic.';
  end if;

  select count(*) into v_count from public.profiles where tenant_id = new.tenant_id;
  if v_count >= v_effective then
    raise exception 'Alcanzaste el límite de % usuarios de tu plan.', v_effective;
  end if;

  return new;
end;
$$;
