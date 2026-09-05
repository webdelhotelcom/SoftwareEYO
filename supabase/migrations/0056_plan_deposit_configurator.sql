-- ════════════════════════════════════════════════════════════════
-- 0056 — Ajustes de plan_deposit_payments para el configurador
-- "Arma tu Bestoic": (1) renombra la key de plan 'inicial' -> 'emprendedor'
-- (2) agrega selected_modules, para que el founder sepa qué módulos
-- eligió el cliente al crear la cuenta a mano -- nunca afecta el precio
-- ni pasa por ninguna validación de servidor distinta a la que ya existe.
--
-- 0055 nunca se edita (regla del proyecto: no tocar una migración ya
-- aplicada) -- esto es una migración nueva que altera el constraint y
-- agrega la columna.
-- ════════════════════════════════════════════════════════════════

-- No se asume que la tabla está vacía: si ya hay filas reales con
-- plan='inicial' (pagos de prueba u órdenes reales ya creadas), se
-- renombran antes de aplicar el constraint nuevo -- si no hiciera esto
-- primero, el ALTER de abajo fallaría contra esas filas.
update public.plan_deposit_payments set plan = 'emprendedor' where plan = 'inicial';

alter table public.plan_deposit_payments drop constraint plan_deposit_payments_plan_check;
alter table public.plan_deposit_payments add constraint plan_deposit_payments_plan_check
  check (plan in ('emprendedor','profesional'));

-- Informativa únicamente -- la lista de module keys que el cliente
-- eligió en el configurador, para que el founder sepa qué configurar al
-- crear la cuenta a mano. Nunca se usa para calcular ningún precio (el
-- backend siempre cobra el precio fijo del plan, ver mp-plan-order.js).
alter table public.plan_deposit_payments add column selected_modules jsonb;

comment on column public.plan_deposit_payments.selected_modules is
  'Lista informativa de module keys elegidos en el configurador (armá tu Bestoic). Nunca afecta el precio cobrado -- eso siempre es el precio fijo del plan, recalculado server-side en mp-plan-order.js.';

-- ── Verificación ──
-- select distinct plan from public.plan_deposit_payments; -- solo 'emprendedor'/'profesional', nunca 'inicial'
-- select column_name from information_schema.columns where table_name='plan_deposit_payments' and column_name='selected_modules';
