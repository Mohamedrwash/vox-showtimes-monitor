// main.js — voxwatch catalog + live watchlist
// Fetches catalog.json + showtimes.json, renders unified catalog,
// handles track/untrack + chosen day via Supabase, dialog + QR + copy.

(function () {
  'use strict';

  var SUPABASE_URL = (window.VOXWATCH_SUPABASE && window.VOXWATCH_SUPABASE.url) || '';
  var SUPABASE_KEY = (window.VOXWATCH_SUPABASE && window.VOXWATCH_SUPABASE.anonKey) || '';
  var DEFAULT_CINEMA = 'City Centre Almaza';

  var catalogLedger = document.getElementById('catalog-ledger');
  var catalogEmpty = document.getElementById('catalog-empty');
  var navStatus = document.getElementById('nav-status');
  var statusText = document.querySelector('.status-text');
  var sourceLine = document.getElementById('source-line');
  var footerStatus = document.getElementById('footer-status');
  var filmsCount = document.getElementById('c-films');
  var syncText = document.getElementById('c-sync');
  var dialog = document.getElementById('subscribe-dialog');
  var dialogTitle = document.getElementById('dialog-title');
  var dialogCinema = document.getElementById('dialog-cinema');
  var dialogTimes = document.getElementById('dialog-times');
  var dialogQR = document.getElementById('dialog-qr');
  var dialogLink = document.getElementById('dialog-link');
  var dialogTopic = document.getElementById('dialog-topic');
  var dialogCopy = document.getElementById('dialog-copy');
  var dialogClose = document.getElementById('dialog-close');

  var DATA_URL = 'data/showtimes.json';
  var CATALOG_URL = 'data/catalog.json';
  var SNAPSHOT = document.getElementById('snapshot-data');
  var CATALOG_SNAPSHOT = document.getElementById('snapshot-catalog');

  var tracked = {}; // slug → chosen day ('' = any day), THIS browser only
  var selectedDays = {}; // pending day selection per slug before tracking
  var catalog = [];
  var showtimes = null;
  var sourceState = 'loading'; // 'live' | 'snapshot' | 'offline'

  var DAYS = dayOptions();

  // ---- browser notifications (bell) ------------------------------

  var bellBtn = document.getElementById('nav-bell');
  var bellLabel = document.getElementById('nav-bell-label');
  var pushToast = document.getElementById('push-toast');
  var toastTimer = null;

  function recordPushState (enabled) {
    if (!SUPABASE_URL) return;
    return fetch(SUPABASE_URL + '/rest/v1/push_state?on_conflict=client_id', {
      method: 'POST',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: 'Bearer ' + SUPABASE_KEY,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates'
      },
      body: JSON.stringify({
        client_id: clientId(),
        enabled: enabled,
        updated_at: new Date().toISOString()
      })
    }).catch(function () {});
  }

  function renderBell () {
    if (!bellBtn) return;
    if (window.VoxPush.state.enabled) {
      bellBtn.dataset.state = 'on';
      bellLabel.textContent = 'notify on';
      bellBtn.title = 'browser notifications on - click to turn off';
      bellBtn.setAttribute('aria-label', 'turn off browser notifications');
    } else {
      bellBtn.dataset.state = 'off';
      bellLabel.textContent = 'notify';
      bellBtn.title = window.VoxPush.state.reason
        ? 'notifications unavailable (' + window.VoxPush.state.reason + ')'
        : 'enable browser notifications';
      bellBtn.setAttribute('aria-label', 'enable browser notifications');
    }
  }

  function showToast (text) {
    if (!pushToast) return;
    pushToast.textContent = text;
    pushToast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { pushToast.classList.remove('show'); }, 4000);
  }

  function toggleBell () {
    if (window.VoxPush.state.enabled) {
      window.VoxPush.disable();
      recordPushState(false);
      renderBell();
      return;
    }
    bellBtn.disabled = true;
    window.VoxPush.enable().then(function () {
      recordPushState(true);
      showToast('browser notifications on');
    }).catch(function () {
      showToast('notifications off - ' + window.VoxPush.state.reason);
    }).then(function () {
      bellBtn.disabled = false;
      renderBell();
    });
  }

  function offerNotifications () {
    // First track: prompt for browser notifications if the browser hasn't
    // decided yet. Never re-prompt after a denial.
    if (!window.VoxPush.state.supported) return;
    if (Notification.permission !== 'default') return;
    window.VoxPush.enable().then(function () {
      recordPushState(true);
    }).catch(function () {
      recordPushState(false);
    }).then(renderBell);
  }

  function $ (id) { return document.getElementById(id); }

  function clientId () { return window.VoxPush.clientId(); }

  // ---- visitor device info (admin groups users by phone / pc) ------

  function detectDevice () {
    var ua = navigator.userAgent || '';
    var data = navigator.userAgentData;
    var type = 'desktop';
    var model = '';
    var browser = 'other';

    if (data && data.mobile) type = 'mobile';
    if (data && data.brands) {
      var brand = data.brands.map(function (b) { return b.brand; }).join(' ');
      if (brand.indexOf('Firefox') >= 0) browser = 'firefox';
      else if (brand.indexOf('Edge') >= 0) browser = 'edge';
      else if (brand.indexOf('Opera') >= 0) browser = 'opera';
      else if (brand.indexOf('Samsung') >= 0) browser = 'samsung';
      else if (brand.indexOf('Chrome') >= 0) browser = 'chrome';
    }

    if (/iPhone/i.test(ua)) { type = 'mobile'; model = 'iPhone'; }
    else if (/iPad/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) {
      type = 'tablet'; model = 'iPad';
    } else if (/Android/i.test(ua)) {
      type = 'mobile';
      var m = ua.match(/;\s*([^;)]+)\s+Build\//);
      if (m) model = m[1].trim();
    } else if (/Windows/i.test(ua)) model = 'Windows';
    else if (/Macintosh/i.test(ua)) model = 'Mac';
    else if (/Linux/i.test(ua)) model = 'Linux';

    if (browser === 'other') {
      if (/Edg\//i.test(ua)) browser = 'edge';
      else if (/OPR\//i.test(ua)) browser = 'opera';
      else if (/SamsungBrowser/i.test(ua)) browser = 'samsung';
      else if (/CriOS/i.test(ua)) browser = 'chrome';
      else if (/FxiOS/i.test(ua)) browser = 'firefox';
      else if (/Firefox\//i.test(ua)) browser = 'firefox';
      else if (/Safari\//i.test(ua)) browser = 'safari';
    }

    return { type: type, model: model, browser: browser };
  }

  function recordDevice () {
    if (!SUPABASE_URL) return;
    var d = detectDevice();
    return fetch(SUPABASE_URL + '/rest/v1/devices?on_conflict=client_id', {
      method: 'POST',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: 'Bearer ' + SUPABASE_KEY,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates'
      },
      body: JSON.stringify({
        client_id: clientId(),
        device_type: d.type,
        browser: d.browser,
        device_model: d.model,
        updated_at: new Date().toISOString()
      })
    }).catch(function () {});
  }

  function dayOptions () {
    var out = [{ value: '', label: 'any' }];
    var d = new Date();
    d.setDate(d.getDate() + 1);
    for (var i = 0; i < 7; i++) {
      var v = String(d.getFullYear()) + String(d.getMonth() + 1).padStart(2, '0') + String(d.getDate()).padStart(2, '0');
      out.push({ value: v, label: d.toLocaleDateString([], { weekday: 'short', day: '2-digit' }) });
      d.setDate(d.getDate() + 1);
    }
    return out;
  }

  function dayLabel (v) {
    for (var i = 0; i < DAYS.length; i++) if (DAYS[i].value === v) return DAYS[i].label;
    return 'any day';
  }

  function sb (method, path, body) {
    return fetch(SUPABASE_URL + '/rest/v1/' + path, {
      method: method,
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: 'Bearer ' + SUPABASE_KEY,
        'Content-Type': 'application/json'
      },
      body: body ? JSON.stringify(body) : undefined
    });
  }

  function formatSynced (ts) {
    if (!ts) return '—';
    var d = new Date(ts);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  function setStatus (source, data) {
    var count = data ? data.films.length : 0;
    var label = count === 1 ? '1 film' : count + ' films';
    if (source === 'live') {
      navStatus.dataset.state = 'live';
      statusText.textContent = 'live · ' + label;
      sourceLine.dataset.state = 'live';
      sourceLine.textContent = 'live · synced ' + formatSynced(data.last_synced) + ' · eest';
      footerStatus.textContent = 'watcher: online';
    } else if (source === 'snapshot') {
      navStatus.dataset.state = 'snapshot';
      statusText.textContent = 'snapshot · ' + label;
      sourceLine.dataset.state = 'snapshot';
      sourceLine.textContent = 'snapshot · ' + formatSynced(data.last_synced) + ' · watcher offline right now';
      footerStatus.textContent = 'watcher: offline';
    } else {
      navStatus.dataset.state = 'offline';
      statusText.textContent = 'offline';
      sourceLine.dataset.state = 'offline';
      sourceLine.textContent = 'offline · no data';
      footerStatus.textContent = 'watcher: unreachable';
    }
    sourceState = source;
  }

  function setStats (data) {
    var n = data ? data.films.length : 0;
    filmsCount.textContent = n;
    var angle = Math.min(243, n * 24.3);
    document.querySelector('.dial-needle').style.setProperty('--needle', angle + 'deg');
    syncText.textContent = formatSynced(data ? data.last_synced : '');
  }
  function renderLedger (films, watchedMap, daySel) {
    catalogLedger.innerHTML = '';
    if (!films.length) {
      catalogEmpty.textContent = 'no films in catalog';
      return;
    }
    var frag = document.createDocumentFragment();
    films.forEach(function (film, idx) {
      var slug = film.slug;
      var watched = watchedMap && watchedMap[slug] !== undefined;
      var row = document.createElement('div');
      row.className = 'ledger-row' + (document.documentElement.classList.contains('reduce-motion') ? '' : ' enter');
      row.style.animationDelay = Math.min(idx * 40, 320) + 'ms';
      row.tabIndex = 0;
      row.setAttribute('role', 'button');
      row.setAttribute('aria-label', 'track ' + film.title);

      var title = document.createElement('span');
      title.className = 'film-title';
      title.textContent = film.title;

      var status = document.createElement('span');
      status.className = 'ledger-status';
      var dot = document.createElement('span');
      dot.className = 'ledger-dot';
      dot.setAttribute('aria-hidden', 'true');
      var label = document.createElement('span');
      if (watched) {
        label.textContent = 'watching · ' + dayLabel(watchedMap[slug]);
        status.classList.add('watching');
      } else {
        label.textContent = 'pick me';
        status.classList.add('not-watching');
      }
      status.appendChild(dot);
      status.appendChild(label);

      var action = document.createElement('button');
      action.className = 'chip';
      action.type = 'button';
      action.textContent = watched ? 'untrack' : 'track';
      action.dataset.slug = film.slug;

      var strip = document.createElement('div');
      strip.className = 'day-strip';
      DAYS.forEach(function (opt) {
        var chip = document.createElement('button');
        chip.className = 'day-chip';
        chip.type = 'button';
        chip.textContent = opt.label;
        var active = daySel && daySel[slug] === opt.value;
        if (active) chip.classList.add('active');
        chip.setAttribute('aria-pressed', active ? 'true' : 'false');
        chip.setAttribute('aria-label', 'notify me ' + opt.label + ' for ' + film.title);
        chip.addEventListener('click', function (e) {
          e.stopPropagation();
          pickDay(slug, opt.value);
        });
        strip.appendChild(chip);
      });

      row.appendChild(title);
      row.appendChild(status);
      row.appendChild(action);
      row.appendChild(strip);

      row.addEventListener('click', function (e) {
        if (e.target === action || e.target.closest('.day-chip')) return; // button/chips handle their own clicks
        openDialog(film.slug);
      });

      row.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openDialog(film.slug); }
      });

      action.addEventListener('click', function (e) {
        e.stopPropagation();
        toggleTrack(film.slug, !watched);
      });

      frag.appendChild(row);
    });
    catalogLedger.appendChild(frag);
  }

  function pickDay (slug, v) {
    selectedDays[slug] = v;
    if (tracked[slug] !== undefined) {
      var old = tracked[slug];
      tracked[slug] = v;
      localStorage.setItem('voxwatch_tracks', JSON.stringify(tracked));
      sb('PATCH', 'tracks?slug=eq.' + encodeURIComponent(slug) + '&client_id=eq.' + encodeURIComponent(clientId()), { day: v })
        .catch(function () { tracked[slug] = old; refreshLedger(); });
    }
    refreshLedger();
  }

  function toggleTrack (slug, enable) {
    var film = catalog.find(function (f) { return f.slug === slug; });
    if (enable) {
      offerNotifications();
      var day = selectedDays[slug] || '';
      tracked[slug] = day;
      localStorage.setItem('voxwatch_tracks', JSON.stringify(tracked));
      sb('POST', 'tracks', {
        slug: slug,
        title: film ? film.title : slug,
        url: film ? film.url : ('https://egy.voxcinemas.com/movies/' + slug),
        cinema: DEFAULT_CINEMA,
        topic: 'voxwatch-' + slug,
        day: day,
        client_id: clientId()
      }).catch(function () { delete tracked[slug]; refreshLedger(); });
    } else {
      delete tracked[slug];
      localStorage.setItem('voxwatch_tracks', JSON.stringify(tracked));
      sb('DELETE', 'tracks?slug=eq.' + encodeURIComponent(slug) + '&client_id=eq.' + encodeURIComponent(clientId()))
        .catch(function () {});
    }
    refreshLedger();
  }

  function loadMyTracks () {
    if (!SUPABASE_URL) return Promise.resolve();
    return sb('GET', 'tracks?select=slug,day&client_id=eq.' + encodeURIComponent(clientId()))
      .then(function (r) { return r.json(); })
      .then(function (rows) {
        rows.forEach(function (row) { tracked[row.slug] = row.day || ''; });
      }).catch(function () {});
  }

  function openDialog (slug) {
    var film = catalog.find(function (f) { return f.slug === slug; });
    if (!film) return;
    var watched = showtimes && showtimes.films.some(function (f) { return f.slug === slug; });
    var filmData = watched ? showtimes.films.find(function (f) { return f.slug === slug; }) : film;

    dialogTitle.textContent = filmData.title;
    dialogCinema.textContent = filmData.cinema || 'default cinema';
    dialogTopic.textContent = filmData.topic;
    dialogLink.href = 'https://ntfy.sh/' + filmData.topic;
    dialogLink.setAttribute('href', 'https://ntfy.sh/' + filmData.topic);

    var timesHtml = '';
    if (filmData.days && filmData.days.length) {
      filmData.days.forEach(function (day) {
        if (day.times && day.times.length) {
          day.times.forEach(function (t) {
            var fmt = t.format ? ' [' + t.format + ']' : '';
            var link = t.booking ? '<a href="' + t.booking + '" target="_blank" rel="noopener" class="time-chip-link">' + t.time + fmt + '</a>' : '<span class="time-chip">' + t.time + fmt + '</span>';
            timesHtml += link;
          });
        }
      });
    }
    if (!timesHtml) timesHtml = '<span class="time-chip">no showtimes yet</span>';
    dialogTimes.innerHTML = timesHtml;

    // QR
    var moduleColor = getComputedStyle(document.documentElement).getPropertyValue('--color-qr-module').trim() || '#2a2530';
    var qr = qrcode(0, 'M');
    qr.addData('https://ntfy.sh/' + filmData.topic);
    qr.make();
    var svg = qr.createSvgTag({ cellSize: 4, margin: 1, scalable: true });
    svg = svg.replace(/fill="(?:#000|#000000|black)"/g, 'fill="' + moduleColor + '"');
    dialogQR.innerHTML = svg;

    dialog.showModal();
  }

  function closeDialog () {
    dialog.classList.add('closing');
    setTimeout(function () {
      dialog.close();
      dialog.classList.remove('closing');
    }, 160);
  }

  dialogClose.addEventListener('click', closeDialog);
  dialog.addEventListener('cancel', function (e) { e.preventDefault(); closeDialog(); });
  dialog.addEventListener('click', function (e) {
    if (e.target === dialog) closeDialog();
  });

  dialogCopy.addEventListener('click', function () {
    var text = dialogTopic.textContent;
    if (!navigator.clipboard) { fallbackCopy(text); return; }
    navigator.clipboard.writeText(text).then(
      function () { done(); },
      function () { fallbackCopy(text); }
    );
    function fallbackCopy (t) {
      var ta = document.createElement('textarea');
      ta.value = t; ta.setAttribute('readonly', ''); ta.style.position = 'absolute'; ta.style.left = '-9999px';
      document.body.appendChild(ta); ta.select(); document.execCommand('copy'); document.body.removeChild(ta);
      done();
    }
    function done () {
      dialogCopy.textContent = 'copied';
      dialogCopy.classList.add('copied');
      setTimeout(function () { dialogCopy.textContent = 'copy'; dialogCopy.classList.remove('copied'); }, 1800);
    }
  });

  function refreshLedger () {
    renderLedger(catalog, tracked, selectedDays);
  }

  function loadCatalog () {
    return fetch(CATALOG_URL, { signal: AbortSignal.timeout(4000) })
      .then(function (r) { return r.json(); })
      .catch(function () {
        var snap = CATALOG_SNAPSHOT ? JSON.parse(CATALOG_SNAPSHOT.textContent) : null;
        return snap || { films: [] };
      });
  }

  function loadShowtimes () {
    return fetch(DATA_URL, { signal: AbortSignal.timeout(4000) })
      .then(function (r) {
        if (!r.ok) throw new Error('http ' + r.status);
        return r.json().then(function (j) { return { source: 'live', data: j }; });
      })
      .catch(function () {
        var snap = SNAPSHOT ? JSON.parse(SNAPSHOT.textContent) : null;
        return { source: 'snapshot', data: snap };
      });
  }

  function init () {
    if (bellBtn) bellBtn.addEventListener('click', toggleBell);

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.addEventListener('message', function (e) {
        if (e.data && e.data.type === 'voxwatch-push-shown') {
          showToast('pinged: ' + e.data.title);
        }
      });
    }

    window.VoxPush.restore().then(function () {
      renderBell();
    });

    recordDevice();

    // restore my tracks from localStorage (optimistic UI, server re-syncs)
    try {
      var cache = JSON.parse(localStorage.getItem('voxwatch_tracks') || '{}');
      Object.keys(cache).forEach(function (s) { tracked[s] = cache[s]; });
      renderLedger(catalog, tracked, selectedDays);
    } catch (e) {}

    loadCatalog().then(function (cat) {
      catalog = cat.films || [];
      return loadMyTracks();
    }).then(function () {
      return loadShowtimes();
    }).then(function (st) {
      showtimes = st.data;
      setStatus(showtimes ? st.source : 'offline', showtimes || { films: [], last_synced: '' });
      setStats(showtimes || { films: [], last_synced: '' });
      renderLedger(catalog, tracked, selectedDays);
    }).catch(function () {
      setStatus('offline', null);
      catalogEmpty.textContent = 'failed to load catalog';
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // reduced-motion detection
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.documentElement.classList.add('reduce-motion');
  }
})();