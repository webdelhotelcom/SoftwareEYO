# Estado de respaldos (todos los proyectos)

Ver también: [[00-Indice]] · [[Web-EYO-Sitio-Personal]] · [[Productividad-Ori]]

**Esta nota es distinta a todas las demás de esta carpeta**: las demás documentan el *porqué* de las decisiones de Bestoic. Esta documenta algo más simple y más urgente — **¿el código de cada proyecto está a salvo de perderse?** — para los 4 repos que este asistente toca habitualmente, no solo Bestoic. Se actualiza cada vez que se revisa el estado real (no asumido) de los 4.

**Importante para no confundir**: esta carpeta de Obsidian (`docs/obsidian/`) es solo documentación — notas sobre el sistema. **No es una copia del código**. La única copia real y segura del código es: (1) el disco local, y (2) el historial de Git una vez commiteado, y recién (3) a salvo de verdad cuando ese historial está además **subido** a GitHub (un commit local, sin subir, se pierde igual si se rompe la compu).

## Última revisión: 2026-09-03

| Proyecto | Carpeta | Working tree | Commiteado localmente | Subido a GitHub |
|---|---|---|---|---|
| **Bestoic** | `D:\Ori\EYO` | Limpio | Sí | ✅ Sí — al día |
| **Productividad Ori** | `D:\Ori\productividad-ori` | Limpio | Sí | ✅ Sí — al día |
| **Finanzas Ori** | `D:\Ori\finanzas-ori` | Limpio | Sí | ✅ Sí — al día |
| **Webeyo (sitio personal + hostal)** | `D:\Ori\webeyo` | Limpio | Sí | ⚠️ **No** — 3 commits sin subir (ver abajo) |

## El pendiente real: Webeyo

El repo local `D:\Ori\webeyo` tiene el remoto `origin` apuntando a `github.com/manuelfestaori-star/webeyo` — **una cuenta de GitHub con un problema de permisos conocido y no resuelto** (documentado en [[Web-EYO-Sitio-Personal]]: se migró la publicación en vivo a otra cuenta por esto mismo, pero el repo local nunca se volvió a apuntar a otro lado). Intentar `git push origin main` da `403 Permission denied` — no es un problema nuevo de hoy, ya estaba así.

**3 commits están a salvo en el disco local (protegidos en el historial de Git), pero no en ningún servidor:**
- `137c7c0` — fotos nuevas de Grande/Medio/Nueva, sección Antes/Después, arreglo de overflow móvil (de hace varios días, recién descubierto sin subir el 2026-09-03).
- `88756bf` — corrección de la sección Antes/Después.
- `56536a6` — arreglo del formulario de contacto (WhatsApp) + el mismo reemplazo de fotos (2026-09-03).

**Qué falta para que esto quede realmente a salvo**: como con Bestoic, hace falta un token de acceso generado desde una sesión de GitHub logueada con la cuenta correcta — pero acá la complicación es mayor, porque ni siquiera está claro cuál es "la cuenta correcta" para este repo puntual (recordar que hay 3 cuentas reales: `alojamietoeyo-maker`, `orielesymama-cyber`, `webdelhotelcom` — ninguna es `manuelfestaori-star`, que parece ser una cuarta, más vieja, con la que ya no se tiene acceso). Las opciones reales:
1. Recuperar el acceso a `manuelfestaori-star` (si se tiene el email/contraseña original).
2. Cambiar el remoto `origin` de este repo local para que apunte a un repo nuevo, en una cuenta con acceso real (ej. `webdelhotelcom`, ya que ahí vive el repo de publicación real `webdelhotelcom.github.io`) — hay que decidir esto con el usuario antes de tocar la configuración del repo, no es una decisión puramente técnica.

## Cómo volver a revisar esto

Correr en cada carpeta: `git status --short` (trabajo sin commitear) y `git log --oneline <remoto>/<rama>..<rama>` (commits commiteados pero no subidos). Si cualquiera de las dos da resultado, ese proyecto tiene algo en riesgo real de perderse.
