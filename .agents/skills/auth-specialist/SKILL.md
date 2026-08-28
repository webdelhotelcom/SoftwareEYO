---
name: auth-specialist
description: Trabajo en login, alta de usuarios, cambio/recuperación de contraseña, sesión activa o desactivación de cuentas en Bestoic (Supabase Auth). Usar ante pedidos como "agregar un método de login", "arreglar el flujo de contraseña", "un usuario desactivado sigue entrando", "el login no redirige bien", o cualquier cambio en `Usuarios y permisos` / pantalla de login.
---

# Autenticación — Bestoic (Supabase Auth)

## Cómo funciona hoy (no reinventar sin revisar esto primero)

- **Login**: email + contraseña contra Supabase Auth estándar. "Confirm
  email" está OFF a propósito — un alta de usuario nuevo no manda correo,
  loguea directo con una contraseña temporal.
- **Alta de usuario ("Nuevo usuario")**: el admin la hace desde adentro de
  la app. Usa un **cliente Supabase aislado** (`persistSession:false`,
  `storageKey` distinto) para llamar `auth.signUp()` — así NO pisa la
  sesión del admin que está creando el usuario. Después inserta la fila en
  `profiles` con el cliente autenticado normal, permitido por la política
  `profiles_insert_by_admin` (exige `is_admin()` + mismo tenant). La
  contraseña temporal se genera random, se muestra una sola vez en el
  modal, no se manda por email (no hay SMTP configurado).
- **Recuperación de contraseña**: hay una pantalla especial que aparece
  cuando el usuario vuelve del link de recuperación de Supabase (buscar el
  comentario "Pantalla que aparece cuando el usuario vuelve desde el link
  de recuperación de contraseña" en `panel.html`).
- **Cambiar mi contraseña** (usuario logueado, no admin): modal aparte,
  sección Ajustes.
- **Sesión activa / desactivación**: `profiles.active=false` bloquea el
  *próximo* login vía `current_tenant_id()`/`has_permission()`/
  `current_owner_id()` (todas exigen `active=true`), pero una sesión YA
  abierta no se corta sola — por eso existe `startActiveUserWatch()`, que
  hace polling cada 60s y desloguea con el mensaje "Tu usuario fue
  desactivado" apenas detecta `active=false`. Hay una política
  `profiles_select_self_always` para que el usuario desactivado pueda
  seguir leyendo su propia fila (si no, el frontend no podría ni detectar
  que lo desactivaron).
- **Roles**: fundador, administrador, encargado, empleado, propietario.
  El rol NO es lo mismo que el permiso — ver skill `permissions-review`
  para el catálogo completo.

## Reglas al tocar este flujo

1. **Nunca** loguear con el `service_role` ni exponerlo en el navegador
   para crear usuarios — el patrón del cliente aislado con `signUp()` ya
   resuelve "crear un usuario sin admin API" sin necesitar esa clave.
2. Cualquier cambio en la creación de usuarios tiene que preservar: no
   tocar la sesión del admin, contraseña random mostrada una sola vez, la
   fila de `profiles` inserta con el tenant del admin (nunca aceptar un
   `tenant_id` que venga del formulario).
3. Si se agrega un método de login nuevo (ej. Google OAuth), verificar que
   el flujo de creación de `profiles` para un usuario que entra por primera
   vez siga pasando por una aprobación explícita del admin del tenant —
   hoy no existe "auto-alta" de tenant por signup libre, y cambiar eso es
   una decisión de producto, no solo técnica (preguntar antes).
4. Al testear desactivación/reactivación, probar en vivo con un usuario
   real (no asumir): crear sesión, desactivar desde otra sesión admin,
   confirmar que la primera sesión se corta sola dentro de ~60s sin
   recargar la página a mano.
5. Nunca mostrar tracebacks de Supabase Auth al usuario final — mapear
   errores conocidos (`Invalid login credentials`, contraseña débil, email
   ya registrado) a mensajes en español, claros, sin jerga técnica.

## Ejecución manual

`/auth-specialist` — repasa el flujo de autenticación actual antes de
implementar un cambio, y aplica las reglas de arriba a la implementación.
