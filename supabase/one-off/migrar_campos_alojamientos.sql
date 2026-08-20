-- Copia real de campos, APROBADA por el usuario tras revisar la vista
-- previa (preview_migrar_campos_alojamientos.sql): los 6 pares
-- "Habitación X" (alojamiento) / "X" (tipo de habitación) son 1:1, sin
-- ambigüedad, así que se tratan como match seguro. "Habitación Emiliano"
-- no tiene candidato y no se toca.
--
-- Reglas respetadas: solo grupo='hostal', solo completa campos vacíos
-- (coalesce / case ... else valor actual), nunca sobreescribe un valor
-- ya cargado, nunca borra ni modifica room_types/rooms, nunca duplica
-- un alojamiento (es un UPDATE, no un INSERT).
begin;

with t as (
  select tenant_id from public.profiles where email='orielesymama@gmail.com'
),
match as (
  select p.id as prop_id, rt.descripcion, rt.camas, rt.tipo_cama, rt.banio, rt.ac, rt.tv, rt.frigobar
  from public.properties p, t
  join public.room_types rt on rt.tenant_id = t.tenant_id
  where p.tenant_id = t.tenant_id and p.grupo = 'hostal'
    and lower(trim(regexp_replace(p.nombre, '^habitaci[oó]n\s+', '', 'i'))) = lower(trim(rt.nombre))
)
update public.properties p
set
  descripcion = coalesce(p.descripcion, m.descripcion),
  camas       = coalesce(p.camas, m.camas),
  tipo_cama   = coalesce(p.tipo_cama, m.tipo_cama),
  banio       = coalesce(p.banio, m.banio),
  ac          = case when p.ac is false and m.ac is true then true else p.ac end,
  tv          = case when p.tv is false and m.tv is true then true else p.tv end,
  frigobar    = case when p.frigobar is false and m.frigobar is true then true else p.frigobar end
from match m
where p.id = m.prop_id;

-- Verificación: se espera ver 6 filas con datos, y "Habitación Emiliano"
-- con estos campos igual que antes (sin cambios, porque no tuvo match).
with t as (
  select tenant_id from public.profiles where email='orielesymama@gmail.com'
)
select p.nombre, p.descripcion, p.camas, p.tipo_cama, p.banio, p.ac, p.tv, p.frigobar
from public.properties p, t
where p.tenant_id = t.tenant_id and p.grupo = 'hostal'
order by p.nombre;

commit;

-- ── Rollback ──
-- No hay una forma automática de "deshacer" un UPDATE ya confirmado.
-- Si algo sale mal, avisame antes de correr commit — se puede cambiar
-- por "rollback;" al final en vez de "commit;" mientras la sesión del
-- SQL Editor siga abierta y no se haya cerrado la pestaña.
