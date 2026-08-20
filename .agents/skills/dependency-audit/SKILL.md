---
name: dependency-audit
description: Revisar las dependencias externas de Software EYO (librerías CDN, cliente Supabase JS, y las del motor Python del bot de mercado) por versiones desactualizadas, vulnerabilidades conocidas, o costos nuevos. Usar ante pedidos como "revisá las dependencias", "¿hay alguna librería vieja o insegura?", o antes de agregar cualquier paquete/servicio nuevo al proyecto.
---

# Auditoría de dependencias — Software EYO

## Regla de negocio que manda sobre esto

El usuario pidió explícitamente **evitar servicios pagos o costos
mensuales salvo que sean estrictamente necesarios, y avisar antes** de
sumar cualquiera. Cualquier dependencia nueva (librería, servicio, API)
que implique un costo recurrente potencial se marca y se consulta ANTES
de agregarla — no se asume "el free tier alcanza para siempre".

## Superficie real de dependencias (dos proyectos distintos)

### Software EYO (`app/panel.html`) — sin bundler, sin `package.json`
Todo vía CDN, cargado directo en el HTML:
```
grep -n "cdn.jsdelivr.net\|cdnjs.cloudflare.com\|<script src=" app/panel.html
```
Librerías conocidas en uso: cliente Supabase JS, Chart.js, jsPDF, XLSX
(SheetJS), Tabler Icons (fuente de íconos). Revisar:
- ¿Están pineadas a una versión específica en la URL, o apuntan a
  `@latest`/sin versión? Sin versión = un cambio breaking upstream puede
  romper producción sin ningún commit de este lado.
- El CSP en `app/_headers` (`script-src`/`style-src`/`font-src`) solo
  permite `cdn.jsdelivr.net` y `cdnjs.cloudflare.com` — cualquier
  dependencia nueva de otro dominio necesita agregarse ahí también, y es
  una superficie de confianza nueva (ese CDN puede servir código
  arbitrario si se compromete).
- ¿La librería nueva tiene versión gratuita real, o es un trial/freemium
  que después empieza a cobrar? Confirmar con el usuario antes de sumarla.

### Bot de precios (`D:\Ori\bot-precios-alojamientos`) — Python
```
cat requirements.txt   # playwright, pandas, reportlab
```
- `playwright`: instala su propio Chromium — verificar que
  `playwright install chromium` esté documentado en el manual de
  instalación/instalador (Fase 6 del proyecto EYO Market, si ya se llegó
  ahí), porque sin eso el motor no arranca en una PC nueva.
- Ninguna de las tres (`playwright`, `pandas`, `reportlab`) tiene versión
  paga — está bien así, no cambiar por una alternativa de pago sin
  consultarlo.
- El agente local (`agente_local.py`) usa solo `http.server` de la
  librería estándar de Python — **a propósito, para no sumar Flask/FastAPI
  como dependencia nueva**. Si en algún momento se propone migrar a un
  framework, evaluar si de verdad hace falta antes de sumar la dependencia.

## Qué NO se debe agregar sin preguntar primero

- Cualquier API de pago (incluyendo tiers "gratis hasta cierto uso" que
  después cobran).
- Cualquier reemplazo de Supabase/Netlify por otro proveedor.
- Cualquier librería de IA/LLM — el proyecto tiene la regla explícita de
  no usar IA en el motor de precios ni en ningún cálculo del negocio.

## Ejecución manual

`/dependency-audit` — lista las dependencias actuales de ambos proyectos,
señala versiones sin pinear o directamente vulnerables si se conocen, y
marca cualquier costo potencial antes de que se sume algo nuevo.
