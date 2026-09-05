# Rediseño visual y comercial del sitio público (2026-09-05)

Ver también: [[00-Indice]] · [[Estado-actual]] · [[Configurador-Arma-tu-Bestoic]] · [[Personalizacion]]

Reorganización de `index.html` y `software.html` (marketing público, no el
panel) en un recorrido de scroll único y más liviano, inspirada
conceptualmente en la simplicidad de agrocloud.com.uy — **nunca copiando su
contenido, gráficos ni estructura**, solo la sensación de aire/orden.

## Decisión de paleta (dada explícitamente por el usuario)

Se mantiene azul marino + naranja (identidad de marca), pero con una
proporción de uso fija: **80-85% blanco/gris muy claro, 10-15% azul marino,
5% naranja/acento**. Azul marino reservado para títulos, iconos, navegación
y elementos de marca — nunca más como fondo de secciones completas salvo el
header/footer y una única franja de CTA final. Naranja reservado para CTAs,
estados activos y puntos importantes — nunca decorativo suelto.

## Qué cambió de estructura

`index.html` pasó a seguir un único recorrido: hero → beneficios → funciones
(resumen de 4 áreas) → demo → cómo funciona → planes → pago único →
comparación (teaser) → confianza → historia → FAQ → CTA final → footer.
`software.html` sigue siendo la página de "profundizar" (catálogo completo
de 14 categorías de funciones, capturas, FAQ de 20 preguntas) — **conserva
intacto el configurador "Armá tu Bestoic"** ([[Configurador-Arma-tu-Bestoic]]),
solo se le aplicó el mismo reskin visual (espaciado, sombras, colores), cero
cambio de lógica/precio.

Se agregó un sistema de scroll-reveal (`initScrollReveal()`,
`IntersectionObserver`, respeta `prefers-reduced-motion`) — primer uso de
microinteracción de este tipo en el sitio. Se excluyó deliberadamente de
las tarjetas de módulo del configurador y del resumen (se re-renderizan en
cada interacción; animarlas de nuevo cada vez habría producido parpadeo).

## Qué NO se tocó, a propósito

- **`#testimonios` sigue oculto** (`hidden`) — la única tarjeta real tiene el
  texto literal "FALTA COMENTARIO" en vez de una cita real. No se inventó
  ningún testimonio para llenar el hueco.
- Capturas de pantalla de `#capturas` (12 espacios) siguen como placeholder
  honesto ("Captura en actualización") — no hay capturas reales todavía.
- El video de demo sigue con `PEGAR_ID_YOUTUBE` como placeholder — no se
  inventó ningún ID de YouTube real.
- Screenshot real del panel en el hero, stats/fotos de alojamientos reales,
  y las 2 tarjetas "Foto próximamente" ya honestas — todo reusado tal cual,
  nunca reemplazado por contenido inventado.

## Desviaciones señaladas explícitamente (juicio propio, corregible)

- El header quedó siempre navy (nunca "blanco translúcido al hacer scroll"
  como decía la letra literal del pedido original) — prioricé la
  instrucción más específica y posterior del usuario, que asignó
  explícitamente navy a "navegación".
- Se mantuvo el orden "Planes" antes de "Cómo funciona" (orden preexistente
  del archivo) en vez del orden numerado exacto del pedido — desviación
  menor, señalada, no corregida sin pedirlo.
- La comparación de competencia en `index.html` es un teaser corto (2-3
  mini-tarjetas) en vez de duplicar la tabla completa de `software.html` —
  para no mantener el mismo array de competidores en dos archivos.

## Estado

Implementado y verificado en el Browser tool (2026-09-05): responsive en
390/430px y desktop, sin desborde horizontal, historia-modal abre/cierra
bien, comparación-teaser con datos reales, consola limpia. **Pendiente de
deploy** — mismo bloqueo que el resto de esta sesión (Netlify pausado, ver
[[Estado-actual]]) y de un `git push`/commit explícito (no se publica nada
sin un "dale" en el momento).

## Pendiente de asset real (no bloqueante para el resto)

Capturas de `software.html#capturas`, ID real de YouTube del video de demo,
testimonio real de un cliente (Elsa u otro) para destapar `#testimonios`.
