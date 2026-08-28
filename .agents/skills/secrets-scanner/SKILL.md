---
name: secrets-scanner
description: Buscar credenciales, tokens o claves expuestas en el repositorio de Bestoic (Netlify token, Supabase service_role, contraseñas) antes de un commit, push, o deploy. Usar ante pedidos como "revisá que no haya secretos filtrados", "escaneá el repo por credenciales", antes de hacer público el repositorio, o después de pegar un token en el chat/consola para un deploy.
---

# Escaneo de secretos — Bestoic

## Qué NO debe aparecer versionado (ni en `git log`, no solo en el working tree)

- **Netlify personal access token** (prefijo `nfp_...`) — se usa para
  desplegar vía `POST /api/v1/sites/{site_id}/deploys`. Nunca se guarda en
  ningún archivo del repo; se pide de nuevo cada vez en el chat/consola.
- **Supabase `service_role` key** — nunca debe existir en `app/config.js`,
  `app/panel.html`, ni en ningún script. Solo `SUPABASE_URL` y la
  **anon/publishable key** (`sb_publishable_...`) van al cliente — esa sí
  es pública por diseño (la protección real es RLS, no ocultar la key).
- **`app/config.js` real** (con URL+anon key reales) — está en
  `.gitignore` a propósito; solo `app/config.example.js` (placeholder) va
  versionado.
- Contraseñas de usuarios reales, en cualquier formato (ni siquiera de
  prueba, si son reutilizables).

## Dónde buscar (más allá de `grep` superficial)

```
# claves con forma reconocible
grep -rnE "nfp_[A-Za-z0-9]{20,}" . --exclude-dir=.git
grep -rnE "service_role|sb_secret_" . --exclude-dir=.git
grep -rn "SUPABASE_URL\s*=\s*[\"']https" . --exclude-dir=.git

# historial de git, no solo el working tree — un secreto commiteado y
# luego borrado SIGUE en el historial
git log -p --all -- app/config.js
git log --all -p | grep -E "nfp_[A-Za-z0-9]{20,}"
```

**Ojo con `.Codex/settings.local.json`**: los comandos Bash permitidos
("allowlist") a veces quedan guardados con el comando LITERAL que se
ejecutó, incluyendo tokens pegados inline en un `curl -H "Authorization:
Bearer nfp_..."`. Revisar ese archivo específicamente — es fácil que un
token de una sesión anterior quede ahí de forma invisible para quien no
piensa en mirar ese archivo. Si aparece uno, avisar al usuario para que lo
revoque (un token viejo reusado sigue siendo válido hasta que se revoca a
mano en Netlify) y limpiar la entrada del allowlist.

## Qué SÍ es público a propósito (no marcar como hallazgo)

- La anon/publishable key de Supabase en `config.js` — diseñada para
  distribuirse en el cliente.
- El `site_id` de Netlify, el `project ref` de Supabase — identificadores,
  no secretos.
- El CSP en `app/_headers` listando dominios de Supabase — información
  pública de configuración.

## Si se encuentra un secreto expuesto

1. Confirmar si sigue siendo válido (para un token, un `curl` de prueba
   contra la API correspondiente).
2. Avisar inmediatamente al usuario — un secreto filtrado se revoca
   siempre desde el panel del proveedor (Netlify/Supabase), nunca alcanza
   con borrarlo del archivo si ya se commiteó (sigue en el historial).
3. Recién después de la revocación, limpiar el archivo/historial si hace
   falta (rewrite de historial es una operación destructiva — confirmar
   con el usuario antes de tocar `git filter-repo`/`BFG`).

## Ejecución manual

`/secrets-scanner` — corre el escaneo completo (working tree + historial +
`settings.local.json`) y reporta cualquier hallazgo con severidad.
