---
name: multi-tenant-security
description: Verificar o garantizar el aislamiento entre clientes (tenants) de Bestoic — cualquier tabla nueva, endpoint nuevo, o módulo nuevo que guarde datos debe quedar imposible de leer/escribir desde otro tenant. Usar ante pedidos como "agregar una tabla nueva", "un cliente puede ver datos de otro", "probar aislamiento entre cuentas", o después de crear cualquier migración con datos de negocio.
---

# Aislamiento multi-tenant — Bestoic

Bestoic es **un solo proyecto Supabase compartido por todos los
clientes** (nunca un proyecto por cliente) — el aislamiento es 100%
responsabilidad de `tenant_id` + RLS. Un error acá es el peor tipo de
bug posible en este sistema: expone datos de un negocio real a otro.

## El patrón ya establecido (seguirlo, no inventar uno nuevo)

Cada tabla de negocio nueva sigue el mismo molde que ya se usó para las
~19 tablas existentes (properties, owners, reservations, expenses, guests,
tasks, room_types, rooms, stays, hk_tasks, maint_tickets, cash_sessions,
billing_config, facturas, profiles, permissions_catalog,
role_permissions, audit_log, tenant_settings...):

1. Columna `tenant_id uuid not null references tenants(id)`.
2. RLS **habilitada** (`alter table x enable row level security`).
3. 4 políticas (select/insert/update/delete), cada una exigiendo:
   - `tenant_id = current_tenant_id()`, **Y**
   - el permiso puntual vía `has_permission('clave_del_permiso')` (o
     `is_admin()` para lo administrativo), **Y**
   - si aplica, `current_owner_id()` para que un rol `propietario` solo
     vea lo suyo dentro del tenant.
4. Triggers `set_audit_fields` (created_by/updated_by/updated_at) +
   `log_audit_event` (AFTER INSERT/UPDATE/DELETE hacia `audit_log`).
5. Si la tabla es "singleton por tenant" (una fila por cliente, como
   `billing_config`/`tenant_settings`), igual necesita una columna `id`
   propia (aunque `tenant_id` sea la PK real) — los triggers genéricos
   acceden a `NEW.id`/`OLD.id` dinámicamente y revientan si no existe.

## Cómo probar aislamiento de verdad (no alcanza con leer el SQL)

El patrón ya usado en la auditoría de 2026-08-02, repetirlo para cualquier
tabla nueva:

1. Crear un **tenant descartable** + 1-2 usuarios de prueba
   (`supabaseClient.auth.signUp()` sirve directo, sin pasar por el
   dashboard, ya que "Confirm email" está OFF).
2. Con la **anon key** (nunca service_role) y sesión del tenant A, intentar
   leer/insertar/actualizar/borrar filas del tenant B.
3. Confirmar bloqueo mirando **filas afectadas/devueltas, no solo ausencia
   de error** — un UPDATE/DELETE bloqueado por la cláusula `USING` de RLS
   devuelve 0 filas afectadas *sin lanzar error*, así que "no hubo
   excepción" NO es prueba de que funcionó.
4. Limpiar el tenant de prueba al final: **`audit_log` se borra último**
   (los triggers de las demás tablas lo repueblan si se borra antes), y no
   olvidar `role_permissions` (se auto-siembra por tenant vía trigger en
   `tenants`, hay que borrarlo también). Los usuarios de Auth quedan
   huérfanos (no se pueden borrar con la anon key) — no pasa nada, se
   pueden dejar o borrar a mano desde el Dashboard.

## Errores reales que ya pasaron en este proyecto (no repetir)

- RLS que solo miraba `tenant_id` sin exigir el permiso — un empleado sin
  el permiso correcto podía igual editar/borrar. Se probó con un usuario
  real de rol `limpieza`, se confirmó, y se corrigió.
- Una función interna (`sync_market_scan_usage()`, del intento de cuota de
  mercado) invocable directo por cualquier tenant, filtrando el cupo de
  otros clientes — hay que revisar que las funciones `security definer`
  no sean invocables sin control de tenant desde el cliente.
- `role_permissions` y `audit_log` olvidados al limpiar un tenant de
  prueba, dejando basura o rompiendo el `DELETE FROM tenants` por FK.

## Ejecución manual

`/multi-tenant-security` — antes de mergear cualquier tabla/función nueva,
corre el checklist de arriba y, si es viable, arma el test de aislamiento
en vivo con un tenant descartable.
