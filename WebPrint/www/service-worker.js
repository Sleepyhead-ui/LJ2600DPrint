const CACHE = "lj2600d-web-v5";
const APP_FILES = [
  "./",
  "./index.html",
  "./styles.css",
  "./app.js",
  "./encoder-worker.js",
  "./manifest.webmanifest",
  "./vendor/pdf.min.js",
  "./vendor/pdf.worker.min.js",
  "./vendor/lucide.min.js",
  "./icons/icon-180.png",
  "./icons/icon-1024.png"
];

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP_FILES)));
  self.skipWaiting();
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))
  );
  self.clients.claim();
});

self.addEventListener("fetch", event => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.pathname.includes("/cgi-bin/")) return;
  event.respondWith(
    caches.match(event.request).then(cached => cached || fetch(event.request).then(response => {
      if (response.ok) caches.open(CACHE).then(cache => cache.put(event.request, response.clone()));
      return response;
    }))
  );
});
