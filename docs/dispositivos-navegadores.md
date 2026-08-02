# Matriz de dispositivos y navegadores

Qué se probó realmente y qué no, para no dar por buena una combinación que nunca se abrió de verdad.

## Herramienta de prueba disponible

Todas las pruebas de esta sección se hicieron con el navegador automatizado disponible en este entorno de trabajo, que usa el mismo motor que Google Chrome/Microsoft Edge (Chromium), con distintos anchos de pantalla simulados (viewport). **No hay acceso a un dispositivo físico real (celular, tablet) ni a otros motores de navegador (Firefox/Gecko, Safari/WebKit) en este entorno.** Donde no se pudo verificar de verdad, se marca explícitamente como tal en vez de asumir que funciona igual.

## Anchos de pantalla probados (panel y página comercial)

| Ancho | Referencia | Panel (`app/panel.html`) | Página comercial (`index.html`) |
|---|---|---|---|
| 375px | Celular chico (iPhone SE/mini) | Sin desborde horizontal ✅ | Sin desborde horizontal ✅ |
| 768px | Tablet | Sin desborde horizontal ✅ | Sin desborde horizontal ✅ |
| 1280px | Notebook/escritorio | Sin desborde horizontal ✅ | Sin desborde horizontal ✅ |

Además, en la Fase 4 de este mismo proyecto ya se habían revisado a mano los módulos del panel uno por uno en ancho celular (incluida la corrección específica del zoom automático de iOS en los formularios: `font-size:16px` en los inputs, para que Safari no haga zoom solo al tocar un campo).

## Motores de navegador

| Motor / navegador | Estado | Cómo se sabe |
|---|---|---|
| Chromium (Chrome, Edge, Brave, Opera) | **Probado en vivo**, en este entorno, en los tres anchos de arriba y en el flujo completo de login/CRUD de varios módulos a lo largo de toda la auditoría. | Directo — es el motor que usa la herramienta de este entorno. |
| Safari / WebKit (Mac, iPhone, iPad) | **No verificable en este entorno.** El código usa CSS y JavaScript estándar (flexbox, grid, `fetch`, `async/await`, sin APIs experimentales), lo cual es compatible con versiones recientes de Safari en teoría, pero eso no reemplaza abrirlo en un Safari real — WebKit tiene particularidades propias (inputs, `position:sticky`, animaciones) que a veces se comportan distinto. | Sin probar. |
| Firefox / Gecko | **No verificable en este entorno**, mismo motivo. | Sin probar. |
| Navegadores de Android (Chrome Android, Samsung Internet) | **No verificable en este entorno** — la simulación de ancho de pantalla no reemplaza un teclado táctil real, gestos, ni el navegador real del fabricante. | Sin probar. |

## Qué significa esto en la práctica

- Es razonable esperar que el sistema funcione bien en Chrome/Edge de escritorio y celular (el caso más común), porque fue lo que se probó.
- Antes de anunciar el sistema como "probado en todos los dispositivos", **hace falta abrirlo al menos una vez en un iPhone real con Safari** (es el caso más distinto técnicamente) y en un Android con Chrome, idealmente haciendo el flujo completo: login, crear una reserva, subir una foto/backup, y revisar que el teclado no tape los formularios.
- Si en algún momento un cliente reporta un problema visual puntual en Safari o Firefox, no va a ser sorpresa — es la brecha de cobertura conocida y documentada acá, no un caso que se haya dado por probado sin estarlo.

## Cómo actualizar esta matriz

Cuando alguien pruebe el sistema en un dispositivo o navegador real, agregar una fila nueva acá con la fecha, el dispositivo/navegador exacto (marca, modelo, versión) y el resultado — igual que se hizo con las pruebas de seguridad en `docs/pruebas-aislamiento.md`. No reemplazar "no verificable" por "✅" sin haberlo hecho de verdad.
