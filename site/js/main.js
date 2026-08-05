// main.js — voxwatch catalog + live watchlist
// Fetches catalog.json + showtimes.json, renders unified catalog,
// handles track/untrack via ntfy control topic, dialog + QR + copy.

(function () {
  'use strict';

  var CONTROL_TOPIC = 'voxwatch-control';
  var NTFY_SERVER = 'https://ntfy.sh';

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

  var tracked = new Set(); // slugs of films the user has clicked "track"
  var catalog = [];
  var showtimes = null;
  var sourceState = 'loading'; // 'live' | 'snapshot' | 'offline'

  function $ (id) { return document.getElementById(id); }

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

  function renderLedger (films, watchedMap) {
    catalogLedger.innerHTML = '';
    if (!films.length) {
      catalogEmpty.textContent = 'no films in catalog';
      return;
    }
    var frag = document.createDocumentFragment();
    films.forEach(function (film, idx) {
      var slug = film.slug;
      var watched = watchedMap && watchedMap[slug];
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
        label.textContent = 'watching';
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

      row.appendChild(title);
      row.appendChild(status);
      row.appendChild(action);

      row.addEventListener('click', function (e) {
        if (e.target === action) return; // button handles its own click
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

  function toggleTrack (slug, enable) {
    if (enable) {
      tracked.add(slug);
      localStorage.setItem('voxwatch_tracked', JSON.stringify(Array.from(tracked)));
      publishControl('PICK ' + slug);
    } else {
      tracked.delete(slug);
      localStorage.setItem('voxwatch_tracked', JSON.stringify(Array.from(tracked)));
      publishControl('UNPICK ' + slug);
    }
    refreshLedger();
  }

  function publishControl (message) {
    if (!CONTROL_TOPIC) return;
    fetch(NTFY_SERVER + '/' + CONTROL_TOPIC + '/publish', {
      method: 'PUT',
      body: message,
      headers: { 'Content-Type': 'text/plain' }
    }).catch(function () {}); // fire and forget
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
    var watchedMap = {};
    if (showtimes && showtimes.films) {
      showtimes.films.forEach(function (f) { watchedMap[f.slug] = true; });
    }
    // merge tracked into watchedMap so "track" buttons stay pressed
    tracked.forEach(function (s) { watchedMap[s] = true; });
    renderLedger(catalog, watchedMap);
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
    // restore tracked from localStorage
    try {
      var stored = JSON.parse(localStorage.getItem('voxwatch_tracked') || '[]');
      stored.forEach(function (s) { tracked.add(s); });
    } catch (e) {}

    loadCatalog().then(function (cat) {
      catalog = cat.films || [];
      return loadShowtimes();
    }).then(function (st) {
      showtimes = st.data;
      var watchedMap = {};
      if (showtimes && showtimes.films) {
        showtimes.films.forEach(function (f) { watchedMap[f.slug] = true; });
      }
      tracked.forEach(function (s) { watchedMap[s] = true; });
      setStatus(showtimes ? st.source : 'offline', showtimes || { films: [], last_synced: '' });
      setStats(showtimes || { films: [], last_synced: '' });
      renderLedger(catalog, watchedMap);
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