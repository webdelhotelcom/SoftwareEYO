# Límites del plan gratuito de Supabase — qué vigilar y cómo

El proyecto usa **un solo proyecto de Supabase, plan Free, compartido por todos los clientes** (separados entre sí por `tenant_id` + RLS). Esta nota explica los dos tipos de límite que existen y cómo se manejan, para que nunca se termine pagando algo sin que alguien lo decida a propósito.

## 1. Límite por cliente (dentro de la app, ya implementado)

Cada tenant tiene un tope de alojamientos (y, más adelante, de habitaciones y usuarios) según su plan contratado — `plan_config` + `client_limits` en la base de datos, no en el código JavaScript.

- El panel muestra "4 de 15 alojamientos utilizados" en la página de Alojamientos.
- Si un cliente llega al límite, el botón "Nuevo" se deshabilita con un aviso.
- Aunque alguien edite el JavaScript del navegador para saltarse ese aviso, el **trigger `check_properties_limit` en la base de datos** rechaza el `insert` igual (ver `supabase/migrations/0004_properties_module.sql`).
- Si el límite de un cliente Hotel todavía no se configuró (no hay fila en `client_limits` y el plan no trae default), el sistema **bloquea las altas nuevas en vez de permitir "sin límite"** — nunca se usa `Infinity` como comportamiento por defecto.

Esto ya está construido y probado (Fase 1). No implica ningún costo: es lógica de la aplicación, no un límite de Supabase.

## 2. Límite de la cuenta de Supabase (a nivel de todo el proyecto, hay que vigilarlo a mano)

Estos son límites del plan Free de Supabase en general (espacio de base de datos, ancho de banda, envío de mails de autenticación, etc.). Cambian de vez en cuando según la política de Supabase, así que **no conviene confiar en un número fijo escrito acá**: hay que revisarlos directamente en el dashboard.

Dónde mirar:

- **Supabase Dashboard → Project Settings → Usage** — ahí Supabase muestra el consumo actual contra el límite del plan Free (espacio de base de datos, ancho de banda, usuarios de Auth, etc.), con barras de progreso.
- Conviene revisarlo una vez por mes, o cuando se sume un cliente nuevo grande.

### Qué pasa si se llega a un límite de Supabase

Supabase, en el plan Free, **no cambia de plan solo ni empieza a cobrar automáticamente**. Lo que puede pasar es que ciertas funciones se restrinjan o el proyecto se pause por inactividad — nunca una migración automática a un plan pago. Aun así, la instrucción del proyecto es clara: **cualquier cambio de plan, complemento pago o suscripción se consulta antes de activarlo.** Esta app nunca lo hace por sí sola.

### Proyecto pausado por inactividad

Los proyectos gratuitos de Supabase pueden pausarse automáticamente después de un tiempo sin actividad. Si el panel deja de conectar y la consola del navegador muestra errores de red hacia `supabase.co`, lo primero para revisar es: Supabase Dashboard → tu proyecto → si aparece un botón para "reactivar/restore", tocarlo. Esto no genera ningún cargo, solo requiere una acción manual.

## Resumen

- Límite por cliente → resuelto en la base de datos, con aviso en pantalla y bloqueo real. No es plata.
- Límite de la cuenta de Supabase → hay que mirarlo a mano en el dashboard de vez en cuando. Si algún día hace falta pasar a un plan pago para seguir creciendo, es una decisión de negocio que se toma explícitamente, nunca un cambio automático del sistema.
