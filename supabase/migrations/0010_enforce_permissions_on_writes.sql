-- ════════════════════════════════════════════════════════════════
-- 0010 — Aplicar los permisos de rol también del lado del servidor
-- en las escrituras más sensibles (Reservas, Gastos). No solo la
-- pantalla esconde el botón: la base de datos también lo exige.
--
-- Alcance de esta pasada: crear/editar reservas y registrar gastos.
-- "Cancelar" una reserva es, técnicamente, una edición más (cambia el
-- campo estado) — el permiso "cancelar_reservas" por ahora solo se usa
-- para mostrar/ocultar esa opción en la pantalla, no hay una regla
-- server-side separada para distinguir "cancelar" de "editar cualquier
-- otro campo". Igual, cualquier edición ya exige "editar_reservas".
-- El borrado (delete) queda reservado a administradores, como ya
-- funcionaba en la pantalla.
-- ════════════════════════════════════════════════════════════════

alter policy "reservations_insert_own_tenant" on public.reservations
  with check (tenant_id = public.current_tenant_id() and public.has_permission('crear_reservas'));

alter policy "reservations_update_own_tenant" on public.reservations
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('editar_reservas'));

alter policy "reservations_delete_own_tenant" on public.reservations
  using (tenant_id = public.current_tenant_id() and public.is_admin());

alter policy "expenses_insert_own_tenant" on public.expenses
  with check (tenant_id = public.current_tenant_id() and public.has_permission('registrar_gastos'));
