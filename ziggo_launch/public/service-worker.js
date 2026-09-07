// Ziggo Launch — Service Worker
// Handles Web Push notifications and notification click events.

const ZIGGO_APP_LINK = self.__NEXT_DATA__?.props?.pageProps?.appLink
  || 'https://ziggo.app';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data = {};
  try {
    data = event.data.json();
  } catch {
    data = { title: event.data.text() };
  }

  const title = data.title ?? 'Ziggo 🚀';
  const options = {
    body: data.body ?? 'Ziggo is now LIVE! Tap to open.',
    icon: '/logo-light.png',
    badge: '/logo-light.png',
    image: data.image,
    data: { url: data.url ?? self.registration.scope },
    vibrate: [200, 100, 200],
    requireInteraction: true,
    actions: [
      { action: 'open', title: 'Open Ziggo 🚀' },
      { action: 'dismiss', title: 'Dismiss' },
    ],
    tag: 'ziggo-launch',
    renotify: true,
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  if (event.action === 'dismiss') return;

  const targetUrl = event.notification.data?.url ?? self.registration.scope;

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clients) => {
        // Focus existing tab if open
        const existing = clients.find((c) => c.url === targetUrl && 'focus' in c);
        if (existing) return existing.focus();
        // Otherwise open new tab
        if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
      })
  );
});
