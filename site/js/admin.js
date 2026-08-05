// admin.js - voxwatch admin page.
// Shows every visitor's tracked films + browser-push status, and sends test
// notifications straight to their browser (via their per-user ntfy topic).

(function () {
  'use strict';

  var SUPABASE_URL = (window.VOXWATCH_SUPABASE && window.VOXWATCH_SUPABASE.url) || '';
  var SUPABASE_KEY = (window.VOXWATCH_SUPABASE && window.VOXWATCH_SUPABASE.anonKey) || '';
  var PASSCODE = (window.VOXWATCH_ADMIN && window.VOXWATCH_ADMIN.passcode) || '';
  var NTFY_SERVER = 'https://ntfy.sh';
  var SITE_URL = 'https://mohamedrwash.github.io/vox-showtimes-monitor/';

  var gate = document.getElementById('admin-gate');
  var panel = document.getElementById('admin-panel');
  var gateMsg = document.getElementById('gate-msg');
  var panelMsg = document.getElementById('panel-msg');
  var msgsBox = document.getElementById('admin-msgs');
  var usersBox = document.getElementById('admin-users');

  var tracks = [];
  var pushStates = {};
  var showtimes = null;

  function $ (id) { return document.getElementById(id); }

  function sb (method, path) {
    return fetch(SUPABASE_URL + '/rest/v1/' + path, {
      method: method,
      headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY }
    });
  }

  function msg (el, text, ok) {
    el.textContent = text;
    el.className = 'admin-msg' + (ok === false ? ' err' : (ok === true ? ' ok' : ''));
  }

  function flash (text, ok) {
    var d = document.createElement('div');
    d.className = 'admin-flash' + (ok === false ? ' err' : '');
    d.textContent = text;
    msgsBox.appendChild(d);
    setTimeout(function () { d.remove(); }, 6000);
  }

  function ntfyPublish (topic, title, message, click) {
    return fetch(NTFY_SERVER + '/' + topic + '/publish', {
      method: 'POST',
      headers: { Title: title, Priority: 'high', Click: click },
      body: message
    });
  }

  function dayLabel (v) {
    if (!v) return 'any day';
    var s = String(v);
    if (s.length !== 8) return v;
    var d = new Date(Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8)));
    return d.toLocaleDateString([], { weekday: 'short', day: '2-digit', month: 'short' });
  }

  function shortId (id) { return id ? id.slice(0, 8) + '…' + id.slice(-4) : '—'; }

  function fmtTime (ts) {
    if (!ts) return '—';
    return new Date(ts).toLocaleString([], { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
  }

  // ---- data ------------------------------------------------------

  function loadAll () {
    var p1 = sb('GET', 'tracks?select=*&order=created_at.asc').then(function (r) { return r.json(); });
    var p2 = sb('GET', 'push_state?select=*').then(function (r) { return r.json(); });
    var p3 = fetch('data/showtimes.json').then(function (r) { return r.ok ? r.json() : null; });
    return Promise.all([p1, p2, p3]).then(function (res) {
      tracks = res[0] || [];
      pushStates = {};
      (res[1] || []).forEach(function (p) { pushStates[p.client_id] = p; });
      showtimes = res[2];
    });
  }

  function render () {
    var users = {};
    tracks.forEach(function (t) {
      (users[t.client_id] = users[t.client_id] || []).push(t);
    });

    var uids = Object.keys(users);
    $('st-users').textContent = uids.length;
    $('st-tracks').textContent = tracks.length;
    $('st-push').textContent = uids.filter(function (id) { return pushStates[id] && pushStates[id].enabled; }).length;
    $('st-available').textContent = showtimes && showtimes.films ? showtimes.films.length : '—';

    usersBox.innerHTML = '';
    if (!uids.length) {
      var none = document.createElement('p');
      none.className = 'admin-note';
      none.textContent = 'no tracked films yet — visitors appear here the moment they track something.';
      usersBox.appendChild(none);
      return;
    }

    uids.forEach(function (uid) {
      var films = users[uid].slice().sort(function (a, b) { return (b.created_at || '').localeCompare(a.created_at || ''); });
      var push = pushStates[uid];
      var card = document.createElement('div');
      card.className = 'admin-user';

      var head = document.createElement('div');
      head.className = 'admin-user-head';
      var who = document.createElement('div');
      who.className = 'admin-user-who';
      var name = document.createElement('span');
      name.className = 'admin-user-id mono-inline';
      name.textContent = shortId(uid);
      name.title = uid;
      var pushChip = document.createElement('span');
      pushChip.className = 'admin-push ' + (push && push.enabled ? 'on' : 'off');
      pushChip.textContent = push && push.enabled ? 'browser notify · on' : 'browser notify · off';
      who.appendChild(name);
      who.appendChild(pushChip);
      var seen = document.createElement('span');
      seen.className = 'admin-user-seen';
      seen.textContent = 'last seen ' + fmtTime(push ? push.updated_at : null);
      head.appendChild(who);
      head.appendChild(seen);

      var list = document.createElement('ul');
      list.className = 'admin-film-list';
      films.forEach(function (t) {
        var li = document.createElement('li');
        li.className = 'admin-film';
        var info = document.createElement('div');
        info.className = 'admin-film-info';
        var title = document.createElement('span');
        title.className = 'admin-film-title';
        title.textContent = t.title || t.slug;
        var meta = document.createElement('span');
        meta.className = 'admin-film-meta';
        meta.textContent = dayLabel(t.day) + ' · ' + (t.cinema || 'default cinema') + ' · tracked ' + fmtTime(t.created_at);
        info.appendChild(title);
        info.appendChild(meta);
        var btn = document.createElement('button');
        btn.className = 'btn btn-ghost admin-ping';
        btn.type = 'button';
        btn.textContent = 'ping';
        btn.addEventListener('click', function () { pingUser(uid, t); });
        li.appendChild(info);
        li.appendChild(btn);
        list.appendChild(li);
      });

      card.appendChild(head);
      card.appendChild(list);
      usersBox.appendChild(card);
    });
  }

  // ---- actions ------------------------------------------------------

  function pingUser (uid, track) {
    var topic = 'voxwatch-u-' + uid;
    var film = track ? (track.title || track.slug) : 'voxwatch';
    var click = track && track.url ? track.url : SITE_URL;
    var title = 'voxwatch - test';
    var message = '[test] you track "' + film + '" - this is a test ping from the admin page. everything works.';
    msg(panelMsg, 'sending test ping to ' + shortId(uid) + ' (' + topic + ')…');
    ntfyPublish(topic, title, message, click).then(function (r) {
      if (r.ok) {
        msg(panelMsg, 'sent ✓ — pinged ' + shortId(uid) + "'s browser", true);
        flash('pinged ' + shortId(uid) + ' — ' + topic);
      } else {
        msg(panelMsg, 'ntfy returned ' + r.status, false);
      }
    }).catch(function () { msg(panelMsg, 'network error', false); });
  }

  function pingSelf () {
    msg(panelMsg, 'enabling notifications for this browser…');
    window.VoxPush.enable().then(function () {
      var topic = window.VoxPush.userTopic();
      return ntfyPublish(topic, 'voxwatch - test', '[test] this browser is receiving pushes.', SITE_URL).then(function (r) {
        if (r.ok) {
          msg(panelMsg, 'sent ✓ — check this browser for the notification (' + topic + ')', true);
        } else {
          msg(panelMsg, 'ntfy returned ' + r.status, false);
        }
      });
    }).catch(function () {
      msg(panelMsg, 'could not enable notifications: ' + window.VoxPush.state.reason, false);
    });
  }

  function pingAll () {
    var uids = tracks.reduce(function (acc, t) {
      if (t.client_id) acc[t.client_id] = true;
      return acc;
    }, {});
    var target = Object.keys(uids).filter(function (id) { return pushStates[id] && pushStates[id].enabled; });
    if (!target.length) { msg(panelMsg, 'no users with browser notifications enabled', false); return; }
    msg(panelMsg, 'pinging ' + target.length + ' user(s)…');
    target.forEach(function (uid, i) {
      setTimeout(function () {
        ntfyPublish('voxwatch-u-' + uid, 'voxwatch - test',
          '[test] broadcast test ping from the admin page.', SITE_URL)
          .then(function (r) { flash((r.ok ? '✓ ' : '✗ ') + shortId(uid), r.ok); })
          .catch(function () { flash('✗ ' + shortId(uid), false); });
      }, i * 400);
    });
    msg(panelMsg, 'pinged ' + target.length + ' user(s) ✓', true);
  }

  function refresh () {
    msg(panelMsg, 'refreshing…');
    loadAll().then(render).then(function () {
      msg(panelMsg, 'synced ' + new Date().toLocaleTimeString(), true);
    }).catch(function () {
      msg(panelMsg, 'failed to load tracks', false);
    });
  }

  // ---- gate ------------------------------------------------------

  function locked () {
    return !PASSCODE || sessionStorage.getItem('voxwatch_admin') !== 'unlocked';
  }

  function applyGate () {
    var isLocked = locked();
    gate.hidden = !isLocked;
    panel.hidden = isLocked;
    if (!isLocked) refresh();
    if (!PASSCODE) {
      gateMsg.textContent = 'admin is disabled — set a passcode in site/js/config.js';
      gateMsg.className = 'admin-msg err';
    }
  }

  document.getElementById('gate-form').addEventListener('submit', function (e) {
    e.preventDefault();
    if (!PASSCODE) return;
    var pass = document.getElementById('gate-pass').value;
    if (pass === PASSCODE) {
      sessionStorage.setItem('voxwatch_admin', 'unlocked');
      applyGate();
    } else {
      msg(gateMsg, 'wrong passcode', false);
    }
  });

  document.getElementById('btn-test-self').addEventListener('click', pingSelf);
  document.getElementById('btn-test-all').addEventListener('click', pingAll);
  document.getElementById('btn-refresh').addEventListener('click', refresh);
  document.getElementById('btn-lock').addEventListener('click', function () {
    sessionStorage.removeItem('voxwatch_admin');
    document.getElementById('gate-pass').value = '';
    applyGate();
  });

  applyGate();
})();
