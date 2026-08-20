# Personalización por cuenta

Ver también: [[00-Indice]] · [[Arquitectura]] · [[Seguridad]] · [[Estado-actual]] · [[Centro-de-Configuracion]]

Agregado el 2026-08-02: cada cliente puede personalizar el nombre comercial, dos colores y un logo propio, sin tocar código. Esta nota documenta la decisión técnica, la estructura de datos, el almacenamiento y la seguridad — el detalle de uso normal (cómo cambiarlo desde el panel) no hace falta documentarlo acá, es autoexplicativo en la página de Ajustes.

> **Actualización 2026-08-18 (Fase 3 — ver [[Centro-de-Configuracion]]):** los selectores de **color** (principal y de menú lateral) se **retiraron de la interfaz** — Ajustes → General quedó solo con nombre comercial y logo. El motivo: el nuevo sistema de modo oscuro/claro/sistema (por usuario) necesitaba que el acento de marca y el fondo de la app no compitieran por la misma variable CSS sin control. `sidebar_color` dejó de aplicarse por completo (el menú lateral siempre sigue el fondo del tema activo). Un `primary_color` guardado de una configuración vieja **sigue aplicándose como acento** si pasa un chequeo de contraste contra sus usos reales (texto de botón, link, badge) para el tema activo — si no pasa, se usa el acento por defecto del tema en su lugar, sin tocar el valor guardado en Supabase. El resto de esta nota (estructura de datos, storage del logo, RLS) sigue vigente tal cual — la tabla `tenant_settings` no cambió de forma, `primary_color`/`sidebar_color` solo dejaron de ser editables desde la UI.

## Decisión técnica

Clasificación: **A. Factible y liviana**, para las tres piezas (nombre comercial, colores, logo).

- **Nombre comercial y colores**: texto y códigos HEX, un puñado de bytes por cliente. Ninguna preocupación de espacio ni rendimiento — es una fila más en una tabla que ya vive en el mismo proyecto Supabase Free.
- **Logo**: la pieza que había que evaluar en serio. Con un tope duro de 300 KB por archivo, un solo logo activo por cliente (se reemplaza, no se acumula) y compresión automática a WebP:
  - 100 clientes × 300 KB ≈ 30 MB
  - 1.000 clientes × 300 KB ≈ 300 MB
  - El plan Free de Supabase Storage da 1 GB — para llegar a ese límite con logos de 300 KB harían falta más de 3.000 clientes activos con logo subido. Muy por encima de cualquier escala realista para este proyecto en el corto/mediano plazo.
  - Conclusión: el logo también es factible sin costo, usando el mismo proyecto Supabase que ya se usa para todo lo demás — no se contrató ni se necesitó ningún servicio nuevo.

## Simplificación consciente frente al pedido original

El pedido original mencionaba hasta 5 colores personalizables (principal, secundario, de botones, de acento, de menú lateral). Revisando el CSS real de `app/panel.html`, el sistema de diseño actual solo tiene **una** variable de acento (`--accent`, con `--accent2` como su tono de hover derivado automáticamente) que maneja botones, estados activos y insignias — no existen 4-5 "ranuras" de color independientes y con sentido visual propio. Ofrecer 5 selectores que en su mayoría terminarían pisando la misma variable habría sido una interfaz confusa sin beneficio real.

Se implementaron **2 colores** con significado real y distinto en la interfaz:
- **Color principal** → `--accent` / `--accent2` (botones, acentos, estados activos).
- **Color del menú lateral** → nueva variable `--sidebar-bg` (antes la barra lateral usaba directamente `var(--bg)`, blanco fijo).

Esta reducción está documentada acá a propósito, para que quede claro que fue una decisión deliberada ("no generar una solución pesada ni innecesaria", como pedía el encargo original) y no un recorte por descuido.

## Estructura de base de datos

Migración `0024_tenant_settings_personalizacion.sql`.

```
tenant_settings
  tenant_id     uuid PK, FK -> tenants(id)
  business_name text        (máx. 60 caracteres, sin < ni >)
  logo_path     text        (ruta dentro del bucket, o NULL)
  primary_color text        (HEX validado por constraint, o NULL)
  sidebar_color text        (HEX validado por constraint, o NULL)
  updated_at    timestamptz
  updated_by    uuid FK -> auth.users(id)
```

Una fila por tenant. Todos los campos en NULL = usar el diseño original de Software EYO (ese es el estado por default y también el resultado de "Restaurar diseño original" — nunca se borra la fila, se limpian sus columnas).

## Almacenamiento del logo

Bucket de Supabase Storage `tenant-logos`, **privado** (`public: false`), con tope de archivo de 300 KB y tipos MIME permitidos limitados a PNG/JPEG/WebP a nivel del propio bucket (además de la validación en el navegador).

Ruta fija por tenant: `tenant-logos/{tenant_id}/logo.webp`. Como la ruta es siempre la misma, subir un logo nuevo (`upsert:true`) reemplaza al anterior automáticamente — no hace falta borrar el archivo viejo a mano, y nunca se acumulan versiones.

Antes de subir, el navegador:
1. Revisa que el tipo declarado del archivo sea PNG/JPEG/WebP.
2. Lee los primeros bytes del archivo y compara contra la firma real de cada formato (evita que un archivo renombrado con otra extensión pase el primer filtro) — probado en vivo con un `.txt` renombrado a `.png`.
3. Redimensiona a un máximo de 512×512 manteniendo proporción, y comprime a WebP bajando la calidad en pasos hasta entrar en 300 KB (o rechaza el archivo con un mensaje claro si ni así entra).

## Seguridad (RLS)

- `tenant_settings`: cualquier usuario logueado del tenant puede leer (es apariencia, se aplica igual para todos los roles); **solo un admin** puede insertar/actualizar. Reforzado también en la interfaz: un usuario sin rol admin ve el formulario pero con todos los controles deshabilitados.
- `storage.objects` (bucket `tenant-logos`): política de SELECT/INSERT/UPDATE/DELETE que exige `(storage.foldername(name))[1] = current_tenant_id()::text`, y las de escritura exigen además `is_admin()`. Un tenant no puede leer, listar ni escribir el logo de otro, ni por la API ni por URL directa (el bucket no es público).
- Probado en vivo con 2 tenants descartables: el tenant B recibió una carpeta vacía al listar el logo del tenant A, y una descarga directa sin caché del navegador devolvió 404 "Object not found" (RLS no revela ni la existencia del archivo). Un primer intento de esta misma prueba dio un falso positivo por **caché HTTP del navegador** (el logo ya se había pedido en esa misma pestaña bajo otra sesión) — quedó anotado como aprendizaje: al probar aislamiento de Storage entre tenants, usar `list()` o un `fetch` con `cache:'no-store'`, nunca `.download()` reciclando una pestaña que ya pidió el mismo archivo antes.

## Aplicación en pantalla

`applyTenantBranding()` en `app/panel.html` se llama después de cada login (y se limpia en cada logout, para que no quede pegada la personalización de una cuenta en la sesión de otra en el mismo navegador). Aplica los colores como variables CSS en `:root` (`--accent`, `--accent2` derivado más oscuro, `--sidebar-bg`), y el logo como imagen de fondo de los íconos de marca — descargado vía el cliente autenticado de Supabase (respeta RLS), no por URL pública.

## Archivos modificados

- `supabase/migrations/0024_tenant_settings_personalizacion.sql` (nuevo)
- `app/panel.html`: sección "Personalización" en Ajustes, funciones `applyTenantBranding()`, `applyTenantLogoImage()`, `savePersonalizacion()`, `restorePersonalizacion()`, `resizeAndCompressImage()`, `fileMatchesRealType()`, validaciones de contraste (`contrastRatio()`/`relLuminance()`).
