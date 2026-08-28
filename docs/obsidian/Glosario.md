# Glosario

Ver también: [[00-Indice]]

Términos del proyecto explicados en una línea, para quien no viene del mundo Supabase/Postgres.

- **Tenant** — un cliente de Bestoic. Todas las tablas de negocio cuelgan de un `tenant_id`.
- **RLS (Row Level Security)** — reglas de PostgreSQL que filtran automáticamente qué filas puede leer/escribir cada usuario, según quién esté logueado. Es la base de todo el aislamiento de este sistema — ver [[Seguridad]].
- **Policy (política RLS)** — una regla concreta de RLS sobre una tabla y una operación (select/insert/update/delete). Puede tener una cláusula `USING` (qué filas son visibles/afectables) y `WITH CHECK` (qué valores nuevos se aceptan).
- **`security definer`** — una función de Postgres que se ejecuta con los permisos de quien la creó, no de quien la llama. Se usa para funciones como `current_tenant_id()` que necesitan leer `profiles` saltando su propia RLS, sin abrir esa tabla al cliente.
- **`has_permission(clave)`** — función que resuelve si el usuario logueado tiene un permiso puntual, cruzando su rol con la grilla `role_permissions` de su propio tenant. La usan las políticas de escritura de casi todas las tablas.
- **`is_admin()`** — función más simple que solo mira si el rol del usuario es `admin`. Se usa para operaciones exclusivas de administrador sin pasar por la grilla de permisos.
- **Migración (migration)** — un archivo `.sql` numerado en `supabase/migrations/`, que se corre una sola vez, en orden, y nunca se vuelve a editar en su lógica una vez aplicado en producción (si hace falta corregir algo, se escribe una migración nueva).
- **Backfill** — una migración (o parte de ella) que aplica un cambio a datos que **ya existían** antes de esa migración, para que queden consistentes con el nuevo comportamiento.
- **`on conflict do nothing`** — patrón SQL usado en los backfills de este proyecto para que sean seguros de correr más de una vez: si la fila ya existe, no hace nada (no pisa configuraciones que un admin ya haya tocado a mano).
- **Tenant descartable** — un tenant de prueba creado solo para verificar algo en vivo (por ejemplo, una política RLS nueva), que se borra apenas termina la prueba. Nunca se usa la cuenta real del founder para probar cambios riesgosos.
- **`audit_log`** — tabla que registra automáticamente cada alta/edición/baja de las tablas de negocio, más eventos sintéticos como `RESTORE`. Sin política de escritura directa para el cliente (tamper-proof).
- **CSP (Content-Security-Policy)** — header HTTP que le dice al navegador de qué orígenes puede cargar scripts, estilos, imágenes, etc. Reduce el impacto de un XSS aunque algo se cuele.
- **`esc()`** — función propia de `app/panel.html` que escapa HTML antes de insertar texto libre en `innerHTML`, para evitar XSS.
