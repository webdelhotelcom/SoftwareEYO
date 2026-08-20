# Web EYO — Sitio personal (index.html)

Ver también: [[00-Indice]] · [[Estado-actual]] · [[Historia-y-decisiones]]

**Proyecto aparte, no es Software EYO.** Es el sitio personal/de trayectoria de Orieles (el usuario), separado del panel de gestión de alojamientos. Vive en un repo distinto, con su propia cuenta de GitHub, y no comparte código ni infraestructura con `app/panel.html`.

## Qué es

Repo local: `D:\Ori\webeyo`. Dos páginas HTML de una sola pieza (sin build step, fotos embebidas en base64 dentro del HTML):
- **`index.html`** — sitio personal: "Sobre mí", historia, formación, y una sección "Logros" con la trayectoria de los alojamientos que gestiona (tarjetas + modales con fotos), incluyendo el relato de los 3 alojamientos de Elsa Fernández (Medio/Grande/Nueva) y otros clientes (Dac, Zulmira, Maciega, Gloria, Casa Propia).
- **`hostal.html`** — página de reservas del hostal, con un array JS `HABITACIONES` que referencia fotos como archivos sueltos (`fotos/img-XXX.jpg`), a diferencia de `index.html` que las incrusta en base64. **Tarea distinta y separada, no tocada en esta ronda** — quedó a medio hacer de una sesión anterior (reemplazo de fotos de Grande, ver `git status` en el repo) y sigue en pausa.

## El problema de acceso a GitHub (2026-08-20)

El repo original vivía en `github.com/manuelfestaori-star/webeyo`, publicado vía GitHub Pages en `manuelfestaori-star.github.io/webeyo`. **El usuario no tiene las credenciales de esa cuenta** (`manuelfestaori-star`) — al intentar hacer `git push`, GitHub devolvía 403 (permiso denegado) sin importar con qué cuenta propia se autenticara (`orielesymama-cyber`, luego `webdelhotelcom`).

**Solución aplicada:** en vez de perseguir el acceso a la cuenta vieja, se migró todo a una cuenta que el usuario sí controla (`webdelhotelcom`), en un repo nuevo.

- **Repo nuevo:** `github.com/webdelhotelcom/EYOSoftware` (se creó como `eyosoftware` en minúscula, GitHub lo normalizó a `EYOSoftware`).
- **Remote local agregado:** `git remote add eyosoftware https://github.com/webdelhotelcom/eyosoftware.git` (el remote `origin` original, hacia `manuelfestaori-star/webeyo`, se dejó intacto sin tocar — sigue ahí pero no se usa).
- **Link nuevo, en vivo:** **`https://webdelhotelcom.github.io/EYOSoftware/index.html`**
- **Link viejo** (`manuelfestaori-star.github.io/webeyo`) quedó desactualizado — si está compartido en algún lado (Booking, Instagram, WhatsApp Business, tarjetas), el usuario tiene que actualizarlo a mano. No se verificó dónde está enlazado.
- **Autenticación:** el administrador de credenciales de Windows (Git Credential Manager) tenía cacheada la cuenta equivocada y no soltaba el login aunque el usuario iniciara sesión distinto en el navegador — se resolvió generando un **Personal Access Token clásico** (`ghp_...`, scope `repo`, expiración 7 días) desde `github.com/settings/tokens` con la cuenta `webdelhotelcom`, y haciendo el push con el token embebido en la URL (`git push https://x-access-token:TOKEN@github.com/...`), sin guardarlo en ningún archivo. GitHub Pages también se activó vía API (`POST /repos/{owner}/{repo}/pages`) con ese mismo token, en vez de por la interfaz web.
- Los tokens generados durante esta sesión deberían revocarse desde `github.com/settings/tokens` — quedó pendiente que el usuario lo confirme.

**Cómo aplicar:** cualquier cambio futuro a `index.html` se sube así:
```bash
cd D:\Ori\webeyo
git add index.html
git commit -m "..."
git push eyosoftware main
```
(Puede volver a pedir login — si el administrador de credenciales de Windows tiene guardada la cuenta equivocada, hay que borrar esa entrada en "Administrador de credenciales" → "Credenciales de Windows" → buscar `git:https://github.com`.)

## Trabajo hecho el 2026-08-20 (todo sobre `index.html`)

1. **Emiliano** — nueva tarjeta de alojamiento en la sección de trayectoria (mismo diseño que las demás), año 2026, **sin fotos** (el usuario no las tenía todavía) — placeholder "Fotos próximamente" tanto en la miniatura como en el modal. Nuevas clases CSS `.traj-thumb-placeholder` / `.prop-modal-img-placeholder` para este caso.
2. **Apart Medio** — portada nueva + galería de 4 fotos (antes solo tenía portada + 2 fotos), tomadas de una carpeta que el usuario dejó en `D:\Ori\Medio`.
3. **Apart Grande** — portada nueva + galería de 8 fotos. **Antes no existía galería para Grande** (los modales de este sitio en general solo tienen una foto de portada, salvo que se les agregue explícitamente un bloque `.modal-sub-fotos` — la misma clase CSS ya la usaban otros alojamientos como Casa Gloria, así que se reutilizó, no se inventó una nueva). Fotos de `D:\Ori\Grande`.
4. **Apart Nueva** — cambio de portada solamente (a una foto de la habitación en vez de la entrada al baño). *Nota: en el primer intento se pisó por error la portada de **Casa Maciega** (otro alojamiento, sin relación) por un cálculo mal hecho de los límites de un bloque de HTML — se detectó y restauró desde el commit anterior antes de continuar.*
5. **Sección "Antes y Después"** (dentro de "Logros"): tenía un montage genérico de 20 fotos "antes" + 33 "después" sin etiquetar, una de las cuales (dentro de "antes") era un auto estacionado en lo que hoy es el Almacén. Se agregaron dos comparaciones nuevas, etiquetadas, **sin borrar el montage original**:
   - "Apartamento Grande — Antes/Después" (fotos de las carpetas `Grande Vieja` y `Grande`)
   - "Almacén EYO — Antes/Después" (la foto del auto, movida acá desde el montage original de "antes", + fotos nuevas de `Almacen Nuevo`)
   - **Error cometido y corregido en esta misma ronda:** el primer intento reemplazó TODO el montage original por solo estas 7 fotos nuevas, perdiendo las 52 fotos originales — el usuario lo notó y se corrigió restaurando las fotos originales (ya estaban guardadas localmente en el directorio de scratch de la sesión) y agregando las nuevas al lado, no en su lugar. Quedó también una etiqueta HTML rota (`<div class="` faltante) de ese primer intento, reparada en el mismo arreglo.
6. **Responsive en celular** — el problema real no era el tamaño de fuente: la tira de fotos circulares "Mi historia en fotos" (con scroll horizontal propio, `overflow-x:auto`) no tenía `min-width:0`, así que forzaba todo el bloque `.about-content` (grid item) a 795px de ancho aunque el viewport fuera de 375px — desbordamiento horizontal real medido y confirmado con JS (`document.body.scrollWidth`), no solo visual. Se arregló con `min-width:0` en la cadena de contenedores (`.about-content`, `.about-life-gallery`, `.about-life-strip`), más un `overflow-wrap:break-word` global de seguridad y un breakpoint extra a 420px para los títulos más grandes.
7. **Texto corregido**: "cada alojamiento... representa aproximadamente el 50% del costo **de** un mes de mi carrera universitaria" (antes decía "costo anual de un mes", mezclaba dos ideas).

## Cómo verificar que esta nota sigue vigente

`git log --oneline` en `D:\Ori\webeyo` sobre el remote `eyosoftware` — los commits de esta sesión tienen mensajes descriptivos de cada cambio. Si el link `webdelhotelcom.github.io/EYOSoftware` no carga o muestra contenido viejo, revisar `git remote -v` (¿sigue apuntando a `webdelhotelcom/eyosoftware`?) y el estado de GitHub Pages en `Settings → Pages` del repo.
