'use strict';
/* ---------------------------------------------------------------------------
   Service worker — for checklist reminders only.

   Phones (Android Chrome, and iPhones with the app added to the home screen)
   only show a system notification through a service worker, so the page
   registers this one and calls registration.showNotification().

   It caches nothing and handles no fetch: the app works exactly as it does
   without it. Tapping a reminder brings the app forward on the Checklist
   page, or opens it there.
   --------------------------------------------------------------------------- */

self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });

self.addEventListener('notificationclick', function (e) {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
    for (var i = 0; i < list.length; i++) {
      if ('focus' in list[i]) {
        list[i].postMessage({ open: 'chk' });
        return list[i].focus();
      }
    }
    return self.clients.openWindow('/#chk');
  }));
});
