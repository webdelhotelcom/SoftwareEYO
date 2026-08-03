# Módulos

Ver también: [[00-Indice]] · [[Arquitectura]]

Los 20 módulos de negocio de `app/panel.html`, todos sobre Supabase (ninguno en `localStorage`), con la migración SQL donde nació cada uno. Migrados en el orden de esta tabla — cada uno siguió el mismo patrón: tabla + `tenant_id` + RLS (4 políticas) + triggers de auditoría → CRUD async en el frontend → botones de export/import backup → prueba en vivo → deploy.

| Módulo | Migración | Notas |
|---|---|---|
| Alojamientos | `0004_properties_module` | Primer módulo migrado (Fase 1 del proyecto original). |
| Propietarios | `0005_owners_module` | Conecta con `properties.propietario_id` por FK. |
| Reservas | `0006_reservations_module` | |
| Gastos | `0007_expenses_module` | |
| Huéspedes | `0008_guests_module` | Reconecta `reservations.guest_id` como FK real. |
| Usuarios y Permisos | `0009_permissions_and_users` | Catálogo de 23 permisos originales + grilla por rol. Ampliado a 70 permisos en `0019` (auditoría). |
| Auditoría | `0011_audit_log` | Trigger genérico en las tablas de negocio; sin política de insert directo (tamper-proof). |
| Tareas | `0012_tasks_module` | Último módulo de la Fase 2 original. |
| Tipos de habitación + Habitaciones | `0013_rooms_module` | Primer módulo hotelero (Fase 3). |
| Check-in/out (estadías) | `0014_stays_module` | Folio de cargos/pagos como `jsonb` en la fila (mismo patrón que `properties.seasons`). |
| Housekeeping | `0015_housekeeping_module` | |
| Mantenimiento | `0016_maintenance_module` | |
| Caja y turnos | `0017_cashbox_module` | Distingue turno abierto/cerrado en la política de update. |
| Pre-facturación | `0018_billing_module` | No emite comprobante con validez fiscal DGI por sí solo — ver `terminos.html`. |
| Calendario hotelero | *(sin migración propia)* | Lee `rooms`/`stays`/`reservations`, ya migrados — no necesitó cambios de esquema. |
| Reportes hoteleros | *(sin migración propia)* | Mismo motivo. |
| Dashboard | *(sin migración propia)* | Agrega datos de varios módulos ya migrados. |
| Resumen Mensual | *(sin migración propia)* | Ídem. |
| WhatsApp / Mensajes | *(sin migración propia)* | Genera texto a partir de datos ya migrados; no persiste nada propio. |
| Recepción | *(sin migración propia)* | Vista operativa sobre `stays`/`rooms`. |
| Inteligencia de Precios (beta) | `0025_pricing_intelligence_phase1`, `0026_pricing_view_permission_fix` | Solo Plan Hotel, por feature flag. Fase 1 de un desarrollo por etapas — ver [[Inteligencia-de-Precios]]. |

## Correcciones posteriores (no son módulos nuevos)

- `0010_enforce_permissions_on_writes` — primer intento de exigir permisos server-side (solo Reservas/Gastos). Superado por `0019`.
- `0019_permissions_enforcement`, `0020_deactivated_user_lockout`, `0021_restore_audit_trail`, `0022_fix_propietario_editar_gastos` — correcciones de la auditoría de seguridad del 2026-08-02. Ver [[Seguridad]] e [[Historia-y-decisiones]].

## Lo único que sigue sin migrar

Nada de negocio. La demo original (`Panel-EYO-Plan-*.html`) sigue existiendo en el repo como referencia histórica — no es un módulo pendiente, es intencional (ver la regla del proyecto en [[Historia-y-decisiones]]: no se borra la demo vieja).
