# Configurador "Armá tu Bestoic"

Ver también: [[00-Indice]] · [[Estado-actual]] · [[Pago-Sena-Plan-MercadoPago]] · [[Rediseno-Visual-Publico-2026-09]]

Reemplazo completo (2026-09-04) de la vieja sección `#comparacion` de
`software.html` (4 paneles fijos + tabla comparativa estática) por un
configurador real: el cliente arma su propio plan eligiendo módulos de un
catálogo, ve el precio actualizarse en vivo, compara contra 5 competidores
reales y paga la seña directo desde ahí.

## Por qué existe

Antes, "Plan Inicial/Profesional/Hotel" eran combos fijos de funciones. El
usuario quería que el cliente arme su propio Bestoic dentro de un cupo de
módulos por plan — más parecido a cómo se vende de verdad (cada alojamiento
necesita cosas distintas) y más honesto que forzar un combo que no encaja.

## Modelo comercial (decidido con el usuario, no inventado)

- **Bestoic Core** — incluido siempre, en los 3 planes, nunca se puede sacar
  y no consume cupo: Calendario/disponibilidad, Reservas y huéspedes, Señas
  y saldos, Ingresos y gastos, Panel/resumen general, Copias de seguridad.
- **Cupo de módulos, no lista fija** — cada plan compra Core + un número de
  módulos del catálogo de 17 (`MODULES.length`, nunca un literal a mano) a
  elección del cliente:

| Plan | Precio | Alojamientos | Usuarios | Módulos incluidos |
|---|---|---|---|---|
| Emprendedor (antes "Inicial") | USD 150, sin condición de suba futura en el código | 5 | 1 | 3, a elección |
| Profesional | USD 500 | 15 | 3 | 6, a elección + Apariencia y marca propia incluida (no consume cupo) |
| Hotel | Desde USD 750, cotización | Según operación | Según operación | Sin cupo fijo — arma la config para pedir cotización por WhatsApp, nunca botón de pago |

- Excedente de módulos/alojamientos/usuarios en Emprendedor/Profesional se
  cobra aparte (`EXTRA_MODULE_PRICE_USD`/`EXTRA_PROPERTY_PRICE_USD`/
  `EXTRA_USER_PRICE_USD`) — **las 3 constantes siguen en `null`** a propósito
  (decisión comercial que el usuario todavía no tomó). Mientras sigan sin
  definir, cualquier configuración con excedente pierde el botón de Mercado
  Pago y muestra solo "Consultar por WhatsApp" con el detalle armado
  dinámicamente — nunca se cobra un monto inventado ni parcial.
- Plan "Desarrollo Personalizado" (USD 1.000) **se eliminó** — lo reemplaza
  un CTA de WhatsApp genérico dentro del propio catálogo ("¿necesitás algo
  que no está?").
- Presets recomendados, fijos por plan (sin cuestionario adaptativo — ver
  hoja de ruta abajo): Emprendedor 3, Profesional 6, Hotel 10 — todos
  intercambiables por cualquier otro módulo sin costo mientras no se supere
  el cupo. Botones **"Usar recomendada" / "Elegir mis módulos"**, nunca
  presentando lo recomendado como obligatorio.

## Seguridad de precio — la regla no negociable de todo el proyecto

El total nunca lo decide el navegador. `netlify/functions/mp-plan-order.js`
recalcula todo desde su propia copia de `PLANS`/`MODULES`: valida que el
`plan` sea uno de los 3 reales, que cada módulo elegido exista en el
catálogo del servidor, que no haya duplicados, que ningún módulo
auto-incluido (`personalizacion` en Profesional/Hotel) venga marcado como
"elegido" para inflar el cupo, y rechaza con 400 explícito cualquier
configuración con excedente mientras los 3 precios de extra sigan sin
definir. El `localStorage`/DevTools del cliente es solo UX, nunca fuente de
verdad — mismo criterio que ya regía el resto del panel (`esc()`, permisos
server-side, etc.).

## Comparación de competencia + calculadora

Datos reales de 5 competidores (Predia, Pxsol, Lodgify, Smoobu, Guesty),
verificados por el usuario el 2026-09-04, con disclaimer obligatorio visible
siempre (nunca dentro de un accordion colapsado) y sin mezclar monedas
(Smoobu/Guesty son EUR, el resto USD — nunca sumados entre sí). Calculadora
de costo a 1/2/3 años: Bestoic paga una sola vez, cada competidor se
proyecta a su tarifa mensual real × 12/24/36, respetando su condición de
facturación (ej. Lodgify Professional se factura anual, no mensual).

## Persistencia y deep-linking

`localStorage` (`bestoic_configurator_v1`) guarda plan + módulos elegidos +
extras entre visitas — primer uso de `localStorage` en este archivo.
`software.html?plan=X#comparacion` preselecciona un plan desde un link
externo (ej. desde `index.html`) — **el query string va antes del `#`**,
nunca después (`location.search` no ve nada que esté en el fragmento); esto
fue un bug real que el propio usuario detectó antes de que se implementara.

## Estado

Implementado y verificado en vivo (2026-09-04): las 3 configuraciones
recomendadas cierran exacto contra su cupo, el gating Mercado Pago↔WhatsApp
funciona según haya o no excedente, `localStorage` restaura la selección al
recargar, responsive probado en mobile (bottom-sheet del resumen) y
desktop. Migración `0056` (renombre de `plan='inicial'` a `'emprendedor'`)
aplicada. Reskin visual del propio configurador (colores, espaciado,
sombras) se hizo al día siguiente como parte de [[Rediseno-Visual-Publico-2026-09]] — sin tocar su lógica.

## Hoja de ruta explícita, no iniciada

- **Cuestionario adaptativo** (3-4 preguntas que ajustan la recomendación
  según el tipo de negocio) — pedido explícitamente diferido por el usuario
  a una fase 2.
- Definir los 3 precios de excedente (`EXTRA_MODULE_PRICE_USD`/
  `EXTRA_PROPERTY_PRICE_USD`/`EXTRA_USER_PRICE_USD`) — desbloquea el botón
  de Mercado Pago también para configuraciones con excedente.
- Videos explicativos reales por módulo (el mecanismo de "Ver cómo
  funciona" ya existe, ningún módulo tiene video cargado todavía).
