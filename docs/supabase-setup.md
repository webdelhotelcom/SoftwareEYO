# Crear el proyecto de Supabase (una sola vez)

Esto lo tenés que hacer vos: no puedo crear la cuenta ni cargar datos de pago en tu nombre. Son unos 10-15 minutos.

## 1. Crear la cuenta y el proyecto

1. Entrá a [supabase.com](https://supabase.com) → **Start your project** → creá una cuenta (con GitHub o con email).
2. **New project**.
3. Elegí una organización (o creá una nueva, es gratis).
4. Completá:
   - **Name**: por ejemplo `eyo-produccion` (el nombre es solo para vos, no lo ve nadie más).
   - **Database Password**: generá una y **guardala en un lugar seguro** (gestor de contraseñas). No hace falta usarla en el día a día, pero es la llave maestra de la base.
   - **Region**: elegí la más cercana a Uruguay (por ejemplo `South America (São Paulo)` si está disponible).
   - **Pricing Plan**: dejá **Free** — no lo cambies a Pro. Este proyecto está pensado para quedarse en el plan gratuito; cualquier cambio de plan se consulta antes.
5. **Create new project**. Tarda uno o dos minutos en aprovisionarse.

## 2. Correr el esquema SQL

Una vez que el proyecto esté listo:

1. Menú lateral → **SQL Editor** → **New query**.
2. Abrí `supabase/migrations/0001_tenants_and_plans.sql` de este repositorio, copiá todo el contenido, pegalo en el editor y tocá **Run**. Tiene que decir "Success" abajo.
3. Repetí el mismo paso, en este orden exacto, con:
   - `0002_profiles_and_auth_helpers.sql`
   - `0003_rls_core_tables.sql`
   - `0004_properties_module.sql`

Si alguno da error, no sigas con el siguiente — copiame el mensaje de error tal cual aparece y lo resolvemos antes de continuar.

## 3. Conseguir las claves para el panel

1. Menú lateral → **Project Settings** (ícono de engranaje) → **API** (en versiones nuevas del dashboard puede aparecer como **Data API**).
2. Copiá dos valores:
   - **Project URL** (algo como `https://xxxxxxxxxxxx.supabase.co`)
   - **anon public** key (una cadena larga que arranca con `eyJ...`)
3. **NO copies ni me pases la clave `service_role`.** Esa es secreta y no la necesitamos para esta fase.
4. Pasame esos dos valores (Project URL y anon public) para que yo complete `app/config.js` (ya está en `.gitignore`, así que no queda expuesta en el repositorio).

## 4. Crear el primer cliente de prueba (tenant) y tu usuario admin

Esto también se hace por SQL Editor, con vos mirando y yo guiando en el momento — preferí hacerlo juntos en vez de dejarte un script para correr solo, porque acá se crea el usuario con el que vas a entrar al panel.

Resumen de lo que vamos a hacer cuando llegue el momento:

1. **Authentication → Users → Add user** en el dashboard: creás el primer usuario (tu email real + una contraseña). Anotá el **UID** que le asigna Supabase (un UUID).
2. Por SQL Editor, insertamos una fila en `tenants` (con el plan que corresponda) y una fila en `profiles` que conecta ese UID con ese tenant y con rol `admin`.
3. Si el plan es `hotel`, además cargamos la fila en `client_limits` con los números reales del contrato (nunca queda "sin límite": si no se carga esta fila, el sistema bloquea las altas de alojamientos hasta que se configure).

Cuando tengas el Project URL y la anon key del paso 3, avisame y seguimos con esto.

## 5. Verificación rápida

Con `app/config.js` completo y el primer usuario creado:

1. Abrí `app/panel.html` en el navegador (o pedime que lo pruebe yo).
2. Iniciá sesión con el email/contraseña que creaste.
3. Deberías ver el panel con "0 de N alojamientos utilizados" (según el límite que hayamos cargado) y poder crear un alojamiento de prueba.
