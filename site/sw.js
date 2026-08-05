// sw.js - voxwatch service worker.
// Shows browser push notifications forwarded by ntfy.sh (Web Push API) when
// the cloud watcher publishes to this browser's private topic. The payload is
// ntfy's JSON format: { title, message, click, topic, ... }.
// Also notifies open tabs (postMessage) so the page can react to pings.

self.addEventListener('push', function (event) {
  var payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch (e) {}
  var title = payload.title || 'voxwatch';
  var message = payload.message || 'a film you track is available';
  var click = payload.click || payload.url || null;
  var tag = 'voxwatch-' + (payload.topic || 'alert');
  var options = {
    body: message,
    tag: tag,
    renotify: true,
    data: { url: click }
  };
  event.waitUntil(
    self.registration.showNotification(title, options).then(function () {
      return self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
        list.forEach(function (client) {
          client.postMessage({ type: 'voxwatch-push-shown', title: title, message: message });
        });
      });
    })
  );
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var url = event.notification.data && event.notification.data.url;
  if (!url) return;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      for (var i = 0; i < list.length; i++) {
        if (new URL(list[i].url).pathname === new URL(url).pathname) return list[i].focus();
      }
      return self.clients.openWindow(url);
    })
  );
});
