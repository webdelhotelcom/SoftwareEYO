# Login externo (Google / Microsoft) — pausado

Ver también: [[00-Indice]] · [[Arquitectura]] · [[Seguridad]] · [[Modulos]] · [[Estado-actual]]

Trabajo iniciado el 2026-08-05 para agregar "Continuar con Google" y "Continuar con Microsoft" al login de Bestoic, usando exclusivamente Supabase Auth + proveedores oficiales (nunca un sistema de login casero). **Pausado a pedido explícito del usuario** por trancarse en la configuración de Google Cloud Console — el código queda listo, oculto, para retomar sin tener que rehacer nada.

## Qué está construido y probado (en `app/panel.html`)

- Botones "Continuar con Google" / "Continuar con Microsoft" en la pantalla de login, con el texto exacto pedido. Hoy están **ocultos** (`display:none` en `#login-oauth-buttons`) — el HTML y el JS siguen enteros, solo hay que sacar ese `display:none` para reactivarlos.
- `doOAuthLogin(provider)`: dispara `supabaseClient.auth.signInWithOAuth({provider,...})`. Ningún Client Secret pasa nunca por el frontend — vive solo en la configuración de Supabase.
- **Vinculación de identidades** (Ajustes → sección oculta con el mismo criterio): `linkIdentity()`/`unlinkIdentity()` de Supabase Auth, para que un usuario que ya tiene cuenta con correo/contraseña pueda sumar Google/Microsoft **a la misma cuenta** en vez de que se le cree una cuenta de Auth nueva y separada (así se evita el problema de "cuenta duplicada al usar el mismo correo con otro proveedor"). Nunca deja desvincular el único método de acceso que le queda a alguien.
- Mensaje de error claro cuando alguien entra por primera vez sin perfil (`loadSessionUser`), explicando que si ya tenía cuenta con contraseña, un admin le tiene que vincular el proveedor en vez de crear una cuenta nueva.
- Verificado: sin errores de consola, sin ningún secreto en el código (`grep` por `client_secret`/`GOCSPX` sobre `panel.html` da limpio), botones con el texto exacto pedido.

## Dónde quedó trancado (Google Cloud Console)

1. Se creó el proyecto de Google Cloud "software-eyo" y se configuró la pantalla de consentimiento OAuth (tipo Externo).
2. Se creó un cliente OAuth 2.0 tipo "Web application" con el redirect URI:
   `https://ckbarfwqdnehqnpafzay.supabase.co/auth/v1/callback`
3. Primer Client ID generado: `345551546693-mithrff38j1fbpjfceehilt5lqij4uja.apps.googleusercontent.com` (cargado en Supabase → Authentication → Providers → Google).
4. Primer intento de login real: `{"code":400,"msg":"Unsupported provider: provider is not enabled"}` — el proveedor no había quedado guardado/activado del todo en Supabase.
5. Se generó un Client Secret nuevo (el primero se compartió por error en el chat de la sesión de trabajo — **quedó potencialmente expuesto, no reusar ese secret si en algún momento aparece documentado en otro lado**) y se volvió a guardar en Supabase.
6. Segundo intento: `Error 401: deleted_client — The OAuth client was deleted.` — Google reportó el cliente OAuth como borrado.
7. Al revisar Google Cloud Console, el cliente **sí aparecía como existente** — contradicción sin resolver entre lo que reporta el flujo de login y lo que se ve en la consola. No se llegó a confirmar si el Client ID vigente en Google Cloud Console coincide con el que quedó guardado en Supabase (puede haberse recreado el cliente en algún momento del ida y vuelta, dejando un ID viejo guardado en Supabase).
8. Microsoft Entra ID: ni siquiera se llegó a crear el App Registration — al entrar a "Microsoft Entra ID" desde el portal, tiró un error de tenant (`La cuenta de usuario seleccionada no existe en el inquilino "Microsoft Services"...`) que no se resolvió ni en una ventana de incógnito.

## Para retomar

1. **Google**: entrar a Google Cloud Console → Credentials, confirmar el Client ID vigente del cliente OAuth, compararlo contra el que está guardado en Supabase (Authentication → Providers → Google) — si no coinciden, actualizar Supabase con el ID/secret correctos. Si el cliente realmente se corrompió, más simple recrearlo de cero (tipo Web, mismo redirect URI) que seguir diagnosticando el estado inconsistente.
2. **Microsoft**: retomar desde `https://entra.microsoft.com` directo (se sugirió como alternativa al error de tenant, no se llegó a probar) — si el error de tenant persiste, puede hacer falta crear/asociar un directorio de Microsoft Entra propio para la cuenta usada.
3. Una vez con credenciales válidas y activadas en Supabase: sacar el `display:none` de `#login-oauth-buttons` y de la sección de vinculación en Ajustes (`app/panel.html`, buscar el comentario "Login con Google/Microsoft: pausado"), y volver a descomentar la llamada a `renderAjustesIdentidades()` dentro de `renderAjustesPage()`.
4. Redeploy a Netlify y probar el login real de punta a punta con una cuenta agregada como "test user" en la pantalla de consentimiento de Google (mientras la app de Google siga en modo "Testing", solo esas cuentas pueden entrar — para producción real hay que publicar la app fuera de modo prueba).

## Nota de seguridad

Un Client Secret de Google quedó pegado en el chat de la sesión de trabajo por error del usuario (no debería volver a pasar — los secretos se cargan directo en Supabase, nunca por el chat). Se generó uno nuevo para reemplazarlo. Si en algún momento se recupera/reutiliza el proyecto de Google Cloud, conviene revisar que no quede ningún Client Secret viejo activo sin usar.
