// Service worker: viser push-notifikationer og åbner appen, når man trykker på dem.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  const d = e.data ? e.data.json() : {};
  e.waitUntil(self.registration.showNotification(d.title || 'Folke-App', {
    body: d.body || '', icon: '/icon.png', badge: '/icon.png', data: {url: d.url || '/'},
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = e.notification.data.url;
  e.waitUntil(self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(list => {
    for (const c of list) if ('focus' in c) { c.navigate(url); return c.focus(); }
    return self.clients.openWindow(url);
  }));
});
