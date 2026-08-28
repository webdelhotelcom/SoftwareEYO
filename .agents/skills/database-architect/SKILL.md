---
name: database-architect
description: Diseñar o revisar el esquema de base de datos de Bestoic (Supabase/Postgres) — tablas nuevas, columnas, migraciones, relaciones, índices. Usar ante pedidos como "agregar una tabla para X", "diseñar el esquema de Y", "esta migración está bien armada?", o cuando un módulo nuevo necesita persistencia.
---

# Arquitectura de base de datos — Bestoic

Postgres vía Supabase, un solo proyecto (`ckbarfwqdnehqnpafzay`, free
tier) compartido por todos los tenants. `supabase/migrations/NNNN_*.sql`
numeradas secuencialmente, nunca se editan las ya aplicadas — todo cambio
es una migración nueva.

## Reglas de diseño de este proyecto

1. **Toda tabla de negocio lleva `tenant_id` + RLS + triggers de
   auditoría** — ver skill `multi-tenant-security` para el molde exacto.
   No crear una tabla "provisoria sin RLS para probar rápido": no existe
   ese modo en este proyecto.
2. **Nunca `default Infinity` ni `null` como "sin límite"** en columnas de
   cupo/límite — un límite mal configurado tiene que *bloquear*, no
   *permitir todo*. Ejemplo real: `client_limits` con 999/999/999 como
   número finito explícito para la cuenta Founder, nunca `Infinity`.
3. **FKs entre tablas de negocio, no strings sueltos** — ejemplo real:
   `reservations.guest_id` se reconectó como FK real a `guests` después de
   vivir como texto libre. Si una relación nueva se parece a esto, usar FK
   desde el día uno.
4. **Datos anidados simples → `jsonb` en la fila padre, no tabla hija.**
   Patrón ya usado en `properties.seasons`, `stays.folio`,
   `cash_sessions.movimientos`: un ledger tipo append/remove sin necesidad
   de RLS independiente va como jsonb. Si en cambio necesita su propia
   política de acceso (ej. alguien puede ver el padre pero no cada línea),
   ahí sí tabla hija con su propio tenant_id+RLS.
5. **Tablas singleton por tenant** (una fila por cliente): igual necesitan
   una columna `id` propia además de `tenant_id`, por el gotcha de los
   triggers genéricos de auditoría (acceso dinámico a `RECORD`, ver skill
   `multi-tenant-security`).
6. **Nombres de columnas en español, snake_case**, consistente con el
   resto del esquema (`fecha_entrada`, `precio_mostrado_lista`, etc. — no
   mezclar inglés/español en la misma tabla).
7. **Migraciones de "cambio de forma" en tablas grandes ya en producción**:
   pensar en `ALTER TABLE ... ADD COLUMN` (nunca DROP+CREATE) para no
   perder datos de clientes reales. Si hace falta backfill, escribirlo en
   la misma migración con un `UPDATE` explícito, no asumir que el default
   alcanza.
8. **CTEs múltiples en un mismo `WITH`, cuidado**: una escritura de una CTE
   no es visible para otra CTE del mismo statement (mismo snapshot). Si un
   trigger necesita ver algo que otra parte de la migración acaba de
   insertar, separar en statements top-level secuenciales.

## Antes de aplicar una migración nueva

- ¿Tiene RLS + las 4 políticas + triggers de auditoría si es tabla de
  negocio? (skill `multi-tenant-security` tiene el checklist completo)
- ¿Agrega permisos nuevos al catálogo si hace falta gating por rol? (skill
  `permissions-review`)
- ¿Rompe algo que ya tenga datos reales? Si sí, avisar antes de aplicar,
  nunca aplicar una migración destructiva sin confirmación explícita.
- Después de aplicar: **redeploy del frontend si el HTML espera columnas
  nuevas** — Netlify no redeploya solo al cambiar Supabase.

## Ejecución manual

`/database-architect` — diseña o revisa una migración/tabla siguiendo
estas convenciones antes de escribir el SQL final.
