# Productividad Ori

Ver también: [[00-Indice]] · [[Historia-y-decisiones]] · [[Estado-actual]]

**Proyecto aparte, séptimo producto EYO, de uso personal (no comercial).** No es Software EYO Alojamientos ni comparte código, base de datos ni repositorio con él. Es una aplicación de productividad personal para Orieles: planificar el día/semana, cronometrar actividades reales, y medir cuánto tiempo dedica a trabajo, estudio, gimnasio y vida personal contra lo planificado.

## Qué es, en una frase

Un "sistema operativo personal" para administrar el tiempo: **Planificar → Ejecutar → Registrar → Medir → Analizar → Mejorar.** Combina calendario, cronómetro con persistencia real (sobrevive a cerrar el navegador/bloquear el celular), presupuesto de tiempo por categoría, objetivos semanales, y un módulo de gimnasio con series/repeticiones/volumen — todo con estadísticas comparativas semana a semana, calculadas desde datos reales, sin inventar ni usar IA para lo que se resuelve con cálculo normal.

## Estado (2026-08-20)

**MVP + Fase 2 completos — no queda nada pendiente del prompt maestro.** Las 12 fases del MVP y las 12 funcionalidades de Fase 2 están construidas, verificadas en vivo con usuarios de prueba reales, y publicadas en producción: **https://productividad-ori.netlify.app**. Repo local en `D:\Ori\productividad-ori` (Next.js App Router + TypeScript + Tailwind CSS v4 + `@supabase/ssr`), todavía sin remoto en GitHub. 12 commits locales.

### Scaffold y diseño
- Sistema de diseño (tokens de color claro/oscuro, tarjetas, barras de progreso) y layout responsive: sidebar en escritorio, barra inferior en celular con botón central "+".
- Modo claro/oscuro con toggle persistente (`localStorage`) y sin parpadeo (script inline antes del primer paint) — se encontró y corrigió un error real de hidratación de React durante la verificación (el estado inicial del toggle no coincidía entre servidor y cliente cuando ya había un tema guardado).
- Dashboard principal construido siguiendo el mockup exacto del prompt maestro (sección 101): actividad activa con cronómetro en vivo, próxima actividad, objetivo diario con barra de progreso, resumen del día por categoría, listado cronológico con estados. Todavía con datos de demostración (no conectado a datos reales) — eso es la próxima fase (Categorías/Proyectos → Actividades).

### Supabase — proyecto y esquema
- **Proyecto nuevo creado:** `productividad-ori`, dentro de la misma cuenta/organización de Supabase que ya tiene Software EYO (`SoftwareEYO`), pero como proyecto separado — nunca se mezclan los datos personales con los de los clientes del hotel. Creado vía API con un token de gestión (`sbp_...`) que el usuario generó, en vez de hacerlo a mano por el dashboard.
- **Esquema completo:** 15 tablas (`profiles`, `user_preferences`, `categories`, `subcategories`, `projects`, `activities`, `timer_sessions`, `goals`, `time_budgets`, `tasks`, `workouts`, `exercises`, `workout_exercises`, `exercise_sets`, `weekly_templates`), migraciones `0001`-`0007` en `supabase/migrations/`, corridas directo contra la base vía la Management API de Supabase (mismo token) — no hizo falta pegar nada a mano en el SQL Editor.
- RLS activado y verificado (`rowsecurity = true`) en las 15 tablas, con políticas por `user_id`. Restricciones de integridad reales (no duraciones negativas, fin no puede ser antes que el inicio, rating de concentración/energía entre 1 y 10, etc.), índices en `user_id`/fechas/FKs, y una restricción única que impide dos sesiones de cronómetro activas para la misma actividad.
- Trigger `handle_new_user()` sobre `auth.users`: crea automáticamente `profile` + `user_preferences` al registrarse — verificado en vivo (usuario de prueba creado por API, se generaron sus filas solas, después se borró todo).

### Autenticación real
- Registro, login, cerrar sesión, recuperar/actualizar contraseña — server actions de Next.js sobre Supabase Auth, sin credenciales hardcodeadas.
- Layout reorganizado en dos grupos: `(app)` con el shell completo (sidebar/bottom nav), protegido server-side — sin sesión redirige a `/login`; y `(auth)` con un layout mínimo centrado para las pantallas de login/registro.
- Middleware que refresca el token de sesión en cada request.
- **Caso real encontrado y corregido:** el proyecto nuevo de Supabase exige confirmar el correo antes de habilitar sesión — `signUp()` no devuelve error en ese caso, solo no viene con sesión. La primera versión asumía que registro = sesión inmediata y rebotaba en silencio a `/login` sin explicación; se corrigió para mostrar "confirmá tu correo" cuando corresponde.
- Verificado en vivo de punta a punta con un usuario de prueba (creado y confirmado por API para no depender del email real durante la prueba, borrado al terminar): registro, login, ruta protegida, perfil mostrando el correo real, logout.

### Deploy (completado)
- **Decisión final sobre Netlify — cambió durante la sesión:** originalmente el usuario había pedido una cuenta nueva y separada de `webdelhotelcom` para no arriesgar el panel del hotel si esta app personal agotara créditos compartidos (Netlify pausa TODOS los sitios de una cuenta si eso pasa). Sobre el final, el usuario decidió explícitamente lo contrario — usar la cuenta/organización `SoftwareEYO` ya existente — y confirmó por segunda vez que entendía y aceptaba ese riesgo compartido antes de seguir. Se dejó registrado así por si en el futuro hay que revisar esa decisión.
- **Sitio creado:** proyecto nuevo `productividad-ori` dentro de la organización `SoftwareEYO` de Netlify, publicado en **https://productividad-ori.netlify.app**. `netlify.toml` con el plugin oficial `@netlify/plugin-nextjs` (soporta Server Actions/SSR de Next.js, no es un export estático). Variables `NEXT_PUBLIC_SUPABASE_URL`/`NEXT_PUBLIC_SUPABASE_ANON_KEY` cargadas en Netlify.
- **Obstáculo encontrado y resuelto:** el sitio nuevo heredó por defecto la protección SSO/de equipo de la cuenta (`sso_login` a nivel de sitio), que devolvía 401 a cualquier visitante sin sesión de Netlify — mismo tipo de bloqueo ya visto antes al publicar la página comercial de Software EYO. Se desactivó a nivel de sitio (no de cuenta) vía la API de Netlify.
- Verificado en producción real con un usuario de prueba (creado y borrado por API): registro/login funcionan, el dashboard carga con datos reales de Supabase a través de una Server Action, sin errores de consola.
- **Costos:** confirmado que ni Supabase (500 MB/5 GB/50k MAU gratis) ni Netlify (300 créditos/mes gratis, deploys a producción cuestan 15 créditos c/u, vistas previas gratis) deberían generar costo real para un solo usuario.

### Categorías, subcategorías y proyectos (completado)
- CRUD real contra Supabase (ya no son datos de demostración): categorías (nombre, color de una paleta fija, marca "productiva"), subcategorías anidadas dentro de cada categoría, y proyectos (nombre, categoría opcional, descripción, archivar/restaurar sin perder el historial).
- Nuevas pantallas `/categorias` y `/proyectos`, accesibles desde la sidebar en escritorio y desde Perfil en celular (la barra inferior no tenía espacio libre para dos ítems más).
- Verificado en vivo de punta a punta con un usuario de prueba (creado y borrado por API, igual que en Fase 1): crear categoría, agregar subcategoría, crear proyecto vinculado, archivar — y confirmado que el borrado en cascada del usuario dejó las tablas en 0 filas (las foreign keys están bien puestas).
- **Bug real encontrado y corregido:** dos formularios de edición (categoría y proyecto) llamaban directamente al dispatcher de `useActionState` como si fuera la server action cruda, intentando leer un valor de retorno que ese dispatcher no expone así. El síntoma: después de guardar una edición exitosa, el formulario nunca volvía a cerrarse solo.

### Actividades (completado)
- CRUD real: `/actividades` (lista completa, crear/editar/eliminar/cambiar estado) y `/registrar` (ahora funcional — inicio rápido desde el botón "+", antes placeholder).
- Formulario compartido con categoría → subcategoría en cascada (la subcategoría solo aparece si la categoría elegida tiene alguna) y proyecto opcional.
- Los 7 estados del prompt maestro (planificada, en progreso, pausada, completada, parcialmente completada, cancelada, no realizada), cambiables desde un selector en cada tarjeta, con color propio por estado.
- `planned_end` se calcula en el servidor a partir de inicio + duración en minutos — nunca se le pide al usuario dos campos de fecha por separado.
- Verificado en vivo de punta a punta: crear con categoría/subcategoría/proyecto vinculados, cambiar estado (persiste tras recargar), editar (confirmado que precarga todos los valores guardados, incluida la conversión de `datetime-local`), eliminar. Usuario y datos de prueba borrados al terminar, cascada confirmada en 0 filas.

### Calendario (completado)
- Vistas día/semana/mes sobre actividades reales, con selector de vista y navegación de período. La semana es la vista por defecto, como pidió el prompt maestro.
- Cada actividad se dibuja como bloque en la franja horaria correspondiente (`ActivityBlock`), con color por categoría y estado.
- Verificado en vivo: actividades sembradas en distintos días/horarios aparecen en el día, la semana y el mes correctos; responsive a 375px sin desborde (se encontró y corrigió el mismo patrón de bug que en Web EYO: un ancestro flex sin `min-w-0` dejaba que el `overflow-x-auto` interno empujara la página entera).

### Cronómetro (completado)
- Implementado el principio central del prompt maestro: nunca se acumula tiempo en estado de JavaScript. Cada actividad guarda sesiones (`timer_sessions`) con `started_at`/`ended_at` reales; el tiempo transcurrido se calcula siempre como `ahora − started_at` (mientras corre) más la suma de sesiones ya cerradas.
- Iniciar / pausar / reanudar / finalizar, con la restricción de "una sola actividad activa a la vez" reforzada tanto en la base de datos (índice único parcial `timer_sessions_one_active_per_activity`) como en la aplicación (aviso claro si ya hay otra corriendo).
- Pausar/reanudar modela cada tramo activo como una fila propia (no una sola fila con múltiples ciclos de pausa), por cómo está armado el índice único de la base.
- Verificado en vivo, incluidos los casos límite pedidos en las pruebas obligatorias del prompt maestro: iniciar → cerrar pestaña → volver a abrir (el tiempo sigue corriendo, calculado desde el timestamp real); iniciar → pausar → cerrar → volver a abrir (queda pausado, con el tiempo acumulado correcto); iniciar → trabajar → finalizar (duración final correcta).
- **Dos bugs reales encontrados y corregidos:** (1) al pausar, el tiempo acumulado se mostraba en 00:00:00 porque la consulta excluía por error la sesión recién cerrada; (2) al reanudar, el intento de insertar una nueva sesión "corriendo" chocaba en silencio con la restricción única mientras la sesión pausada anterior seguía abierta — se corrigió cerrando la sesión pausada antes de abrir la nueva, y se agregó aviso visible de error (antes se perdía sin mostrar nada).

### Dashboard principal (completado)
- Reemplazado el mockup de demostración por datos reales: actividad activa con cronómetro en vivo, próxima actividad, objetivo diario con progreso real, resumen del día por categoría, listado cronológico con estados.
- **Bug real encontrado y corregido:** el cálculo de tiempo por actividad llamaba `Date.now()` directo dentro de funciones `reduce`/`map` ejecutadas en el render de un componente de servidor, lo que el linter de React marca como impureza; se corrigió capturando el timestamp una sola vez al principio del componente y reutilizándolo.
- Verificado en vivo contra datos sembrados a mano, cifra por cifra.

### Estadísticas y gráficos (completado)
- Filtros de período (día/semana/mes), comparación planificado vs. real, gráfico de barras "Horas por día" (Recharts, con las series de tiempo por categoría) themeado con las variables de color de la app en vez de clases de Tailwind (porque Recharts pinta SVG con estilos inline).
- Verificado en vivo contra datos sembrados con horarios reales en huso horario de Montevideo (`AT TIME ZONE 'America/Montevideo'` al sembrar por SQL, para no confundir un desfase de zona horaria del dato de prueba con un bug real de la app).

### Objetivos y presupuesto de tiempo (completado)
- Objetivos semanales por categoría/proyecto y presupuesto de tiempo, con barra de progreso calculada contra el tiempo real ya registrado (no contra lo planificado).
- **Bug real encontrado y corregido:** los formularios de edición llamaban directamente al dispatcher de `useActionState` intentando leer su valor de retorno, lo cual no funciona así — mismo patrón de bug ya visto y corregido en Categorías/Proyectos; se movió la llamada real a la acción (y el cierre del formulario al tener éxito) adentro de la función reductora que se le pasa a `useActionState`.

### Módulo de gimnasio (completado)
- Entrenamientos con cronómetro propio (mismo principio de timestamps reales que el cronómetro de actividades): crear, finalizar (calcula duración real), eliminar.
- Agregar ejercicios existentes al entrenamiento o crear uno nuevo al vuelo (nombre + grupo muscular), y registrar series (peso × repeticiones) con volumen calculado por serie y total por ejercicio.
- Historial por ejercicio (`/gimnasio/ejercicios/[id]`): último set, mejor marca (mayor peso), mayor volumen en un mismo entrenamiento, y tabla completa fecha/peso/reps/volumen.
- Estadísticas de "esta semana" en la pantalla principal de Gimnasio: cantidad de entrenamientos, tiempo total y promedio, cantidad de ejercicios distintos, series por grupo muscular.
- Enlaces agregados al hub de Perfil en celular (Objetivos y Gimnasio no entraban en los 5 espacios de la barra inferior).
- Verificado en vivo de punta a punta con el ejemplo exacto del prompt maestro: 60kg×10 + 65kg×8 + 65kg×7 = 1.575 kg de volumen, coincide exacto.
- **Bug real encontrado y corregido:** el historial por ejercicio ordenaba las series solo por fecha del entrenamiento; con varias series del mismo entrenamiento (fecha idéntica), "Último" mostraba una serie al azar en vez de la última de verdad. Se agregó `set_number` como criterio de desempate dentro del mismo entrenamiento.

### Responsive final + seguridad (completado — MVP terminado)
- Barrido completo a 320px (el ancho mínimo pedido) en las 14 pantallas de la app, en claro y oscuro, con un usuario de prueba real (no datos de demostración).
- **Tres bugs reales de desborde horizontal encontrados y corregidos**, los tres con el mismo patrón de fondo (contenido que no encoge/envuelve dentro de una fila flex) pero en componentes distintos:
  1. Los controles del cronómetro sobre una actividad en curso (franja de tiempo + botones Pausar/Finalizar) no entraban en una fila a 320px — ahora envuelve a una segunda línea si hace falta (`flex-wrap`).
  2. En Categorías, el nombre + insignia "Productiva" + contador de subcategorías no cedía espacio a los botones Editar/Eliminar (faltaba `min-w-0`) y los empujaba fuera de la tarjeta — el nombre ahora trunca y el resto puede pasar a una segunda línea.
  3. La barra inferior de navegación (BottomNav) tenía más ancho natural del que entra en 320px entre sus 5 accesos y el botón central — se le bajó el ancho por ítem en vez de depender de que el texto encogiera solo.
  4. Guardia defensiva agregada en `globals.css` (`overflow-x: hidden` en `html`/`body`) para que ningún elemento de posición fija pueda producir scroll horizontal fantasma a futuro — no afecta el scroll horizontal intencional de la grilla semanal del calendario, que ya tiene su propio contenedor `overflow-x-auto` independiente.
- **Bug de hidratación real encontrado y corregido** (no es de responsive, salió durante estas mismas pruebas): `LiveElapsed` calculaba el tiempo transcurrido con `Date.now()` ya en el primer render — ese primer render corre tanto en el servidor como en el cliente, en momentos distintos, así que el texto no coincidía entre los dos (error de hidratación de React, reproducible en cualquier actividad o entrenamiento con el cronómetro activo). Se corrigió arrancando en `null` (mismo valor en servidor y cliente) y sincronizando el valor real recién después de montar en el navegador.
- Seguridad revisada explícitamente: RLS activo con política por `user_id` confirmado en las 15 tablas; ninguna acción de servidor confía en un `user_id` mandado por el cliente (siempre usa el de la sesión real); sin vectores de XSS (el único `dangerouslySetInnerHTML` de toda la app es el script de tema, con contenido fijo, no datos de usuario); validación de límites ya reforzada a nivel de base de datos desde el diseño original (montos y duraciones no negativos, fechas coherentes).
- Ciclo completo del cronómetro probado en vivo de punta a punta: iniciar → pausar (tiempo acumulado correcto) → reanudar (sigue sumando sin resetear) → finalizar (duración final correcta) — sin errores de consola en ningún paso.

**Con esto se completan las 12 fases del MVP del prompt maestro, y la app ya está publicada en https://productividad-ori.netlify.app.** Fase 2 se completó después en la misma sesión — ver la sección dedicada más abajo.

### Decisiones ya tomadas

- **Nombre:** Productividad Ori.
- **Uso:** personal, no para clientes ni venta — pero **sí se sube a internet** (no se queda solo local), con backup en la nube. El usuario dudó primero entre no publicarla ("es solo para mí") y publicarla privadamente; la decisión final fue subirla igual.
- **Supabase:** proyecto nuevo (`productividad-ori`) dentro de la misma cuenta/organización que ya tiene Software EYO, pero separado — nunca se mezclan los datos personales con los del hotel. Ya creado y en uso.
- **Netlify:** decisión cambiada sobre el final — en vez de una cuenta separada (la idea original, ver más abajo), se publicó dentro de la organización `SoftwareEYO` ya existente, con confirmación explícita y por duplicado del usuario aceptando el riesgo de créditos compartidos. Publicado en https://productividad-ori.netlify.app.
- **Repositorio:** separado del de Software EYO (`D:\Ori\EYO`) — carpeta y repo propios. Por defecto, privado (es una app personal), a confirmar cuando se suba de verdad.
- **Documentación:** en `docs/obsidian` del repo de Software EYO (esta misma carpeta), no en la bóveda real de Obsidian (`D:\Ori\Obsidian`) — decisión explícita del usuario al preguntarle, pese a que esa bóveda real tiene un sistema de organización más completo por producto. Ver la nota de abajo.

### Nota importante sobre la bóveda de Obsidian

Durante esta sesión se descubrió que existe una bóveda de Obsidian real y más completa en `D:\Ori\Obsidian` (con `CLAUDE.md`, carpetas numeradas por producto, decisiones `DEC-XXX`, roadmaps, plantillas) que **no se actualiza desde el 2026-08-04.** Todo lo documentado en sesiones más recientes (Centro de Configuración, Caja, i18n, Web EYO, GitHub, página comercial, y ahora esto) quedó en `docs/obsidian` dentro del repo de Software EYO — una carpeta distinta, con formato similar pero sin conexión real con la app de Obsidian que el usuario abre. Consultado explícitamente, el usuario eligió seguir usando esta carpeta (`docs/obsidian`) en vez de migrar a la bóveda real. Si en algún momento se decide unificar, hay que revisar ambas fuentes — no asumir cuál manda.

## Arquitectura técnica (según el prompt maestro)

- **Frontend:** React + Next.js + TypeScript + Tailwind CSS.
- **Backend:** Supabase (Auth + PostgreSQL + Row Level Security). Realtime solo donde tenga sentido.
- **Hosting:** gratuito (Netlify o similar) — cuenta a definir, ver arriba.
- Sin IA para cálculos que se resuelven con matemática simple (estadísticas, insights, comparaciones).
- PWA preparada (manifest, iconos), sin exigir soporte offline completo en la v1.

### Principio central del cronómetro

No depender de un contador de JavaScript corriendo en el navegador. Guardar `started_at`/`paused_at`/`resumed_at`/`finished_at` como timestamps reales en base de datos, y calcular la duración a partir de esos timestamps — así una actividad cronometrada sobrevive a cerrar el navegador, bloquear el celular, o cambiar de app.

### Tablas principales (borrador, sujeto a la fase de diseño de arquitectura)

`profiles`, `categories`, `subcategories`, `projects`, `activities`, `timer_sessions`, `goals`, `time_budgets`, `tasks`, `workouts`, `exercises`, `workout_exercises`, `exercise_sets`, `weekly_templates`, `user_preferences`. Todas las tablas de usuario llevan `user_id` + RLS (cada usuario solo lee/escribe lo suyo — aunque en este caso es una app mono-usuario, la regla se mantiene igual que en Software EYO).

## Fases de desarrollo (orden pedido por el usuario)

1. Arquitectura, Supabase, Auth, base de datos, RLS.
2. Layout responsive y navegación (bottom nav en celular, sidebar en escritorio).
3. Categorías y proyectos.
4. Actividades (planificadas + registro real).
5. Calendario (vista semana por defecto, día y mes).
6. Cronómetro (con persistencia real vía timestamps, sesiones múltiples por actividad).
7. Dashboard (resumen del día, actividad activa, próxima actividad, objetivo diario).
8. Estadísticas (diarias, semanales, mensuales, anuales, planificado vs. real, comparación semana a semana).
9. Objetivos y presupuesto de tiempo.
10. Gimnasio (entrenamientos, ejercicios, series, volumen, historial por ejercicio, estadísticas por músculo).
11. Responsive final (320px en adelante) y modo oscuro.
12. Seguridad y pruebas (RLS, XSS, validación, casos límite del cronómetro).

Regla explícita del usuario: **cada fase se verifica (compila, sin errores de TypeScript, RLS probado, responsive revisado) antes de pasar a la siguiente** — no se avanza a ciegas.

### MVP (fase 1, alcance mínimo obligatorio)

Autenticación, dashboard, calendario semanal, crear/editar/eliminar actividades, categorías, proyectos, cronómetro (iniciar/pausar/finalizar), registro manual, planificado vs. real, estadísticas diarias y semanales, objetivos semanales, presupuesto de tiempo, gimnasio (entrenamientos/ejercicios/series) con estadísticas básicas, responsive móvil, modo oscuro, RLS y seguridad.

### Fase 2 (completada, 2026-08-20)

Las 12 funcionalidades pedidas para después del MVP, todas construidas y verificadas en vivo con un usuario de prueba real:

- **Tareas** (`/tareas`): título, descripción, prioridad, fecha límite, categoría/proyecto opcionales, tres estados (pendiente/en curso/completada, con reapertura), y "convertir en actividad planificada" (crea la actividad real y la enlaza vía `tasks.activity_id`).
- **Actividades recurrentes**: al crear una actividad, tildar "Repetir" habilita diaria / lunes a viernes / semanal / días específicos / mensual, con cantidad de repeticiones configurable. Cada ocurrencia es una fila real e independiente de `activities` (no un patrón calculado al vuelo), agrupadas por `recurrence_group_id`. Al eliminar una que pertenece a una serie, se puede elegir "solo esta" o "esta y todas las futuras".
- **Copiar semana anterior**: en la vista semanal del calendario, clona lo *planificado* de la semana previa a la actual (nunca estados ni tiempos reales, para no arrastrar datos que no correspondan).
- **Plantillas semanales**: guardar la semana actual como plantilla con nombre propio (`weekly_templates` + `weekly_template_items`: día de la semana + hora + duración por actividad), aplicarla a cualquier semana futura, eliminarla. Bug real evitado antes de escribir el código de aplicación: las semanas de esta app siempre arrancan en lunes, así que el `day_of_week` que devuelve JavaScript (0 = domingo) hay que convertirlo a "días desde el lunes" antes de sumarlo a la fecha de inicio — usarlo como offset directo habría corrido todo un día.
- **Rachas**: días consecutivos con al menos una actividad completada, mostrando racha actual y mejor racha histórica en Estadísticas (`utils/streak.ts`).
- **Comparación mensual** y **estadísticas anuales**: ya existían desde el MVP (el selector de período `Este mes`/`Año` ya calculaba automáticamente la comparación contra el período anterior) — confirmadas funcionando, no hizo falta código nuevo.
- **Insights automáticos**: frases generadas con reglas simples sobre datos ya calculados en la página (racha, cambio de tiempo vs. período anterior, categoría dominante, % de cumplimiento, día más productivo) — nunca con IA, tal como pide el prompt maestro.
- **Historial avanzado de gimnasio**: gráfico de progreso de peso por ejercicio a lo largo del tiempo, en la página de historial de cada ejercicio.
- **Récords personales** (`/gimnasio/records`): página nueva que agrega la mejor marca y el mayor volumen de TODOS los ejercicios a la vez, no de a uno.
- **Exportaciones CSV/Excel/PDF**: en Actividades y Estadísticas. Librería `xlsx` instalada desde el tarball oficial de SheetJS (`cdn.sheetjs.com`) en vez del paquete de npm, porque la versión publicada en el registro de npm tiene una vulnerabilidad alta sin parche disponible — decisión de seguridad, no un detalle menor.
- **PWA avanzada**: íconos reales (192px/512px/maskable — el manifest tenía el array de íconos vacío desde Fase 1) generados con un encoder de PNG escrito en Python puro (sin librerías, ya que no había Pillow disponible), service worker con red-primero para navegación (mostrando `offline.html` en vez del error feo del navegador cuando no hay conexión) y cache-primero para assets estáticos, botón "Instalar app" en Perfil vía `beforeinstallprompt`.

Publicado en producción: https://productividad-ori.netlify.app

### Notas del día (agregado después de Fase 2, 2026-08-20)

Pedido del usuario después de ver la app terminada: quería algo tipo "notas" para anotar pendientes del día, más libre que Tareas (que exige prioridad/estado) y sin necesidad de horario como una Actividad. Se definió con el usuario (opción elegida entre 3) que fueran **notas por día**, no una lista general tipo Keep.

- Tabla nueva `daily_notes` (`user_id` + `note_date` único, `content` de texto libre), RLS estándar.
- Vive en la vista **Día** del calendario, debajo de la grilla de horarios — un cuadro de texto que se guarda solo al salir del campo (blur) si el contenido cambió, con indicador "Guardando…"/"Guardado".
- Cada día es independiente: se usa `key={noteDate}` en el componente para que React lo remonte entero al cambiar de fecha, en vez de arrastrar por error lo que había quedado escrito para otro día.
- Verificado en vivo: escribir, guardar, recargar (persiste), cambiar de día (queda vacío, no se mezcla). Un supuesto bug apareció durante la prueba (el guardado no disparaba) pero resultó ser el entorno de prueba automatizado sin foco real de documento, no la app — confirmado disparando el evento `focusout` a mano, sin tocar código.

## Prompt maestro completo (fuente original, 2026-08-20)

> Documento de referencia — no editar, es la especificación tal como la escribió el usuario. Cualquier cambio de alcance se documenta como una decisión nueva en este archivo, no editando el texto de abajo.

PROMPT MAESTRO — APP DE CALENDARIO, PRODUCTIVIDAD, TRABAJO, GIMNASIO Y ESTADÍSTICAS

Quiero que diseñes y desarrolles una aplicación completa de productividad personal cuyo objetivo principal sea permitir al usuario:

PLANIFICAR → EJECUTAR → REGISTRAR → MEDIR → ANALIZAR → MEJORAR

No quiero simplemente una aplicación de calendario ni solamente un cronómetro.

La aplicación debe funcionar como un panel de control de la vida diaria del usuario, permitiendo saber exactamente:

- Qué tenía planificado hacer.
- Qué hizo realmente.
- Cuánto tiempo dedicó.
- A qué áreas de su vida está dedicando más tiempo.
- Qué proyectos consumen más horas.
- Cuánto tiempo entrena.
- Qué entrenó en el gimnasio.
- Cuánto estudió.
- Cuánto trabajó.
- Qué objetivos semanales cumplió.
- Qué porcentaje de lo planificado realmente ejecutó.
- Cómo evolucionan sus hábitos y su uso del tiempo semana a semana.

### 1. Objetivo general

Crear una aplicación moderna, rápida, responsive y principalmente diseñada para celular, aunque debe funcionar perfectamente también en computadora y tablet.

La aplicación debe combinar conceptos de: Google Calendar, time tracking, cronómetro, productividad, gestión de proyectos personales, registro de gimnasio, seguimiento de objetivos, estadísticas, hábitos, análisis semanal/mensual/anual — todo dentro de una única aplicación.

La aplicación debe evitar ser complicada. Registrar información debe ser rápido. Siempre priorizar: menos clics + más automatización + estadísticas útiles.

### 2. Tecnología

Frontend: React, Next.js, TypeScript, Tailwind CSS.
Backend: Supabase (Auth, PostgreSQL, Row Level Security, Realtime solo cuando tenga sentido).
Hosting: servicios gratuitos siempre que sea posible. Evitar dependencias que generen costos mensuales innecesarios. No utilizar APIs de inteligencia artificial para funciones que pueden resolverse mediante cálculos normales.

### 3. Diseño general

Moderno, minimalista, profesional, muy limpio, fácil de entender, mobile first, responsive, rápido, visualmente agradable. No saturado. Usar cards, gráficos simples, barras de progreso, iconos, espaciado amplio, tipografía clara, bordes redondeados moderados. Modo claro y modo oscuro, elegible por el usuario.

### 4. Navegación principal

Celular: barra inferior con Inicio, Calendario, botón central "+" para registrar rápido, Estadísticas, Perfil.
Escritorio: sidebar.

### 5. Dashboard principal

Pantalla Inicio: saludo + fecha, actividad actual (con pausar/finalizar, hora de inicio, tiempo transcurrido, categoría, proyecto), próxima actividad (con botón Comenzar), resumen del día por categoría, tiempo productivo total, objetivo diario con barra de progreso, listado cronológico de actividades de hoy con su estado.

### 6-7. Calendario

Vistas Día, Semana (por defecto), Mes. Vista semanal: horas en vertical, columnas por día de la semana, actividades como bloques con horario/título/categoría. Crear, editar, eliminar, mover, cambiar duración, duplicar, marcar completada, comenzar cronómetro — todo desde el calendario.

### 8. Actividades

Campos: ID, usuario, título, descripción opcional, categoría, subcategoría, proyecto opcional, fecha, hora de inicio/fin planificada, duración planificada, inicio/fin real, duración real, estado, notas, nivel de concentración opcional, nivel de energía opcional.

### 9. Estados de actividad

Planificada, en progreso, pausada, completada, parcialmente completada, cancelada, no realizada — cada uno identificado visualmente.

### 10. Planificado vs. real

Comparar tiempo planificado contra tiempo realizado por categoría/proyecto, diario/semanal/mensual. Cumplimiento = duración real / duración planificada × 100.

### 11-13. Cronómetro

Cronómetro global, visible mientras hay actividad activa. Iniciar, pausar, continuar, finalizar. **No depender de un contador de JavaScript corriendo constantemente** — guardar `started_at`, `paused_at`, `resumed_at`, `finished_at` en base de datos y calcular la duración con timestamps reales, para que sobreviva a cerrar el navegador, bloquear el teléfono, cambiar de app, o volver horas después. Una misma actividad puede tener varias sesiones de cronómetro (tabla `timer_sessions`: id, user_id, activity_id, started_at, ended_at, duration_seconds, status).

### 14. Inicio rápido

Botón "+ Iniciar actividad" → preguntar título, categoría, proyecto opcional → "Empezar cronómetro". No obligar a completar muchos campos.

### 15-16. Categorías y subcategorías

Categorías iniciales sugeridas: Trabajo, Estudio, Gimnasio, Fútbol, Deporte, Lectura, Administración, Personal, Descanso, Reuniones, Transporte, Otro — el usuario puede crear las suyas (nombre, ícono, color, descripción). Las categorías pueden tener subcategorías (ej. Trabajo → Software, Alojamientos, Administración, Marketing, Finanzas, Reuniones).

### 17. Proyectos

Ejemplo: Software EYO, Hostal, Marketing, Universidad, Proyecto personal. Cada proyecto muestra: total de horas, horas esta semana/mes, número de sesiones, fecha de última actividad, promedio diario, porcentaje del tiempo laboral.

### 18-19. Estadísticas de trabajo y presupuesto de tiempo

Distribución de horas por proyecto/categoría con porcentajes. "Presupuesto de tiempo": el usuario define cuántas horas quiere dedicar por semana a cada categoría (ej. Trabajo 35h, Estudio 10h, Gimnasio 7h) y la app muestra cumplimiento — por debajo del objetivo, objetivo alcanzado, u objetivo superado.

### 20. Objetivos

Diarios, semanales o mensuales (ej. "Trabajar 35 horas semanales", "Entrenar 5 días"), con barra de progreso.

### 21-28. Módulo de gimnasio

Entrenamientos con nombre (ej. Pecho + tríceps, Espalda + bíceps, Piernas, Hombros, Full Body). Entrenamiento activo con cronómetro propio, agregar/editar/eliminar ejercicios y series (peso, repeticiones). Ejercicios con nombre, grupo muscular, notas, historial. Estadísticas semanales (entrenamientos, tiempo total, promedio, ejercicios, series). **Volumen** = peso × repeticiones, sumado por entrenamiento/semana/mes/ejercicio. Estadísticas por grupo muscular (para detectar músculos poco entrenados). Historial por ejercicio: último entrenamiento, mejor marca, mayor volumen, historial completo fecha/peso/repeticiones/volumen.

### 29-40. Estadísticas generales

Filtros por período (hoy, 7 días, semana actual/pasada, 30 días, mes actual/pasado, año, rango personalizado). Gráficos simples (barras, líneas, donut, progreso) — sin saturar: horas por día, distribución por categoría/proyecto, planificado vs. realizado, evolución semanal, entrenamientos por semana. Comparación semana actual vs. anterior (por categoría, con porcentaje de cambio). Tendencias a 7/30/90 días y 1 año. Día más y menos productivo. Definición configurable de qué categorías cuentan como "productivas" (por defecto: Trabajo, Estudio, Gimnasio, Lectura, Proyectos). Rachas (ej. "6 semanas entrenando 4+ veces") — mantenido profesional, no gamificado. Resumen semanal automático (por cálculo, no IA) con horas trabajadas/entrenadas/estudiadas, % de cumplimiento, actividad principal, día más/menos productivo, objetivos completados. Estadísticas mensuales y anuales con los mismos ejes.

### 41-54. Tareas, recurrencia, plantillas y detalles de registro

Tareas (título, descripción, fecha límite, prioridad, estado, proyecto) que pueden convertirse en actividad planificada en el calendario. Actividades recurrentes (diaria, lunes a viernes, semanal, días específicos, mensual). "Copiar semana anterior" como base de planificación (sin copiar estados/tiempos reales). Plantillas semanales guardables (ej. "Semana normal", "Semana universidad"). Registro manual retroactivo (marcado como tal). Corrección de tiempos ya registrados (marcada como editada manualmente). Detección de actividades planificadas solapadas, con advertencia pero permitiendo confirmar. Solo una actividad cronometrada activa a la vez (con opción de finalizar la actual, pausarla y empezar otra, o cancelar). Buscador (actividades, proyectos, ejercicios, tareas) y filtros (categoría, subcategoría, proyecto, estado, fecha). Notas en actividades y entrenamientos. Nivel de concentración y energía opcionales (1-10) al finalizar una actividad, con promedio semanal.

### 55-62. Experiencia móvil/desktop, PWA, auth, seguridad, validación

Funcional desde 320px. Cards/listas/bottom nav/modales en móvil; sidebar/calendario amplio/paneles en desktop. PWA (manifest, iconos, nombre, theme color), sin exigir soporte offline completo en la v1. Auth: registro, login, logout, recuperar/cambiar contraseña (Google Login como posibilidad futura, no obligatoria en el MVP). **Seguridad no negociable:** nunca exponer `service_role key` ni secretos; RLS en toda tabla con `user_id`, cada usuario lee/escribe/edita/borra solo lo suyo, nunca confiando solo en filtros de frontend. Validación en frontend y backend (duraciones negativas, fechas inválidas, series imposibles, horas finales antes que iniciales).

### 63-76. Base de datos

Arquitectura limpia. Tablas: `profiles`, `categories`, `subcategories`, `projects`, `activities`, `timer_sessions`, `goals`, `time_budgets`, `tasks`, `workouts`, `exercises`, `workout_exercises`, `exercise_sets`, `weekly_templates`, `user_preferences`. (Ver detalle de campos de cada tabla en la versión original del prompt, guardada íntegra en el historial de la conversación que originó este pedido — al momento de diseñar la Fase 1 de arquitectura, releer los campos completos antes de escribir las migraciones.)

### 77-83. Timezone, semana, performance, formato

Manejo correcto de zona horaria (evitar el bug clásico de `new Date('YYYY-MM-DD')` interpretado como UTC medianoche — el mismo tipo de bug ya corregido antes en Software EYO, ver [[Historia-y-decisiones]]). Primer día de semana configurable (lunes por defecto). Índices en `user_id`, fechas, `activity_id`, `project_id`, `category_id`, `workout_id`. No duplicar datos que se puedan calcular de forma confiable desde `activities`/`timer_sessions`. Duración interna en segundos, mostrada como "1 h 28 min" (nunca decimales tipo "1.4666 horas").

### 84. Insights automáticos

Por reglas matemáticas, sin IA. Ej.: "Trabajaste 18% más que la semana pasada", "Tu martes fue el día con mayor tiempo productivo", "Software EYO representó el 62% de tu tiempo laboral".

### 85-95. Historial, exportación, configuración, onboarding, estados vacíos/error/carga, confirmaciones, archivado, accesibilidad

Navegación entre semanas (anterior/hoy/siguiente) sin perder datos. Arquitectura preparada para exportar CSV/Excel/PDF a futuro (no obligatorio en MVP). Pantalla de configuración (perfil, apariencia, categorías, proyectos, objetivos, presupuesto de tiempo, unidades, primer día de semana, zona horaria, cuenta). Onboarding corto y saltable (nombre → categorías principales → objetivos opcionales → primera actividad). Datos de demostración en desarrollo. Nunca pantallas vacías sin acción sugerida. Errores entendibles para el usuario (nunca mensajes técnicos de Supabase crudos). Loading con skeletons, nunca pantalla en blanco. Confirmación antes de eliminar actividad/entrenamiento/proyecto con datos/cuenta. Proyectos archivables en vez de solo eliminables (conserva el historial estadístico). Accesibilidad básica (labels, aria-label, contraste, navegación por teclado en desktop).

### 96-98. MVP, Fase 2, y qué no hacer

Ver "Fases de desarrollo" arriba para el detalle del MVP y la Fase 2. Explícitamente evitar: interfaz saturada, código monolítico, una página gigantesca, componentes sin estructura, lógica duplicada, estadísticas falsas o datos hardcodeados en producción, información sensible en frontend, `service_role key` expuesta, tablas sin RLS, cronómetros dependientes solo del navegador, diseño que funcione solo en desktop.

### 99-100. Organización de código y tipos

Separar `components`, `features`, `hooks`, `services`, `lib`, `types`, `utils`, rutas de la app, capa de base de datos. Componentes reutilizables (ej. `ActivityCard`, `Timer`, `DurationDisplay`, `CategoryBadge`, `ProgressBar`, `StatCard`, `WeeklyCalendar`, `GoalProgress`, `WorkoutCard`, `ExerciseSetRow`). Tipos TypeScript claros para cada entidad, evitando `any` salvo necesidad real.

### 101-104. Flujo de uso esperado

Ejemplo visual del dashboard móvil (saludo, actividad "ahora" con pausar/finalizar, "próximo", resumen "hoy" por categoría, objetivo con barra de progreso, bottom nav). Estadísticas móviles en cards/listas, no tablas grandes, con comparación porcentual contra la semana anterior. Flujo ideal: planificar de noche/inicio de semana → tocar "Comenzar" durante el día (registro automático) → tocar "Finalizar" → ver estadísticas del día → ver análisis completo al fin de semana. **Principio fundamental: el usuario nunca escribe la misma información dos veces** — si una actividad ya existe en el calendario, al tocar "Comenzar" la app ya conoce categoría, proyecto, hora planificada y duración esperada; solo hay que arrancar el cronómetro.

### 105. Futuro (no implementar todavía)

Integración con Apple Calendar, Google Calendar, wearables, Apple Health, Google Fit, notificaciones, recordatorios, widget móvil, IA opcional, equipos, coaching.

### 106-108. Pruebas obligatorias

Antes de dar por terminada una función: crear, editar, eliminar, actualizar, refrescar navegador, cerrar/reabrir sesión, móvil, desktop, dark mode, timezone, cambio de semana, cronómetro activo/pausado. Casos críticos del cronómetro: iniciar y cerrar pestaña (debe continuar), iniciar-pausar-cerrar-volver (debe seguir pausado), iniciar-trabajar-finalizar (duración correcta). Validar manualmente los cálculos de estadísticas y porcentajes con números simples antes de confiar en la implementación.

### 109. Orden de desarrollo recomendado por el usuario

Arquitectura/Supabase/Auth/DB/RLS → Layout responsive y navegación → Categorías y proyectos → Actividades → Calendario → Cronómetro → Dashboard → Estadísticas → Objetivos → Gimnasio → Responsive final → Seguridad y testing.

### 110-112. Cómo trabajar, migraciones y seguridad antes de lanzar

**No generar todo el proyecto de golpe.** Trabajar por fases; antes de avanzar a la siguiente, comprobar que compila, verificar errores de TypeScript, comprobar rutas, probar base de datos, comprobar RLS, revisar responsive, corregir errores existentes — nunca dejar errores acumulándose. Todas las modificaciones de Supabase vía migraciones SQL versionadas (mismo patrón que Software EYO). Revisión final de seguridad antes de lanzar: claves expuestas, permisos incorrectos, tablas sin RLS, políticas demasiado permisivas, endpoints sin autorización, inputs no validados, XSS, SQL injection, IDOR, acceso a datos de otros usuarios, filtración de variables, errores de Supabase Auth.

### 113-114. Resultado final esperado e identidad del producto

El usuario debe poder abrir la app y responder de un vistazo: qué tiene que hacer hoy, qué está haciendo ahora, cuánto tiempo lleva, cuánto trabajó/entrenó/estudió hoy, a qué proyecto dedicó más tiempo, si está cumpliendo sus objetivos, si está haciendo realmente lo que planificó, en qué está gastando su tiempo, y si está mejorando respecto a la semana anterior. No debe sentirse como "un calendario más", sino como un sistema operativo personal para administrar el tiempo y medir el rendimiento: planificar mejor, ejecutar, medir la realidad, analizar, mejorar la semana siguiente.

## Próximo paso

No hay nada pendiente del prompt maestro — MVP y Fase 2 completos, publicado en producción. Lo único que queda abierto es lo que el usuario pida a futuro (mejoras puntuales, alguna idea nueva) o, opcionalmente, subir el repo a GitHub (hasta ahora solo vive en local).
