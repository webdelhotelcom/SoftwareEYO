# Migrar datos de la demo anterior (localStorage) a Supabase

Esto aplica a alguien que ya venía usando `Panel-EYO-Plan-Hotel.html` (o
Inicial/Profesional) con datos cargados en el navegador y ahora quiere
pasarse a `app/panel.html` (la versión con Supabase).

Por ahora esto cubre **Alojamientos**, que es el único módulo ya migrado a
Supabase (Fase 1). Reservas, Gastos, Huéspedes, etc. se migran en la Fase 2;
hasta entonces siguen funcionando en localStorage en ambas versiones, sin
relación entre sí.

## Paso a paso

1. Abrí la demo anterior (`Panel-EYO-Plan-Hotel.html` o la que corresponda) en el navegador donde tiene los datos cargados.
2. Sidebar → **Exportar backup**. Se descarga un `.json` (ej: `panel-alojamientos-backup-2026-07-30.json`).
3. Abrí `app/panel.html` (la versión nueva) e iniciá sesión con tu usuario real de Supabase.
4. Sidebar → sección "Alojamientos (Supabase)" → **Migrar desde demo anterior** → elegí el `.json` del paso 2.
5. Confirmá. Cada alojamiento del backup se crea como uno nuevo en Supabase, asociado a tu cuenta.

## Qué se migra y qué no

Se migran: nombre, dirección, capacidad, precio base, comisión %, estado, cuenta bancaria, horarios de check-in/check-out, wifi, acceso, normas, información, contacto, notas y temporadas.

**No se migra** el vínculo con Propietarios (`propietarioId`): en la demo vieja era un número que solo tenía sentido dentro de ese mismo archivo; en Supabase todavía no existe el módulo de Propietarios (llega en la Fase 2). Los alojamientos migrados quedan sin propietario asignado — se vincula a mano después, o se espera a la Fase 2 para hacerlo en bloque.

**No se reutilizan los IDs viejos.** Supabase genera un identificador nuevo para cada alojamiento migrado. Si en algún momento hay que cruzar datos históricos por ID (por ejemplo reservas viejas que referenciaban el alojamiento "3"), va a hacer falta un mapeo manual — lo vamos a resolver en la Fase 2 cuando Reservas también se migre, no antes.

## Después de migrar

- Confirmá en el panel nuevo que la cantidad de alojamientos y sus datos coinciden con la demo vieja.
- No borres la demo vieja todavía: es el respaldo de referencia hasta que confirmes que todo quedó bien en Supabase (ver la regla del proyecto: no se modifica ni se borra el HTML actual hasta que la versión nueva esté probada y aprobada).
- Una vez confirmado y aprobado, la demo vieja se puede dejar de usar para altas nuevas — pero seguirá existiendo en el repositorio como referencia histórica.
