-- ════════════════════════════════════════════════════════════════
-- 0021 — FASE 5 de la corrección de auditoría: dejar rastro cuando
-- se restaura un backup o se migra desde la demo vieja. Hasta ahora
-- cada fila insertada por una restauración ya quedaba en audit_log
-- (por el trigger genérico de cada tabla), pero no había un resumen
-- de "esto vino de una restauración, con este resultado".
--
-- audit_log no tiene política de INSERT para el cliente (a propósito,
-- para que nadie pueda plantar ni borrar historial) — por eso esto es
-- una función security definer bien acotada: solo puede insertar UN
-- tipo de fila (acción 'RESTORE'), siempre con el tenant y el usuario
-- que hace la llamada, nunca datos arbitrarios de otra tabla.
-- ════════════════════════════════════════════════════════════════

create or replace function public.log_restore_event(
  p_module text,
  p_tipo text,
  p_ok int,
  p_fail int,
  p_total int,
  p_referencia text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid;
  v_email text;
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'No se pudo determinar el tenant del usuario actual.';
  end if;
  select email into v_email from public.profiles where id = auth.uid();

  insert into public.audit_log (tenant_id, user_id, user_email, action, table_name, record_id, old_data, new_data)
  values (
    v_tenant,
    auth.uid(),
    v_email,
    'RESTORE',
    p_module,
    null,
    null,
    jsonb_build_object('tipo', p_tipo, 'ok', p_ok, 'fail', p_fail, 'total', p_total, 'referencia', p_referencia)
  );
end;
$$;

comment on function public.log_restore_event is 'Registra en audit_log un resumen de una restauración de backup o migración desde la demo vieja. Solo puede insertar para el propio tenant del usuario que llama.';
