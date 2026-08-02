# Historia y decisiones

Ver también: [[00-Indice]] · [[Estado-actual]]

## Línea de tiempo

- **Antes de 2026-08-01:** Software EYO era una demo autocontenida en HTML (`Panel-EYO-Plan-Hotel/Profesional/Inicial.html`), sin backend, todo en `localStorage`, login hardcodeado `admin`/`1234`. Incluía también un sitio comercial de 2 páginas (`index.html` + `software.html`).
- **2026-08-01 — arranca la migración a un sistema real:** decisión de convertir la demo en un SaaS multi-cliente real: Supabase (Postgres + Auth) para el backend, autenticación real, límites de plan validados en el servidor. Fase 1 (Alojamientos) migrada y probada en vivo con 2 tenants el mismo día.
- **2026-08-01/02 — Fases 2 y 3:** el resto de los módulos de negocio migrados uno por uno siguiendo el mismo patrón (ver [[Modulos]]), hasta completar los 20 módulos.
- **2026-08-02 — Fase 4:** QA de celular (viewport, zoom automático de iOS) y revisión visual de la página comercial. La identidad visual propia (aplicar marca del usuario más allá de lo ya cargado) quedó pendiente — ver [[Estado-actual]].
- **2026-08-02 — Auditoría de seguridad independiente:** revisión completa, escéptica, con pruebas en vivo (no solo lectura de código) de todo el sistema antes de considerarlo listo para clientes reales. Encontró el hallazgo crítico de permisos no aplicados server-side (ver [[Seguridad]]) más varios hallazgos altos/medios (XSS, sesión de usuario desactivado, headers de seguridad, deduplicación de migración, documentación desactualizada, contenido pendiente en la página comercial).
- **2026-08-02 — Corrección de auditoría, Fases 1 a 10:** cada hallazgo corregido y vuelto a probar en vivo, en el orden: permisos por rol (crítico) → sesión de usuario desactivado (alto) → XSS (alto) → headers (medio) → deduplicación + rastro de restauraciones (alto) → documentación → página comercial → limpieza de código muerto → batería final de seguridad → matriz de dispositivos. Cada fase, commit propio, con evidencia real. El usuario pidió explícitamente parar después de cada fase y confirmar antes de seguir con la siguiente — no se avanzó por cuenta propia.

## Decisiones que conviene recordar (y por qué)

- **Un solo proyecto de Supabase para todos los clientes, nunca uno por cliente.** Motivo: quedarse en el plan gratuito — un proyecto por cliente habría significado costo por cliente, y el mandato explícito del proyecto es "cero servicios pagos sin consultar antes".
- **Nunca `Infinity` ni un número gigante como "sin límite" por default.** Si un límite (alojamientos, usuarios) no está configurado explícitamente para un cliente, el sistema **bloquea** en vez de permitir ilimitado. Decisión de negocio, no solo técnica: un límite mal configurado debe fallar de forma visible, no silenciosamente a favor del cliente.
- **La demo vieja y el sitio comercial original nunca se borran ni se editan de forma destructiva** — quedan como referencia histórica hasta que se decida explícitamente retirarlos. Por eso `LEEME (2).md` se marcó como histórico en vez de borrarlo.
- **No inventar contenido comercial.** Testimonios, videos, cifras — si no existen todavía, se ocultan (con `hidden`, reversible) en vez de rellenarse con algo inventado. Aplicado en la Fase 7 de la corrección de auditoría con la tarjeta de testimonio de Elsa.
- **Rama de respaldo antes de cualquier tanda de cambios riesgosa.** Ver `respaldo-pre-correccion-auditoria-2026-08-02` como ejemplo — convención a repetir para la próxima vez que haga falta.
- **"Terminado" significa probado de punta a punta, con datos reales, no solo código que compila.** Regla explícita del usuario para toda la auditoría, y buena práctica a mantener de acá en adelante: cualquier corrección de seguridad se prueba con un intento real de saltársela, no se asume que la política SQL hace lo que el comentario dice que hace.
- **Redesplegar antes de probar en vivo, siempre que el frontend haya cambiado en la sesión.** Lección aprendida en la Fase 5 de la corrección de auditoría: una prueba en vivo contra el sitio de Netlify sin redeploy previo usa el código VIEJO — produce falsos negativos silenciosos (parece que algo no funciona, cuando en realidad ni siquiera se está probando el código nuevo).

## Errores propios detectados y corregidos en el camino

Vale la pena dejarlos anotados porque son el tipo de error que se puede repetir:

- El SQL Editor de Supabase corre todo el script pegado como **una sola transacción**: si una sentencia falla, se deshace TODO lo anterior de esa misma ejecución, aunque haya dicho "Success" en un paso intermedio. Pasó más de una vez durante la auditoría.
- Los CTEs (`with x as (...)`) dentro de una misma sentencia `WITH` **no se ven entre sí** (misma snapshot) — un trigger que lee una tabla que otro CTE de la misma sentencia acaba de insertar no la va a ver. Hace falta partir en sentencias separadas cuando hay esa dependencia.
- Un backfill de permisos para tenants nuevos y otro para tenants existentes, escritos a mano por separado, se desalinearon (el rol `propietario` quedó con un permiso distinto según la fecha de alta del tenant) — corregido en `0022`. Lección: cuando la misma regla de negocio se escribe dos veces en dos lugares del código SQL, alto riesgo de que se desalineen con el tiempo; preferible extraerla a una sola función cuando sea posible.
