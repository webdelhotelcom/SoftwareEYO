# Roles y permisos

Cómo funciona el sistema de permisos de Bestoic, y por qué un botón oculto en la pantalla no es, por sí solo, ninguna garantía de seguridad.

## El modelo

- **`permissions_catalog`** — catálogo único de permisos (70 al día de hoy), igual para todos los clientes. Cada uno tiene una clave (`crear_reservas`, `editar_alojamientos`, etc.) y una etiqueta legible. Ver `supabase/migrations/0009_permissions_and_users.sql` (23 permisos originales) y `0019_permissions_enforcement.sql` (47 agregados en la auditoría de seguridad) para el listado completo y actualizado — este documento no repite la lista entera porque se desactualizaría; esos dos archivos SQL son la fuente de verdad.
- **`role_permissions`** — una fila por `tenant_id` + rol + permiso, con un booleano `allowed`. Es **por cliente**: cada admin puede reconfigurar los permisos de sus propios roles desde la página **Usuarios y Permisos**, sin afectar a otros clientes.
- **8 roles fijos:** `admin`, `gerencia`, `encargado`, `recepcion`, `limpieza`, `mantenimiento`, `contador`, `propietario`. Los roles en sí no se crean ni se borran desde el panel — lo que se ajusta es qué permisos tiene cada uno, por cliente.
- **`has_permission(perm_key)`** — función de PostgreSQL (`security definer`) que resuelve si el usuario logueado (`auth.uid()`) tiene ese permiso, cruzando su rol con `role_permissions` de su propio tenant. `admin` no tiene una excepción especial en esta función: su acceso total viene de que casi todas las políticas también aceptan `is_admin()` como alternativa, y de que sus permisos se siembran todos en `true` por defecto.
- **`is_admin()`** — función aparte que solo mira `profiles.role = 'admin'`. Se usa en las operaciones que son exclusivas de admin sin excepción (por ejemplo administrar usuarios, borrar ciertos registros sensibles), independientemente de la grilla de permisos.

## Por qué esto importa: server-side, no solo en pantalla

Hasta la auditoría de seguridad del 2026-08-02, la mayoría de las políticas de escritura (insert/update/delete) en la base de datos solo revisaban `tenant_id = current_tenant_id()` — es decir, "¿es de tu cliente?", pero no "¿tenés permiso para hacer esto?". La interfaz sí escondía los botones según el permiso, pero cualquiera que llamara a la API directamente (con su propio token real, sin necesidad de robar nada) podía saltarse esa restricción. Se comprobó en vivo con un usuario de rol `limpieza` editando y borrando alojamientos por la API — ver `docs/pruebas-aislamiento.md`.

La migración `0019_permissions_enforcement.sql` corrigió esto: reescribió las políticas de insert/update/delete de las 21 tablas para exigir también `has_permission('clave')` (o `is_admin()`), no solo el `tenant_id`. Ejemplo real (alojamientos):

```sql
alter policy "properties_update_own_tenant" on public.properties
  using (tenant_id = public.current_tenant_id())
  with check (tenant_id = public.current_tenant_id() and public.has_permission('editar_alojamientos'));
```

Esto significa: aunque alguien modifique el JavaScript del navegador para mostrar un botón oculto, el `update` va a llegar a la base de datos igual — y la base de datos lo va a rechazar si el usuario no tiene ese permiso. La UI y la base de datos aplican la misma regla, pero de forma independiente.

## Cómo lo usa el frontend

`app/panel.html` tiene una función `can(key)` que refleja del lado del cliente los mismos permisos que `has_permission()` resuelve del lado del servidor (más una excepción explícita: `admin` siempre da `true` en `can()`, igual que en la base). Se usa para:

- Mostrar/ocultar botones de crear, editar, borrar en cada módulo.
- Habilitar o no ciertas páginas del menú lateral.

**Importante:** `can()` es una comodidad de interfaz, no la fuente de la seguridad. Si algún día `can()` y `has_permission()` quedan desalineados (por ejemplo, se agrega un botón nuevo en el frontend sin la política RLS correspondiente), el peor caso posible es que la base de datos rechace una acción que la UI permitía intentar — nunca al revés. Por eso cualquier función de escritura nueva en el panel necesita su política RLS correspondiente desde el primer commit, no como un paso posterior.

## Permisos "propietario": alcance limitado a lo propio

El rol `propietario` tiene, además, un alcance restringido por dueño: `profiles.owner_id` conecta el usuario con su fila en `owners`, y `current_owner_id()` hace que las políticas de `properties` y `reservations` solo le muestren lo que le pertenece a él (agregado también en `0019`). Es una capa aparte del sistema de permisos por rol: un `propietario` puede tener el permiso `ver_reportes`, pero solo va a ver los reportes de sus propios alojamientos, nunca los de otro propietario del mismo cliente.

## Usuarios desactivados

Desactivar un usuario (`profiles.active=false`, desde Usuarios y Permisos) le revoca el acceso de inmediato a nivel de base de datos — no solo le bloquea el próximo login. `current_tenant_id()`, `has_permission()` y `current_owner_id()` exigen `active=true` en cada llamada (migración `0020_deactivated_user_lockout.sql`), así que una sesión ya abierta deja de poder leer o escribir nada apenas se lo desactiva, aunque no haya vuelto a iniciar sesión. El panel además revisa cada 60 segundos si el usuario logueado sigue activo y cierra la sesión automáticamente si no.

## Cómo reconfigurar permisos de un cliente

Desde el panel, como `admin`: **Usuarios y Permisos → Permisos** → tildar/destildar la grilla rol × permiso → guardar. Los cambios son inmediatos y solo afectan al tenant del admin que los hace (RLS de `role_permissions` lo garantiza: cada admin únicamente puede leer y escribir las filas de su propio `tenant_id`).

Si hace falta un permiso que todavía no existe en el catálogo, hay que agregarlo por SQL (nueva fila en `permissions_catalog` + la política RLS correspondiente en la tabla que protege) — no es algo que se pueda dar de alta desde el panel, a propósito: cada permiso nuevo necesita una política RLS escrita a mano para que sirva de algo.
