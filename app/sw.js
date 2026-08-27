// Service worker de Software EYO — mismo patrón que Productividad Ori:
// red primero para la app (siempre datos/código frescos), cache primero para
// assets estáticos inmutables, y NUNCA cachea nada fuera de este origen (ni
// Supabase ni los CDN de librerías) -- ver el chequeo de origin más abajo.
const CACHE_NAME = "eyo-panel-v1";
const PRECACHE_URLS = [
  "/offline.html",
  "/manifest.webmanifest",
  "/icon-192.png",
  "/icon-512.png",
  "/icon-maskable-512.png",
  "/panel",
  "/panel.html",
  "/config.js",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // nunca cachea Supabase ni los CDN de librerías

  // Navegación (entrar a /panel o /panel.html): red primero, para que la app
  // y sus datos estén siempre al día. Sin red, muestra la última versión
  // cacheada de esa página o, si no existe, offline.html.
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          return response;
        })
        .catch(() => caches.match(request).then((cached) => cached || caches.match("/offline.html")))
    );
    return;
  }

  // Assets estáticos propios (config.js, manifest, íconos): cache primero,
  // más rápido y funcionan sin red. panel.html cambia con cada deploy, pero
  // como la propia app hace fetch a Supabase para sus datos (nunca cachea
  // eso), servir una versión de panel.html un poco vieja desde cache no
  // deja datos desactualizados -- solo código, que se refresca solo la
  // próxima vez que haya red (activate() borra el cache viejo en cada deploy
  // que suba el CACHE_NAME).
  if (PRECACHE_URLS.includes(url.pathname)) {
    event.respondWith(
      caches.match(request).then(
        (cached) =>
          cached ||
          fetch(request).then((response) => {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
            return response;
          })
      )
    );
  }
});
