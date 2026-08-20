-- Preflight de SOLO LECTURA de las sesiones de caja existentes. No modifica
-- nada. Necesito esto para saber cuáles son de Modo Propietario antes de
-- tocar la columna "grupo" — no se puede adivinar, ya usaste la Caja
-- compartida desde Modo Propietario al menos una vez.

with t as (
  select tenant_id from public.profiles where email='orielesymama@gmail.com'
)
select jsonb_pretty(jsonb_agg(x order by x->>'apertura' desc)) as sesiones
from (
  select jsonb_build_object(
    'id', cs.id,
    'apertura', cs.apertura,
    'cierre', cs.cierre,
    'abierta', cs.abierta,
    'responsable', cs.responsable,
    'creada_por_email', pr.email,
    'efectivo_inicial', cs.efectivo_inicial,
    'cantidad_movimientos', jsonb_array_length(coalesce(cs.movimientos,'[]'::jsonb)),
    'suma_movimientos', (
      select coalesce(sum((m->>'monto')::numeric),0)
      from jsonb_array_elements(coalesce(cs.movimientos,'[]'::jsonb)) m
    ),
    'movimientos', cs.movimientos,
    'created_at', cs.created_at
  ) as x
  from public.cash_sessions cs
  cross join t
  left join public.profiles pr on pr.id = cs.created_by
  where cs.tenant_id = t.tenant_id
) y;
