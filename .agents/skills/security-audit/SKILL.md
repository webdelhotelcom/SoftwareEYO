---
name: security-audit
description: Auditoría de seguridad COMPLETA de Bestoic (no solo el diff pendiente) — RLS, exposición de service_role, XSS, aislamiento multi-tenant, CSP, autenticación. Usar ante pedidos como "auditoría de seguridad", "revisá la seguridad de la app", "¿esto es seguro para clientes reales?", antes de dar de alta un cliente pagando, o después de agregar un módulo nuevo con tablas propias. Se diferencia de /security-review (que solo mira el diff de la rama actual): esta skill revisa TODO el sistema en su estado actual, incluso código no tocado en esta sesión.
---

# Auditoría de seguridad — Bestoic

Bestoic es un panel de gestión de alojamientos multi-tenant (Supabase +
Postgres + Netlify, un solo archivo `app/panel.html`). Ya pasó una auditoría
completa el 2026-08-02 (ver `docs/obsidian/Seguridad.md` y
`docs/cierre-auditoria-2026-08-02.md` si existen) — esta skill es para volver
a pasar el mismo nivel de rigor cada vez que se agrega superficie nueva
(tablas, endpoints, módulos), no para repetir desde cero lo ya cerrado.

## Regla de oro

No confiar en la documentación ni en los nombres de función — **verificar
leyendo el código real y, cuando sea posible, probando en vivo** con un
tenant descartable. Un permiso que existe en el catálogo pero que ninguna
política RLS exige no protege nada (pasó de verdad: migración 0025 vs. 0026).

## Checklist (recorrer TODO, no solo lo que cambió)

### 1. RLS en cada tabla
Para cada tabla en `supabase/migrations/*.sql`:
- ¿Tiene `tenant_id` y una política que filtra por él?
- **La política de SELECT exige también el permiso correspondiente**, no
  solo el tenant — el bug real de la auditoría anterior fue exactamente
  esto: RLS que solo miraba `tenant_id`, dejando que cualquier rol leyera/
  editara/borrara todo dentro del tenant sin chequear
  `has_permission()`/`is_admin()`.
- Las políticas de UPDATE/DELETE, ¿usan las mismas funciones de permiso que
  INSERT/SELECT, o quedaron más laxas?
- Tablas "singleton por tenant" (ej. `billing_config`, `tenant_settings`):
  ¿tienen `id` propio aparte de `tenant_id` como PK? Los triggers genéricos
  de auditoría (`log_audit_event`/`set_audit_fields`) asumen `NEW.id`/
  `OLD.id` vía acceso dinámico a `RECORD` — si falta esa columna, el
  trigger revienta recién al dispararse, no al aplicar la migración.

### 2. service_role nunca en el navegador
```
grep -rn "service_role" app/ supabase/ *.html *.js 2>/dev/null
```
Debe aparecer solo en comentarios/documentación explicando que NO se usa
en el cliente, o en funciones `security definer` del lado de la base. Si
aparece una clave real en `app/config.js` (gitignored) o en cualquier
archivo versionado, es crítico.

### 3. XSS — `esc()` en cada inserción de texto libre
`app/panel.html` usa una función central `esc()` para escapar HTML antes de
insertar valores del usuario (nombre, notas, email, huésped, concepto,
dirección) vía `innerHTML`. Buscar nuevas inserciones sin escapar:
```
grep -n "innerHTML" app/panel.html | grep -v "esc("
```
Prestar atención especial a los dos popups que usan `document.write()`
(factura, reporte mensual imprimible) — ahí un `esc()` faltante es más
grave porque corre en la sesión del que imprime (a veces el admin viendo
datos cargados por un rol de menor confianza).
Los builders de texto plano para WhatsApp (`buildWspText`, etc.) van
directo a portapapeles/textarea, NUNCA a innerHTML — no necesitan `esc()`
en el origen, solo en el punto donde se los previsualiza en pantalla.

### 4. CSP y headers (`app/_headers`)
- `connect-src` debe listar únicamente los orígenes que la app realmente
  necesita (Supabase + el agente local `http://127.0.0.1:8765` si Mercado
  está integrado) — cualquier origen nuevo agregado sin justificar es una
  señal de alerta.
- `script-src`/`style-src` necesitan `'unsafe-inline'` porque todo el HTML
  es un solo archivo con `onclick=` inline — es una limitación conocida y
  aceptada, no la marques como hallazgo nuevo salvo que se vuelva a
  documentar como "por resolver".

### 5. Autenticación y sesión
- "Confirm email" está OFF en Supabase Auth a propósito (alta de usuario
  sin invitación por correo) — verificar que un signup sin confirmar
  **no tenga ningún acceso a datos** hasta que un admin inserte la fila en
  `profiles` (RLS-gated).
- Un usuario desactivado (`profiles.active=false`) con sesión ya abierta:
  ¿`current_tenant_id()`/`has_permission()`/`current_owner_id()` siguen
  exigiendo `active=true`? ¿El frontend sigue haciendo polling cada 60s
  (`startActiveUserWatch()`) y desloguea?
- Creación de usuario nuevo: ¿sigue usando un cliente Supabase aislado
  (`persistSession:false`) para no pisar la sesión del admin que lo crea?

### 6. Storage (Supabase Storage)
- Bucket `tenant-logos`: ¿tiene políticas que solo dejan subir/leer al
  propio tenant? Confirmar que la ruta de subida siga siendo
  `{tenantId}/logo.webp` (fija) y no algo controlable por el cliente que
  permita escribir en la carpeta de otro tenant.

### 7. Sincronización código-real vs. lo desplegado
Antes de dar cualquier veredicto "seguro", verificar que Netlify tenga
publicado el `panel.html` que se está revisando — hubo un caso real donde
una prueba en vivo usó JS viejo por falta de redeploy, dando un falso
positivo. Comparar con `curl -s https://dashing-conkies-92cb00.netlify.app/
| grep <algo específico del cambio reciente>`.

## Cómo reportar

Igual que el cierre de auditoría anterior: tabla Punto / Estado / Evidencia
/ Archivo / Problema / Acción. Marcar severidad (CRÍTICO/ALTO/MEDIO/BAJO) y,
si se corrige algo, dejar migración numerada + verificación en vivo con un
tenant descartable (crear, probar, limpiar — `audit_log` se borra último
por el FK con las demás tablas).

## Ejecución manual

`/security-audit` — corre el checklist completo contra el estado actual del
repo. Si el pedido es solo sobre el diff de la rama actual, usar
`/security-review` en su lugar (más rápido, más acotado).
