# Migrar datos de la demo anterior (localStorage) a Supabase

Esto aplica a alguien que ya venía usando `Panel-EYO-Plan-Hotel.html` (o Inicial/Profesional) con datos cargados en el navegador y ahora quiere pasarse a `app/panel.html` (la versión con Supabase).

## Qué módulos se pueden migrar así

Solo los que existían en la demo vieja y tienen su propio botón **"Migrar desde demo anterior"** en el panel nuevo:

| Módulo | Sección del panel |
|---|---|
| Alojamientos | Alojamientos |
| Propietarios | Propietarios |
| Reservas | Reservas (se empareja el alojamiento por **nombre**, ver abajo) |
| Gastos | Gastos (se empareja el alojamiento por **nombre**, ver abajo) |
| Huéspedes | Huéspedes |
| Tareas | Tareas |

Los módulos que no existían en la demo vieja (Housekeeping, Mantenimiento, Caja, Check-in/out, Pre-facturación, Usuarios y Permisos, Auditoría) no tienen ruta de migración porque no hay datos previos que traer — arrancan vacíos en Supabase.

## Paso a paso

1. Abrí la demo anterior (`Panel-EYO-Plan-Hotel.html` o la que corresponda) en el navegador donde tiene los datos cargados.
2. Sidebar → **Exportar backup**. Se descarga un `.json`.
3. Abrí `app/panel.html` (la versión nueva) e iniciá sesión con tu usuario real de Supabase.
4. En la sección del módulo correspondiente → **Migrar desde demo anterior** → elegí el `.json` del paso 2.
5. Confirmá. Cada registro del backup se crea en Supabase, asociado a tu cuenta (tenant).

## Deduplicación (no se puede migrar dos veces el mismo dato)

Si corrés la migración de un módulo dos veces con el mismo archivo (por ejemplo por error, o porque alguien lo hizo sin saber que ya se había hecho antes), el sistema compara contra lo que ya existe en tu cuenta antes de insertar y **salta los que ya están**, en vez de duplicarlos:

| Módulo | Se considera duplicado si coincide... |
|---|---|
| Alojamientos | nombre + dirección |
| Propietarios | email o teléfono |
| Huéspedes | documento o teléfono |
| Tareas | texto de la tarea + fecha límite |
| Reservas | huésped + check-in + check-out + alojamiento (ya emparejado) |
| Gastos | alojamiento (ya emparejado) + fecha + concepto + monto |

El aviso final indica cuántos se migraron, cuántos ya existían (omitidos) y cuántos fallaron — por ejemplo *"Migrados 3, 1 ya existía (omitido)"*. Además queda un registro en **Auditoría** (acción "restauró") con ese mismo resumen, así queda historial de cuándo se hizo cada migración y con qué resultado.

## Qué se migra y qué no

**Alojamientos:** nombre, dirección, capacidad, precio base, comisión %, estado, cuenta bancaria, horarios de check-in/check-out, wifi, acceso, normas, información, contacto, notas y temporadas. **No se migra** el vínculo con Propietarios (`propietarioId` de la demo vieja era un número sin relación con los `id` reales de Supabase) — queda sin propietario asignado, se vincula a mano después.

**Reservas y Gastos:** el alojamiento se empareja por **nombre** (el `propiedadId` numérico de la demo vieja no existe en Supabase). Las reservas/gastos cuyo alojamiento no se encuentre por nombre exacto **se saltean** (el aviso final dice cuántos). El vínculo entre un gasto y su reserva asociada tampoco se migra — no hay forma confiable de emparejar esos IDs numéricos viejos con las reservas ya migradas.

**Tareas:** se migra el texto, categoría, fecha límite y si está hecha o no. El alojamiento asociado no se migra (mismo motivo que arriba).

**Ningún módulo reutiliza los IDs viejos.** Supabase genera un identificador nuevo (UUID) para cada registro migrado.

## Después de migrar

- Confirmá en el panel nuevo que la cantidad de registros y sus datos coinciden con la demo vieja.
- Revisá **Auditoría** para ver el resumen de la migración (módulo, cuántos entraron, cuántos se saltearon).
- No borres la demo vieja: queda como referencia histórica en el repositorio (ver el aviso en `LEEME (2).md`).
