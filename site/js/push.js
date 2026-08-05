// push.js - browser push notifications for voxwatch (Web Push via ntfy.sh).
// Every browser gets its own private ntfy topic: voxwatch-u-<clientId>.
// The cloud watcher publishes there when a tracked film's chosen day has
// showtimes; ntfy.sh forwards it to THIS browser as a push notification
// (works even when the site tab is closed).
//
// Flow: register sw.js -> pushManager.subscribe with ntfy's VAPID key ->
// POST the subscription to ntfy.sh/v1/webpush for our user topic.

(function () {
  'use strict';

  var NTFY_SERVER = 'https://ntfy.sh';

  var state = {
    enabled: false,
    reason: '',
    supported: typeof window !== 'undefined' &&
      'Notification' in window &&
      'serviceWorker' in navigator &&
      'PushManager' in window
  };

  function clientId () {
    var id = localStorage.getItem('voxwatch_client_id');
    if (!id) {
      id = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : ('anon-' + Math.random().toString(36).slice(2));
      localStorage.setItem('voxwatch_client_id', id);
    }
    return id;
  }

  function userTopic () {
    return 'voxwatch-u-' + clientId();
  }

  function urlBase64ToUint8Array (base64String) {
    var padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    var base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    var raw = window.atob(base64);
    var out = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  function ntfyConfig () {
    // ntfy's VAPID public key is stable; cache it for an hour.
    var cached = null;
    try { cached = JSON.parse(localStorage.getItem('voxwatch_vapid')); } catch (e) {}
    if (cached && cached.at > Date.now() - 3600000) return Promise.resolve(cached.key);
    return fetch(NTFY_SERVER + '/v1/config', { signal: AbortSignal.timeout(10000) })
      .then(function (r) { return r.json(); })
      .then(function (cfg) {
        localStorage.setItem('voxwatch_vapid', JSON.stringify({ at: Date.now(), key: cfg.web_push_public_key }));
        return cfg.web_push_public_key;
      });
  }

  function registerAtNtfy (sub) {
    var j = sub.toJSON();
    var body = JSON.stringify({
      endpoint: j.endpoint,
      p256dh: j.keys.p256dh,
      auth: j.keys.auth,
      topics: [userTopic()]
    });
    var tried = false;
    function post () {
      return fetch(NTFY_SERVER + '/v1/webpush', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body
      }).then(function (r) {
        if (!r.ok) {
          state.reason = 'ntfy error ' + r.status + ', try again later';
          throw state.reason;
        }
        state.reason = '';
        return sub;
      }, function () {
        state.reason = 'ntfy unreachable, try again later';
        throw state.reason;
      });
    }
    // ntfy.sh web-push registration is flaky (transient 500s); retry once.
    return post().catch(function (err) {
      if (tried) throw err;
      tried = true;
      return new Promise(function (resolve) { setTimeout(resolve, 1500); }).then(post);
    });
  }

  function enable () {
    state.reason = '';
    if (!state.supported) { state.reason = 'unsupported'; return Promise.reject(state.reason); }
    if (Notification.permission === 'denied') { state.reason = 'blocked'; return Promise.reject(state.reason); }
    var request = Notification.permission === 'granted'
      ? Promise.resolve('granted')
      : Notification.requestPermission();
    return request.then(function (perm) {
      if (perm !== 'granted') { state.reason = 'declined'; throw state.reason; }
      return navigator.serviceWorker.register('sw.js');
    }).then(function (reg) {
      return ntfyConfig().then(function (vapid) {
        return reg.pushManager.getSubscription().then(function (sub) {
          return sub || reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(vapid)
          });
        });
      });
    }).then(function (sub) {
      return registerAtNtfy(sub);
    }).then(function () {
      state.enabled = true;
      localStorage.setItem('voxwatch_push', 'on');
    });
  }

  function disable () {
    state.enabled = false;
    localStorage.removeItem('voxwatch_push');
    if (state.supported) {
      navigator.serviceWorker.getRegistration().then(function (reg) {
        if (reg) return reg.pushManager.getSubscription();
      }).then(function (sub) {
        if (sub) return sub.unsubscribe();
      }).catch(function () {});
    }
  }

  function restore () {
    // A previous visit left "on" - verify the browser still holds the
    // subscription; silently re-subscribe if it was dropped.
    if (localStorage.getItem('voxwatch_push') !== 'on') return Promise.resolve(false);
    if (!state.supported) return Promise.resolve(false);
    return navigator.serviceWorker.getRegistration().then(function (reg) {
      if (!reg) { localStorage.removeItem('voxwatch_push'); return false; }
      return reg.pushManager.getSubscription().then(function (sub) {
        if (sub) {
          // ntfy may have dropped its copy of the registration (e.g. after
          // push-service failures); re-register idempotently on every visit.
          return registerAtNtfy(sub).catch(function () {}).then(function () {
            state.enabled = true;
            return true;
          });
        }
        localStorage.removeItem('voxwatch_push');
        return enable().then(function () { return true; }).catch(function () { return false; });
      });
    }).catch(function () { return false; });
  }

  window.VoxPush = {
    state: state,
    clientId: clientId,
    userTopic: userTopic,
    enable: enable,
    disable: disable,
    restore: restore
  };
})();
