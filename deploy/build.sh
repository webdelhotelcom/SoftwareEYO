#!/usr/bin/env bash
# Arma el directorio de publicación del sitio unificado y lo despliega.
#
# ESTRUCTURA DEL SITIO (decidida el 2026-08-26):
#   /        -> web comercial pública (index.html)  <- NO el login
#   /panel   -> el software (panel.html)
# Antes el panel se servía en la raíz. Eso dejaba el dominio como "una página
# que solo pide credenciales con botones de Google/Microsoft", que es el patrón
# que disparó la marca de "sitio engañoso" de Google Safe Browsing.
#
# DOS TRAMPAS QUE YA COSTARON UN INCIDENTE — no cambiar sin releer esto:
#
# 1) NO desplegar con `netlify deploy --dir=app`. Eso publica solo el panel y
#    deja la raíz del dominio en 404.
#
# 2) HAY QUE DESPLEGAR DESDE FUERA DEL REPO. Netlify lee el `_headers` de la
#    raíz del directorio base (D:/Ori/EYO/_headers, que es el de la OTRA web)
#    y ese pisa al del directorio publicado, sin importar el orden ni --no-build.
#    Comprobado en deploys borrador. Si se despliega desde el repo, el panel
#    queda con `connect-src 'self'`, que bloquea Supabase y lo deja inservible.
#
# Verificar SIEMPRE con un borrador (sin --prod) antes de publicar.
set -euo pipefail

REPO="D:/Ori/EYO"
OUT="${1:-/tmp/bestoic_publish}"
SITE_ID="4a32f93b-1d36-4093-ac74-a5483f83c131"

rm -rf "$OUT" && mkdir -p "$OUT/app"
cp "$REPO/index.html"        "$OUT/index.html"      # landing pública
cp "$REPO/software.html"     "$OUT/software.html"
cp -r "$REPO/assets"         "$OUT/assets"
cp "$REPO/app/panel.html"    "$OUT/panel.html"      # /panel y /panel.html
cp "$REPO/app/config.js"     "$OUT/config.js"
cp "$REPO/404.html"          "$OUT/404.html"
# PWA del panel (instalable como app) -- start_url del manifest es /panel,
# nunca la landing pública. sw.js solo cachea assets propios, nunca Supabase.
cp "$REPO/app/manifest.webmanifest" "$OUT/manifest.webmanifest"
cp "$REPO/app/sw.js"                "$OUT/sw.js"
cp "$REPO/app/offline.html"         "$OUT/offline.html"
cp "$REPO/app/icon-192.png"         "$OUT/icon-192.png"
cp "$REPO/app/icon-512.png"         "$OUT/icon-512.png"
cp "$REPO/app/icon-maskable-512.png" "$OUT/icon-maskable-512.png"
# panel.html las busca en la raíz; index.html las busca en app/
cp "$REPO/app/privacidad.html" "$OUT/privacidad.html"
cp "$REPO/app/terminos.html"   "$OUT/terminos.html"
cp "$REPO/app/privacidad.html" "$OUT/app/privacidad.html"
cp "$REPO/app/terminos.html"   "$OUT/app/terminos.html"
cp "$REPO/deploy/_headers"     "$OUT/_headers"      # CSP unificada de las dos zonas

echo "Listo en $OUT — desplegar desde ESE directorio, no desde el repo:"
echo "  cd \"$OUT\" && netlify deploy --dir=. --site=$SITE_ID --no-build          # borrador"
echo "  cd \"$OUT\" && netlify deploy --dir=. --site=$SITE_ID --no-build --prod   # producción"
