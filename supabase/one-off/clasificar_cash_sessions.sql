-- Clasificación puntual por id, revisada a mano contra el resultado del
-- preflight (una sola sesión existente, responsable "Ana", coincide con
-- el ejemplo de empleado del propio pedido — se identifica como la
-- prueba hecha desde Modo Propietario). No es una regla automática.
begin;

update public.cash_sessions
set grupo = 'hostal'
where id = 'c93d3502-ed49-4821-ac60-3ce31fbaabeb';

-- Verificación: debe devolver esa única fila.
select id, grupo, responsable, apertura, cierre, efectivo_inicial
from public.cash_sessions
where id = 'c93d3502-ed49-4821-ac60-3ce31fbaabeb';

commit;
