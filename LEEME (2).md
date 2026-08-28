> ## ⚠️ HISTÓRICO — este documento describe la demo vieja (localStorage), no el sistema actual
> Bestoic ya no es un conjunto de archivos HTML sueltos con `localStorage` y usuario/contraseña
> `admin`/`1234`. Hoy es un sistema real en `app/panel.html`, con autenticación real y base de datos
> en Supabase (multi-cliente, con permisos por rol aplicados en el servidor). Este archivo queda como
> referencia histórica de cómo era la demo original — **ver `README.md` en la raíz del repositorio
> para la documentación vigente.**

# Bestoic — Archivos finales

Todo quedó en **archivos únicos**: cada uno lleva adentro el diseño, el código y las imágenes.
No hay carpetas ni archivos sueltos que dependan uno del otro.

---

## LOS ARCHIVOS

### Sitio web (2 archivos)

| Archivo | Qué es |
|---|---|
| `index.html` | Página principal |
| `software.html` | Página de funciones y planes |

Los dos deben estar **en la misma carpeta** para que funcione el enlace entre ellos.

### Aplicación (3 versiones del mismo software)

| Archivo | Plan | Alojamientos | Módulos |
|---|---|---|---|
| `Panel-EYO-Plan-Inicial.html` | Inicial | hasta 5 | 8 |
| `Panel-EYO-Plan-Profesional.html` | Profesional | hasta 15 | 12 |
| `Panel-EYO-Plan-Hotel.html` | Hotel Uruguay | sin límite | 13 (incluye Facturación DGI) |

Se entra con usuario **admin** y contraseña **1234**.

---

## PARA VERLO EN TU COMPUTADORA

Descargás los archivos, los ponés en una carpeta y hacés **doble clic**. Se abren en el navegador.
No necesitás internet ni instalar nada.

Para ver cómo queda en el celular: apretá **F12** en el navegador y tocá el ícono de celular.

---

## PARA SUBIR EL SITIO A GITHUB PAGES

1. Entrá a tu repositorio `webeyo`.
2. **Add file → Upload files**.
3. Arrastrá `index.html` y `software.html`.
4. **Commit changes**.
5. Esperá 1 o 2 minutos y abrí `https://manuelfestaori-star.github.io/webeyo/`.

> Borrá los archivos viejos del repositorio (como `software-eyo.html`) para que no queden
> dos versiones dando vueltas con precios distintos.

---

## CÓMO CAMBIAR COSAS

Abrí el archivo con el Bloc de notas y buscá con **Ctrl + F**.

### El número de WhatsApp
Buscá `WHATSAPP_NUMBER`. Está una sola vez en cada página:

```javascript
const WHATSAPP_NUMBER = '59891733054';
```

Código de país + número, sin `+`, sin espacios y sin guiones.
Cambiándolo se actualizan todos los botones, el botón flotante y el formulario.

### El tipo de cambio USD → UYU
Buscá `exchangeRate`:

```javascript
const exchangeRate = 41;
```

Cambiás ese número y **todos** los precios en UYU se recalculan solos.

### Los precios
Buscá `data-usd`. Los precios están así:

```html
<span class="usd" data-usd="150"></span>   <!-- se ve: USD 150 -->
<span class="uyu" data-uyu="150"></span>   <!-- se ve: UYU 6.150 -->
```

Si cambiás un precio, hacelo en **los dos archivos** (`index.html` y `software.html`).

Precios actuales:
- Plan Inicial: **USD 150** de lanzamiento (primeros 3 clientes), luego **USD 175**
- Plan Profesional: **USD 300**
- Plan Hotel Uruguay: **desde USD 500** (cotización)
- Forma de pago: **50% para comenzar y 50% al entregar**

### El video
Buscá `PEGAR_ID_YOUTUBE` (está en las dos páginas).

- **YouTube:** si la dirección es `youtube.com/watch?v=AbC123xyz`, poné `AbC123xyz` en lugar de `PEGAR_ID_YOUTUBE`.
- **Archivo propio:** cambiá `data-video-yt="PEGAR_ID_YOUTUBE"` por `data-video-mp4="mi-video.mp4"` y subí el video a la misma carpeta.

El video no se carga hasta que la persona toca reproducir, y nunca arranca solo con sonido.

### El límite de alojamientos de la app
Buscá `PLAN_MAX` en cualquiera de los 3 archivos de la app:

```javascript
const PLAN_MAX = {inicial:5, profesional:15, hotel:Infinity};
```

### Sacar las 3 versiones de la app desde una sola
Trabajá siempre sobre `Panel-EYO-Plan-Hotel.html` (es la completa).
Para generar las otras dos, buscá esta línea y cambiá la palabra:

```javascript
const PLAN='hotel';     // cambiar por 'inicial' o 'profesional'
```

Así mantenés **un solo** código y no se te desincronizan.

---

## LO QUE TODAVÍA FALTA COMPLETAR

Buscá la palabra `COMPLETAR` en `index.html` para encontrar estos puntos.

1. **El comentario de Elsa.** La tarjeta de testimonio tiene un recuadro punteado que dice
   `FALTA COMENTARIO`. **No publiques la página con ese recuadro visible.**
2. **El video** de 90 segundos (y el completo, en `software.html`).
3. **Cantidad de alojamientos gestionados** — hoy dice 8.
4. **Años de experiencia** — hoy dice 4+.
5. **Imagen para compartir en redes** (1200 × 630 px): buscá `og-cover.jpg`.
6. **Política de privacidad y Términos** en el pie de página (los enlaces están vacíos).
7. **Capturas de Usuarios y de la vista en celular** (las demás ya están puestas).

---

## DECISIONES QUE CONVIENE RECORDAR

- **No se muestran medios de pago** (Visa, Mastercard, etc.) porque todavía no hay una pasarela
  funcionando. Se aclara que se coordinan por WhatsApp.
- **No se afirma que exista facturación electrónica DGI.** El módulo existe en la app, pero no emite
  un comprobante con validez fiscal por sí solo, así que no se promete en la web.
- **No se promete sincronización** con Booking ni Airbnb: solo se registra de qué canal vino la reserva.
- **No hay testimonios inventados.** Solo el de Elsa, cuando esté su comentario.
- Se habla de **"mejora y optimización digital de fotografías"**, no de fotografía profesional.
- El Perfil de Empresa en Google se ofrece **sujeto a la verificación de Google**.
- En la captura de Propietarios, los teléfonos y correos están **desenfocados** a propósito.

---

## VERIFICACIONES YA HECHAS

- Sin desplazamiento horizontal en 320, 360, 390, 430, 768, 1024 y 1440 píxeles.
- El encabezado fijo no tapa las secciones.
- El botón de WhatsApp no tapa el formulario.
- El menú del celular abre, cierra al elegir una opción y se cierra con Escape.
- El formulario valida los campos y arma el mensaje de WhatsApp.
- Todos los enlaces internos y entre las dos páginas funcionan.
- Contraste de colores conforme a WCAG AA.
- Sin errores de JavaScript en ninguna página.
- Las 3 apps: límite de alojamientos funcionando, impresión del resumen mensual corregida.
