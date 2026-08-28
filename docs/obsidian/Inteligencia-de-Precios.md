# Inteligencia de Precios (beta)

Ver también: [[00-Indice]] · [[Arquitectura]] · [[Seguridad]] · [[Modulos]] · [[Estado-actual]]

Agregado el 2026-08-03, Fase 1 de un desarrollo por etapas. Ayuda al propietario/administrador a decidir cuánto cobrar por noche, comparando contra competidores cargados a mano o por CSV — sin ninguna API paga ni scraping.

## Qué es Fase 1 y qué no

**Sí construido y probado en vivo:** feature flag por plan, permisos separados, catálogo de alojamiento propio, grupos de competidores, carga manual y CSV, puntuación de similitud, estadística con percentiles, motor de recomendación con 4 estrategias, explicación del cálculo, nivel de confianza, piso de precio mínimo rentable, registro de la decisión del usuario (aceptar/rechazar/etc).

**Deliberadamente NO en Fase 1** (para no entregar algo a medio construir sin probar): calendario de precios (vista mensual), simulador interactivo, alertas automáticas, historial/evolución con gráficos, aprendizaje a partir de reservas propias. El esquema de base de datos ya está pensado para soportarlas después (`market_searches`/`market_snapshots`/`price_recommendations` separados justamente para poder mostrar evolución más adelante) — no van a requerir rehacer lo ya construido, solo agregar sobre esta base.

## Arquitectura de proveedores de datos

`market_data_sources` es un catálogo honesto: cada fuente tiene `available` (true/false) según si realmente está conectada, no según lo que se planea a futuro.

| Fuente | `available` | Estado real |
|---|---|---|
| Carga manual | true | Funciona desde el día uno. |
| Importar CSV | true | Funciona desde el día uno. |
| Datos de demostración | true | Para probar la interfaz — el frontend no la usa todavía como fuente real de análisis; queda en el catálogo preparada. |
| Booking.com (oficial) | **false** | Requiere acceso autorizado — ver más abajo. |
| Airbnb (oficial) | **false** | Requiere acceso autorizado — ver más abajo. |

Cuando una fuente no está conectada, el panel muestra: *"Esta fuente todavía no está conectada. Puedes ingresar datos manualmente o importar un archivo."* — nunca se inventa un precio para rellenar.

## Feature flag y permisos (server-side, no solo en pantalla)

- `plan_config.pricing_intelligence_enabled` — hoy `true` solo para `hotel`. Cambiarlo a futuro para `profesional` es una fila de base de datos, no un redeploy de código.
- `has_pricing_intelligence()` — función que resuelve el flag según el tenant del usuario logueado. **Toda** política RLS del módulo la exige, además del permiso puntual.
- 9 permisos nuevos en el catálogo existente (mismo mecanismo que el resto del sistema — ver [[Seguridad]]): `ver_analisis_precios`, `crear_analisis_precios`, `importar_datos_precios`, `modificar_competidores_precios`, `configurar_precio_minimo`, `aceptar_recomendaciones_precios`, `administrar_fuentes_precios`, `ver_historial_precios`, `exportar_precios`.
- **Hallazgo real de la prueba en vivo:** las políticas de SELECT originales (migración 0025) solo exigían el plan, no el permiso `ver_analisis_precios` — un empleado sin ese permiso podía igual leer los competidores cargados. Se probó con un usuario `limpieza` real, se confirmó el problema, y se corrigió en la migración `0026` en la misma sesión. Quede como recordatorio: agregar un permiso al catálogo no sirve de nada si ninguna política lo usa — hay que verificarlo probando, no asumirlo.

## Similitud de competidores

`computeSimilarity()` en `app/panel.html` compara el alojamiento propio (`pricing_property_config`) contra cada competidor, sumando puntos solo cuando **ambos lados tienen el dato cargado** (si falta el dato, simplemente no suma ni resta — no inventa una coincidencia ni una diferencia):

| Atributo | Puntos máximos |
|---|---|
| Tipo de alojamiento | 20 |
| Capacidad (±1 = completo, ±2 = parcial) | 15 |
| Baño privado | 10 |
| Aire acondicionado | 10 |
| Cocina | 5 |
| Estacionamiento | 5 |
| Distancia al centro (≤1km/≤3km/≤6km) | 15 |
| Puntuación (±0.3/±0.8) | 15 |
| Cancelación gratuita + desayuno | 5 |

El resultado se normaliza sobre el máximo realmente evaluable (si al alojamiento propio le falta la puntuación cargada, ese ítem no cuenta ni para bien ni para mal) y se muestra como texto legible, ej: *"Similitud: 87/100. Es comparable por tipo de alojamiento, capacidad, baño privado y aire acondicionado."* Por defecto, solo entran al cálculo estadístico los competidores con similitud ≥65 — probado en vivo con una habitación compartida (13/100, correctamente excluida).

## Estadística y exclusión de atípicos

Sobre los precios por noche normalizados (`precio_final ?? precio_total`, dividido por noches) de los competidores válidos:
- Percentiles 10/25/50(mediana)/75/90, mínimo, máximo, promedio.
- Exclusión de atípicos por rango intercuartílico (IQR): fuera de `[P25 − 1.5·IQR, P75 + 1.5·IQR]`, solo si hay 4+ muestras. **Los valores excluidos se muestran, no se esconden** (`excluded_count` en `market_snapshots`).
- Disponibilidad estimada: porcentaje de "disponible=sí" **solo sobre los competidores con dato de disponibilidad conocido** — nunca se afirma un porcentaje sobre toda la zona.

## Motor de recomendación

Precio base según la estrategia elegida:

| Estrategia | Precio base |
|---|---|
| Ganar reservas | Percentil 25 |
| Equilibrado | Mediana |
| Maximizar ingresos | Percentil 75 (sube a P90 si faltan ≤3 días y la disponibilidad estimada es <40%) |
| Personalizado | El precio que el usuario quiera evaluar |

Después: se ajusta (nunca hacia abajo sin avisar) al `precio_minimo_rentable` configurado, y hacia abajo al `precio_maximo_recomendado` si existe. Si el ajuste por mínimo se aplicó, `limitado_por_minimo=true` y se muestra el aviso explícito — probado en vivo forzando un mínimo por encima de lo que recomendaría el mercado libre.

Confianza (`alta`/`media`/`baja`/`insuficiente`) según: cantidad de muestras válidas, % con impuestos desconocidos, % con datos de más de 48hs, dispersión de precios. Con menos de 3 muestras válidas, no se genera recomendación — se muestra: *"No existen suficientes datos fiables para generar una recomendación. Agrega más competidores o actualiza la información."*

Cada recomendación queda persistida (`market_searches` + `market_snapshots` + `price_recommendations`, las tres tablas, no solo en pantalla) con motivos, riesgos, y la sección "¿Cómo se calculó?" mostrando cada número intermedio.

"Aceptar recomendación" actualiza `price_recommendations.precio_aplicado` (un registro interno) — **no publica nada en Booking ni Airbnb**, no hay integración de escritura hacia afuera todavía.

## Pasos pendientes para conectar Booking.com oficialmente

1. Postular como partner en el programa de Connectivity Partners de Booking.com (no es autoservicio — requiere aprobación de Booking).
2. Una vez aprobado, obtener credenciales de la Demand API o Connectivity API según el caso de uso (consultar precios/disponibilidad de mercado vs. gestionar el propio inventario son productos distintos).
3. Revisar los límites de uso y el alcance de datos que la API realmente expone (no toda la información que un usuario ve en la web de Booking está disponible por API).
4. Implementar `BookingAuthorizedProvider` detrás de una función de servidor (nunca credenciales en el navegador) y recién ahí cambiar `market_data_sources.available` a `true` para esa fila.

## Pasos pendientes para conectar Airbnb oficialmente

1. Airbnb no tiene una API pública de datos de mercado — el acceso es mediante programas de partners de software certificados (Preferred Partner / Software Partner Program), con proceso de aprobación propio.
2. Evaluar si el caso de uso (comparación de precios de mercado) encaja en algún programa vigente de Airbnb al momento de implementarlo — puede no existir un producto que lo permita.
3. Igual que Booking: nunca credenciales en el navegador, todo detrás de una función de servidor.

## Servicios externos y costos

Ninguno nuevo. Todo corre sobre el mismo proyecto Supabase (base de datos + RLS) y el mismo sitio Netlify que ya usaba el resto de Bestoic. El cálculo de similitud/estadística/recomendación corre en el navegador (JavaScript), no requiere ningún servicio de cómputo aparte.

## Limitaciones actuales

- Sin calendario, simulador, alertas ni historial visual (Fase 2 en adelante).
- La similitud y la estadística son reglas transparentes, no aprendizaje automático — a propósito, para que cada número se pueda explicar.
- Sin conexión real a Booking/Airbnb — solo carga manual y CSV por ahora.
- No hay todavía una segunda versión limitada para Plan Profesional (el flag ya está preparado para habilitarlo, pero el alcance reducido — "menos competidores, carga manual limitada" — no está implementado).
