// Ziggo Super App Service Worker — Push Notifications Engine

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// ── Receive and Display Push Notification ─────────────────────────
self.addEventListener('push', (event) => {
  let data = {
    title: '🚀 Ziggo is Officially LIVE!',
    body: "Sri Lanka's flagship super-app is live. Tap to open Rides, Food, Trucks & Mart now.",
    url: '/',
    icon: '/logo-light.png',
    badge: '/logo-light.png',
    image: '/service-rides-user-official.jpg',
  };

  if (event.data) {
    try {
      const payload = event.data.json();
      data = { ...data, ...payload };
    } catch {
      data.body = event.data.text() || data.body;
    }
  }

  const options = {
    body: data.body,
    icon: data.icon || '/logo-light.png',
    badge: data.badge || '/logo-light.png',
    image: data.image || '/service-rides-user-official.jpg',
    data: {
      url: data.url || '/',
      dateOfArrival: Date.now(),
    },
    vibrate: [200, 100, 200, 100, 300],
    tag: 'ziggo-launch-live',
    renotify: true,
    requireInteraction: true,
    actions: [
      { action: 'open', title: '🚀 Open Ziggo App' },
      { action: 'close', title: 'Close' },
    ],
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// ── Notification Click Handler ────────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  if (event.action === 'close') return;

  const targetUrl = event.notification.data?.url || '/';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          if (client.url.includes(self.location.origin) && 'navigate' in client) {
            client.navigate(targetUrl);
          }
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
    })
  );
});
