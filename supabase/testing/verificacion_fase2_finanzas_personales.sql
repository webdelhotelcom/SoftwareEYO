-- Verificación de Fase 2 (Finanzas personales) antes del ajuste de arquitectura.
-- Todo de solo lectura, seguro de correr en producción. Pegar entero en el
-- editor SQL de Supabase y mandar el resultado completo.

-- 1) Conteo total -- debe dar 146
select count(*) as total_movimientos from finance_transactions;

-- 2) TC -- debe dar count=7, sum=119363.95
select count(*) as pagos_tc, sum(amount) as total_tc from finance_transactions where nature='pago_tc';

-- 2b) Marzo no tiene TC -- debe dar 0 filas
select * from finance_transactions
 where nature='pago_tc' and date>='2026-03-01' and date<'2026-04-01';

-- 2c) Ningún movimiento de categoría "Tarjeta de crédito" quedó mal clasificado -- debe dar 0
select count(*) from finance_transactions t
  join finance_categories c on c.id=t.category_id
 where lower(c.name)='tarjeta de crédito' and t.nature<>'pago_tc';

-- 3) Las 6 transferencias internas -- deben ser exactamente estas 6 fechas/montos
select date, case when direction='salida' then -amount else amount end as monto, nature
from finance_transactions where nature='transferencia_interna' order by date;
-- esperado: 23/02 $15.000, 04/05 $10.272, 01/06 $5.136, 07/07 $10.272, 27/07 $1.990, 05/08 $7.272

-- 4) Cruce mensual completo contra resumen_mensual del JSON original
select date_trunc('month', t.date) as mes,
       sum(amount) filter (where direction='entrada') as entradas_brutas_calculado,
       sum(amount) filter (where direction='entrada' and nature<>'transferencia_interna') as ingresos_reales_calculado,
       sum(amount) filter (where direction='salida' and nature in ('gasto','pago_tc')) as gastos_identificados_calculado,
       sum(case when direction='salida' then -amount else amount end) as resultado_bancario_calculado
from finance_transactions
group by 1 order by 1;
-- comparar cada fila contra entradas_brutas/gastos_identificados/resultado_bancario
-- de resumen_mensual en movimientos_enero_agosto_2026.json, mes por mes

-- 5) Cuenta y categorías
select * from finance_accounts;
-- esperado: 1 fila, Cuenta Compartida, kind='shared'
select count(*) from finance_categories;
-- esperado: 14 sembradas + las creadas automáticamente por el import

-- 6) Nada de lo existente se rompió -- deben seguir devolviendo datos normales
select count(*) from reservations;
select count(*) from expenses;
select count(*) from cash_sessions;
