# Auditoría de seguridad — Bestoic

**Fecha:** 2026-08-21
**Alcance:** panel (`app/panel.html` + Supabase `ckbarfwqdnehqnpafzay` + `dashing-conkies-92cb00.netlify.app`), web comercial (`index.html` / `software.html` + `software-eyo.netlify.app`), repositorio `webdelhotelcom/SoftwareEYO`.
**Método:** análisis estático de las 45 migraciones y del frontend, escaneo de secretos sobre archivos versionados **y sobre el historial de git**, y **pruebas de ataque en vivo contra producción** (lectura anónima de las 34 tablas, llamadas anónimas a las 13 RPC, escrituras anónimas). No se modificó ningún dato de producción.

---

## Estado general

**Nivel de seguridad actual: ALTO**, con **una corrección crítica pendiente de aplicar** (migración `0047`, ver *Acciones manuales*).

La base es sólida y no es casualidad: las 34 tablas tienen RLS, las 107 políticas son específicas (ninguna `USING (true)`), las 29 funciones `SECURITY DEFINER` fijan `search_path`, los PIN de caja usan bcrypt en una tabla aparte inaccesible desde el cliente, y el escapado de XSS está centralizado. Las pruebas en vivo confirmaron que eso funciona de verdad, no solo en el papel.

El hallazgo crítico es de una clase que el análisis "por política" no detecta: **RLS autoriza filas, no columnas.**

---

## Vulnerabilidades encontradas

### P0 — CRÍTICA

#### 1. Escalada de privilegios: un usuario podía hacerse admin

- **Severidad:** CRÍTICA
- **Archivo:** `supabase/migrations/0003_rls_core_tables.sql` (política `profiles_update_self`)
- **Problema:** la política deja que cada usuario edite su propia fila de `profiles` exigiendo solo `id = auth.uid()` y que no cambie de `tenant_id`. En PostgreSQL una política RLS autoriza la **fila**, no las **columnas** — y en esa misma fila viven `role`, `active` y `owner_id`. No había ningún trigger que las protegiera.
- **Riesgo:** cualquier usuario logueado (por ejemplo uno de rol `limpieza`) podía llamar directo a la API REST con la clave anon, que es pública por diseño:

  ```
  PATCH /rest/v1/profiles?id=eq.<su_propio_uid>
  { "role": "admin" }
  ```

  y convertirse en administrador de su cliente: ver y borrar reservas, gastos, huéspedes y auditoría, y administrar a los demás usuarios. Por el mismo camino, un usuario `propietario` podía cambiar su `owner_id` y pasar a ver la facturación de otro propietario del mismo tenant. La interfaz nunca ofrece ese botón, pero la interfaz no es una defensa: la petición se arma a mano.
- **Solución realizada:** migración `0047_proteger_columnas_privilegiadas_profiles.sql` — trigger `BEFORE UPDATE` que congela `role`, `active`, `tenant_id`, `owner_id` e `id` salvo que quien edita sea admin activo del mismo tenant (el flujo legítimo de "Usuarios y permisos"). Se eligió un trigger y no una política porque una política RLS no puede comparar el valor viejo contra el nuevo. El único auto-update que hace la app hoy (`last_active_at`) sigue funcionando igual.
- **Estado:** **CORREGIDO EN CÓDIGO — PENDIENTE DE APLICAR EN LA BASE** (ver *Acciones manuales*). Es lo único que separa esta app de estar completa.

> Aclaración honesta sobre la evidencia: esta vulnerabilidad está confirmada por lectura del esquema y de las políticas, no por explotación en vivo. Para probarla en producción habría hecho falta crear un usuario real con perfil dentro de un tenant, y eso es modificar datos de producción. La conclusión igual es firme: la columna `role` existe en `profiles`, la política permite el `UPDATE` de esa fila, y no hay trigger ni restricción de columna que lo impida.

---

### P1 — ALTO

#### 2. Librería de autenticación sin fijar versión, con fallback vulnerable

- **Severidad:** ALTA
- **Archivo:** `app/panel.html` (líneas 7-11)
- **Problema:** `@supabase/supabase-js@2` se cargaba con un **tag flotante** (`@2`), es decir, cualquier versión 2.x que el CDN sirviera ese día. El fallback `onerror` apuntaba fijo a `2.45.4`, que **sí está afectada** por `GHSA-8r88-6cj9-9fh5` (*auth-js: Insecure Path Routing from Malformed User Input*, corregida en 2.69.2+). Ninguno de los 5 recursos externos tenía Subresource Integrity.
- **Riesgo:** doble. Por un lado, la librería que maneja los tokens de sesión podía caer en una versión vulnerable por la ruta de fallback. Por otro, un tag flotante sin SRI significa que si el CDN fuera comprometido, se ejecutaría JavaScript arbitrario dentro de la sesión del usuario — con acceso completo a su sesión de Supabase.
- **Solución realizada:** las 5 dependencias quedaron con versión fija y hash SRI `sha384` verificado (descargando el archivo real y calculando el hash, no copiándolo de ningún lado). `supabase-js` pasó a `2.112.3`, y su fallback a unpkg con el **mismo** hash (verificado byte a byte: es el mismo archivo). Los fallbacks dinámicos ahora también fijan `integrity` y `crossOrigin` antes de insertar el `<script>`.
- **Estado:** **CORREGIDO Y DESPLEGADO.** Verificado en producción: 5 recursos con SRI, consola sin errores, todas las librerías cargan.

---

### P2 — MEDIO

#### 3. La web comercial no tenía ningún header de seguridad

- **Severidad:** MEDIA
- **Archivo:** no existía `_headers` en la raíz del sitio comercial
- **Problema:** `software-eyo.netlify.app` respondía únicamente con el HSTS que agrega Netlify por defecto. Sin `X-Frame-Options`, sin CSP, sin `X-Content-Type-Options`, sin `Referrer-Policy`. El panel sí los tenía; la web comercial se quedó afuera cuando se publicó como sitio aparte.
- **Riesgo:** clickjacking (la página de precios podía embeberse en un iframe con una capa encima), MIME sniffing, y fuga de referrer hacia terceros.
- **Solución realizada:** nuevo `_headers` en la raíz con CSP ajustada a lo que la web comercial realmente usa (CSS/JS inline, tipografías de Google, imágenes en base64, iframes de `youtube-nocookie.com`), más `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy` y `Cross-Origin-Opener-Policy`.
- **Estado:** **CORREGIDO Y DESPLEGADO.** Verificado en vivo: headers presentes, cero violaciones de CSP, las 16 imágenes y las tipografías cargan, los precios renderizan.

#### 4. `xlsx` 0.18.5 con CVEs sin parche en el registro de npm

- **Severidad:** MEDIA (**baja en la práctica**, ver riesgo)
- **Archivo:** `app/panel.html`
- **Problema:** `xlsx@0.18.5` arrastra `GHSA-4r6h-8v6p-xvw6` (prototype pollution, alta) y `GHSA-5pgg-2g8v-p4x9` (ReDoS). En npm no hay versión corregida: SheetJS dejó de publicar ahí y las versiones parcheadas viven solo en su CDN propio.
- **Riesgo:** **acotado.** Ambos CVE se disparan al **parsear** un archivo malicioso, y esta app nunca parsea: solo escribe (`XLSX.writeFile`, `aoa_to_sheet`, `book_new`, `book_append_sheet`; cero llamadas a `XLSX.read`). No es explotable con el uso actual, pero quedaba como deuda si algún día se agrega importación desde Excel.
- **Solución realizada:** actualizado a `0.20.3` desde `cdn.sheetjs.com` (con SRI), y `script-src` de la CSP ampliada para permitir ese origen. Probada la API exacta que usa la app: genera un `.xlsx` válido de 15 KB en 0.20.3.
- **Estado:** **CORREGIDO Y DESPLEGADO.**

#### 5. Registro público de cuentas habilitado

- **Severidad:** MEDIA
- **Dónde:** configuración de Supabase Auth (`disable_signup: false`)
- **Problema:** cualquiera puede crear una cuenta en el proyecto de Auth. Está así **por diseño**: el alta de usuarios del panel usa `auth.signUp()` desde un cliente temporal aislado justamente para no meter la `service_role` en el navegador — y eso exige que el signup esté abierto.
- **Riesgo:** **no hay acceso a datos.** Una cuenta recién creada no tiene fila en `profiles`, así que `current_tenant_id()` devuelve NULL y toda la RLS la bloquea (verificado en vivo). El riesgo real es de **abuso, no de fuga**: alta masiva de cuentas huérfanas y consumo de la cuota de correos del plan gratuito de Supabase, que podría dejar sin correos de confirmación a los usuarios legítimos.
- **Solución realizada:** ninguna automática — cerrarlo rompería el alta de usuarios del panel. Requiere una decisión de producto (ver *Acciones manuales*).
- **Estado:** **DOCUMENTADO, PENDIENTE DE DECISIÓN.**

#### 6. Proveedor de Google habilitado en Auth pero oculto en la interfaz

- **Severidad:** MEDIA-BAJA
- **Problema:** el proveedor `google` figura activo en Supabase Auth, mientras que en el panel los botones de "Continuar con Google/Microsoft" están deliberadamente ocultos (`display:none`) porque la integración quedó pausada.
- **Riesgo:** mismo patrón que el punto 5 — se puede completar un login con Google contra el proyecto sin pasar por la interfaz, generando una cuenta huérfana. Sin fila en `profiles`, sigue sin ver datos.
- **Estado:** **DOCUMENTADO** (ver *Acciones manuales*).

---

### P3 — BAJO

#### 7. Dirección de desarrollo (`127.0.0.1`) en la CSP de producción

- **Archivo:** `app/_headers`
- **Problema:** `connect-src` incluía `http://127.0.0.1:8765`, un resto de desarrollo. Además de innecesario, era el único origen en texto plano (`http://`) de toda la política.
- **Solución realizada:** eliminado. Agregados también `Cross-Origin-Opener-Policy: same-origin` y `upgrade-insecure-requests`.
- **Estado:** **CORREGIDO Y DESPLEGADO.**

#### 8. `jspdf` 2.5.1 depende de una versión vulnerable de `dompurify`

- **Problema:** `jspdf@2.5.1` arrastra `dompurify` con varios avisos de XSS (severidad moderada). Corregirlo exige `jspdf` 4.x, que es un cambio mayor.
- **Riesgo:** **no alcanzable.** `dompurify` solo entra en juego por el camino de `doc.html()`, y la app nunca lo llama: usa `.text()` (22 veces) y nada de renderizado de HTML a PDF.
- **Solución realizada:** ninguna — no se hizo el salto mayor a `jspdf` 4.x porque el riesgo no es alcanzable y la actualización podría romper los reportes en PDF, que es funcionalidad en uso. Sí quedó pineado con SRI.
- **Estado:** **ACEPTADO Y DOCUMENTADO.** Revisar si algún día se usa `doc.html()`.

#### 9. Numeración de migraciones con un hueco

- **Problema:** falta `0032` en la secuencia (va de `0031` a `0033`). No es un problema de seguridad, pero complica auditar si el estado de la base coincide con el repositorio.
- **Estado:** **ANOTADO**, sin cambios.

---

## Incidente durante la auditoría (resuelto)

Al desplegar el panel endurecido, **el panel quedó unos minutos con la CSP equivocada y no cargaba ninguna librería**. Causa: `netlify deploy` se ejecutó desde `D:\Ori\EYO`, donde el propio CLI había dejado un `.netlify/netlify.toml` con `publish = "D:\Ori\EYO"`. Con eso el CLI tomó el `_headers` de la **web comercial** (raíz del repo) en lugar del que se le pasaba por `--dir`. Se detectó porque la verificación posterior al deploy comparó el header realmente servido contra el esperado.

- **Solución:** se volvió a desplegar desde un directorio neutral y se eliminó el `netlify.toml` obsoleto.
- **Verificado:** consola limpia, CSP correcta, `Chart`/`jsPDF`/`XLSX 0.20.3`/`supabase.createClient` cargando, iconos Tabler cargando.
- **Lección para el futuro:** los dos sitios comparten repositorio pero necesitan `_headers` distintos. **Desplegar siempre desde el directorio del deploy, nunca desde la raíz del repo**, y verificar el header servido después de cada deploy.

---

## Lo que se probó y resultó correcto

| Prueba (Fase 19) | Resultado |
|---|---|
| Lectura anónima de las **34 tablas** | **0 filas expuestas** en todas |
| Llamada anónima a las **13 RPC** con firma correcta | **13/13 rechazadas** (`Usuario no autenticado o inactivo`) |
| `INSERT` anónimo en `properties`, `reservations`, `profiles`, `tenants`, `audit_log`, `role_permissions` | Todos bloqueados |
| Secretos en archivos versionados | Ninguno |
| Secretos en el **historial de git** | `app/config.js` y `.env` **nunca** se commitearon |
| Clave del navegador | `role: anon` (verificado decodificando el JWT), no `service_role` |
| RLS por tabla | 34/34 con `ENABLE ROW LEVEL SECURITY` |
| Políticas demasiado abiertas | 0 de 107 usan `USING (true)` / `WITH CHECK (true)` |
| `SECURITY DEFINER` sin `search_path` fijo | 0 de 29 (las 14 coincidencias restantes son comentarios) |
| Escalada vía `role_permissions` | Bloqueada: escrituras exigen `is_admin()` |
| Escalada vía límites de plan (`tenants`, `client_limits`, `plan_config`) | Bloqueada: solo lectura, sin políticas de escritura |
| Hash de PIN de caja | bcrypt (`gen_salt('bf')`), en `cash_operator_secrets`, tabla con RLS y **cero políticas** (inaccesible desde el cliente) |
| XSS | `esc()` central y correcta, aplicada en el renderizado; sin `eval`, `new Function` ni `insertAdjacentHTML` |
| Datos sensibles en `localStorage` | Ninguno: solo tema, idioma, modo y último uid |
| Logs con secretos | 0 de 8 `console.*` filtran nada |
| GitHub Actions | No hay workflows |

---

## ACCIONES MANUALES NECESARIAS

### 1. Aplicar la migración `0047` (CRÍTICO — hacelo primero)

Es lo único que falta para cerrar la escalada de privilegios.

- **Dónde:** Supabase → proyecto `ckbarfwqdnehqnpafzay` → **SQL Editor**
- **Qué:** pegar el contenido de `supabase/migrations/0047_proteger_columnas_privilegiadas_profiles.sql` y ejecutar.
- **Después, comprobá que no rompió nada:** entrá al panel y verificá que (a) podés iniciar sesión normal y (b) desde "Usuarios y permisos" un admin todavía puede cambiarle el rol a otro usuario.
- **Riesgo de aplicarla:** bajo. Solo agrega un trigger; no borra ni modifica datos.

### 2. Decidir qué hacer con el registro público (`disable_signup`)

- **Motivo:** hoy cualquiera puede crear una cuenta huérfana. No accede a datos, pero puede consumir la cuota de correos del plan gratuito.
- **Opción recomendada:** dejarlo abierto por ahora (cerrarlo rompe el alta de usuarios del panel) y activar en Supabase → Authentication → Rate Limits un límite de altas por hora/IP. Es la protección que ataca el abuso sin romper el flujo legítimo.
- **Opción alternativa:** cerrar el signup y cambiar el alta de usuarios a una Edge Function con la `service_role` guardada del lado servidor. Es lo correcto a futuro, pero es una obra aparte, no un ajuste de configuración.

### 3. Revisar el proveedor de Google en Auth

- **Dónde:** Supabase → Authentication → Sign In / Providers.
- **Qué:** si el login con Google sigue pausado en el panel, conviene desactivar el proveedor hasta que se retome. Si preferís dejarlo listo, no pasa nada grave — igual no da acceso a datos sin perfil.

### 4. Activar las protecciones del repositorio en GitHub

En `github.com/webdelhotelcom/SoftwareEYO` → Settings → Code security:

- **Secret scanning** y **Push protection** — bloquean el commit de una clave antes de que entre al historial.
- **Dependabot alerts** — avisa de dependencias vulnerables.

Recomendado porque el repo es **público**. Hoy no hay ningún secreto adentro (verificado, incluido el historial), y esto es para que siga siendo así.

### 5. No hace falta rotar ninguna clave

No se encontró ninguna credencial privada expuesta, ni en los archivos ni en el historial de git. La única clave en el navegador es la `anon`, que es pública por diseño y está respaldada por RLS. **No hay nada que rotar por esta auditoría.**

> Nota aparte: durante esta sesión me pasaste por el chat un token de Netlify y uno de GitHub para poder desplegar y publicar. No quedaron escritos en ningún archivo ni en la configuración de git (se usaron solo en la línea de comando). Aun así, como viajaron por el chat, lo prolijo es **revocarlos** cuando termines: GitHub → Settings → Developer settings → Personal access tokens; Netlify → User settings → Applications.

---

## Puntuación

| Área | Ahora | Tras aplicar 0047 |
|---|---:|---:|
| Secretos | 10/10 | 10/10 |
| Autenticación | 7/10 | 7/10 |
| Autorización | 6/10 | 9/10 |
| RLS | 9/10 | 9/10 |
| Multi-tenant | 9/10 | 9/10 |
| Frontend | 9/10 | 9/10 |
| Backend / RPC | 9/10 | 9/10 |
| API | 8/10 | 8/10 |
| Supabase | 8/10 | 9/10 |
| Netlify | 9/10 | 9/10 |
| Dependencias | 8/10 | 8/10 |
| Logging | 9/10 | 9/10 |

**SEGURIDAD TOTAL: 84/100 ahora → 88/100 tras aplicar la migración `0047`.**

Lo que impide una nota más alta no son agujeros abiertos, sino tres cosas estructurales y conocidas: el registro público abierto (consecuencia de no usar `service_role` en el servidor), la ausencia de rate limiting propio en operaciones sensibles, y que `'unsafe-inline'` es obligatorio en la CSP mientras el panel siga siendo un único archivo con ~200 `onclick` en línea.

---

## Cambios aplicados en el código

| Archivo | Cambio |
|---|---|
| `supabase/migrations/0047_proteger_columnas_privilegiadas_profiles.sql` | **Nuevo.** Trigger que bloquea la auto-escalada de rol. *Pendiente de aplicar.* |
| `app/panel.html` | 5 dependencias con versión fija + SRI + `crossorigin`; `xlsx` 0.18.5 → 0.20.3; `supabase-js` `@2` → `2.112.3`; fallbacks con SRI. |
| `app/_headers` | Quitado `http://127.0.0.1:8765`; agregados `cdn.sheetjs.com` y `unpkg.com`; `Cross-Origin-Opener-Policy` y `upgrade-insecure-requests`. |
| `_headers` (raíz) | **Nuevo.** Headers de seguridad de la web comercial, que no tenía ninguno. |
