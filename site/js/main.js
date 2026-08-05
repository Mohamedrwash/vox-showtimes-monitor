/* ============================================================
   main.js · voxwatch
   mixed data mode: fetch live showtimes.json (4s timeout),
   fall back to the baked snapshot, then to the static noscript
   ------------------------------------------------------------
   sources: live · snapshot · offline
   ============================================================ */

(function () {
  "use strict";

  var DATA_URL = "data/showtimes.json";
  var FETCH_TIMEOUT = 4000;

  var reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var renderedOnce = false;

  var $ = function (id) { return document.getElementById(id); };

  var navStatus = $("nav-status");
  var statusText = navStatus.querySelector(".status-text");
  var sourceLine = $("source-line");
  var footerStatus = $("footer-status");
  var ledger = $("ledger");
  var ledgerEmpty = $("ledger-empty");
  var dialogEl = $("subscribe-dialog");

  /* ---------- formatting ------------------------------------- */

  function formatTime(h24) {
    var parts = h24.split(":");
    var h = parseInt(parts[0], 10);
    var m = parts[1] || "00";
    var ampm = h >= 12 ? "pm" : "am";
    h = h % 12 || 12;
    return h + ":" + m + " " + ampm;
  }

  function formatSynced(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "—";
    var months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
    var hh = ("0" + d.getHours()).slice(-2);
    var mm = ("0" + d.getMinutes()).slice(-2);
    var day = ("0" + d.getDate()).slice(-2);
    return day + " " + months[d.getMonth()] + " " + hh + ":" + mm;
  }

  /* ---------- data --------------------------------------------- */

  function loadData() {
    return new Promise(function (resolve, reject) {
      var controller = new AbortController();
      var timer = setTimeout(function () { controller.abort(); }, FETCH_TIMEOUT);
      fetch(DATA_URL, { signal: controller.signal, headers: { Accept: "application/json" } })
        .then(function (r) { if (!r.ok) throw new Error("http " + r.status); return r.json(); })
        .then(function (data) { clearTimeout(timer); resolve(data); })
        .catch(function (err) { clearTimeout(timer); reject(err); });
    });
  }

  function snapshotData() {
    var el = document.getElementById("snapshot-data");
    if (!el || !el.textContent.trim()) return null;
    try { return JSON.parse(el.textContent); } catch (e) { return null; }
  }

  /* ---------- rendering ---------------------------------------- */

  function setStatus(source, data) {
    var count = data ? data.films.length : 0;
    var label = count === 1 ? "1 film" : count + " films";
    if (source === "live") {
      navStatus.dataset.state = "live";
      statusText.textContent = "live · " + label;
      sourceLine.dataset.state = "live";
      sourceLine.textContent = "live · synced " + formatSynced(data.last_synced) + " · eest";
      footerStatus.textContent = "watcher: online";
    } else if (source === "snapshot") {
      navStatus.dataset.state = "snapshot";
      statusText.textContent = "snapshot · " + label;
      sourceLine.dataset.state = "snapshot";
      sourceLine.textContent = "snapshot · " + formatSynced(data.last_synced) + " · watcher offline right now";
      footerStatus.textContent = "watcher: offline";
    } else {
      navStatus.dataset.state = "offline";
      statusText.textContent = "offline";
      sourceLine.dataset.state = "offline";
      sourceLine.textContent = "offline · no data";
      footerStatus.textContent = "watcher: unreachable";
    }
  }

  function setStats(data) {
    var n = data.films.length;
    $("c-films").textContent = n;
    $("stat-films").textContent = n;
    $("c-sync").textContent = formatSynced(data.last_synced);
    var angle = Math.min(243, n * 24.3);
    document.querySelector(".dial-needle").style.setProperty("--needle", angle + "deg");
  }

  function nextTimeLabel(film) {
    for (var i = 0; i < film.days.length; i++) {
      if (film.days[i].times.length) return formatTime(film.days[i].times[0].time);
    }
    return "—";
  }

  function renderLedger(films) {
    ledgerEmpty.remove();
    var frag = document.createDocumentFragment();
    films.forEach(function (film, i) {
      var row = document.createElement("div");
      row.className = "ledger-row" + (reducedMotion ? "" : " enter");
      row.style.animationDelay = Math.min(i * 40, 320) + "ms";
      row.tabIndex = 0;
      row.setAttribute("role", "button");
      row.setAttribute("aria-label", "subscribe to " + film.title);

      var title = document.createElement("span");
      title.className = "film-title";
      title.textContent = film.title;

      var cinema = document.createElement("span");
      cinema.className = "film-cinema";
      cinema.textContent = film.cinema;

      var next = document.createElement("span");
      next.className = "film-next";
      next.textContent = nextTimeLabel(film);

      var status = document.createElement("span");
      status.className = "ledger-status";
      var dot = document.createElement("span");
      dot.className = "ledger-dot";
      dot.setAttribute("aria-hidden", "true");
      status.appendChild(dot);
      status.appendChild(document.createTextNode("watching"));

      var chip = document.createElement("button");
      chip.className = "chip";
      chip.type = "button";
      chip.textContent = "notify me";

      row.appendChild(title);
      row.appendChild(cinema);
      row.appendChild(next);
      row.appendChild(status);
      row.appendChild(chip);

      row.addEventListener("click", function () { openDialog(film); });
      row.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openDialog(film); }
      });
      chip.addEventListener("click", function (e) { e.stopPropagation(); openDialog(film); });

      frag.appendChild(row);
    });
    ledger.appendChild(frag);
    renderedOnce = true;
  }

  /* ---------- subscribe dialog ---------------------------------- */

  function openDialog(film) {
    $("dialog-eyebrow").textContent = "tracking · " + film.slug;
    $("dialog-title").textContent = film.title;
    $("dialog-cinema").textContent = film.cinema;

    var timesWrap = $("dialog-times");
    timesWrap.textContent = "";
    var hasTimes = false;
    film.days.forEach(function (day) {
      if (!day.times.length) return;
      hasTimes = true;
      var head = document.createElement("span");
      head.className = "time-chip";
      head.textContent = day.label;
      head.style.borderColor = "var(--color-accent)";
      head.style.color = "var(--color-accent)";
      timesWrap.appendChild(head);
      day.times.forEach(function (t) {
        var chip = document.createElement("span");
        chip.className = "time-chip";
        chip.textContent = formatTime(t.time) + (t.format ? " · " + t.format : "");
        if (t.booking && t.booking.indexOf("http") === 0) {
          var a = document.createElement("a");
          a.href = t.booking;
          a.className = "time-chip";
          a.target = "_blank";
          a.rel = "noopener";
          a.textContent = chip.textContent;
          a.style.textDecoration = "none";
          a.style.color = "var(--color-ink)";
          timesWrap.replaceChild(a, chip);
        } else {
          timesWrap.appendChild(chip);
        }
      });
    });
    if (!hasTimes) {
      var none = document.createElement("span");
      none.className = "time-chip";
      none.textContent = "no showtimes yet — you\u2019ll be pinged first";
      timesWrap.appendChild(none);
    }

    var topic = film.topic;
    var url = "https://ntfy.sh/" + topic;
    $("dialog-topic").textContent = topic;
    var link = $("dialog-link");
    link.href = url;

    renderQr(url);

    var copyBtn = $("dialog-copy");
    copyBtn.textContent = "copy";
    copyBtn.classList.remove("copied");
    copyBtn.onclick = function () {
      var done = function () {
        copyBtn.textContent = "copied";
        copyBtn.classList.add("copied");
        setTimeout(function () {
          copyBtn.textContent = "copy";
          copyBtn.classList.remove("copied");
        }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(topic).then(done, function () { fallbackCopy(topic, done); });
      } else {
        fallbackCopy(topic, done);
      }
    };

    dialogEl.classList.remove("closing");
    if (typeof dialogEl.showModal === "function") dialogEl.showModal();
  }

  function fallbackCopy(text, done) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch (e) { }
    document.body.removeChild(ta);
    done();
  }

  function closeDialog() {
    if (!dialogEl.open) return;
    dialogEl.classList.add("closing");
    setTimeout(function () {
      dialogEl.classList.remove("closing");
      if (dialogEl.open) dialogEl.close();
    }, 160);
  }

  function renderQr(text) {
    var holder = $("dialog-qr");
    holder.textContent = "";
    if (typeof qrcode === "undefined") return;
    var qr;
    try {
      qr = qrcode(0, "M");
      qr.addData(text);
      qr.make();
    } catch (e) { return; }
    var moduleColor = getComputedStyle(document.documentElement)
      .getPropertyValue("--color-qr-module").trim() || "#2a2530";
    var svg = qr.createSvgTag({ cellSize: 4, margin: 1, scalable: true });
    svg = svg.replace(/fill="(?:#000|#000000|black)"/g, 'fill="' + moduleColor + '"');
    holder.innerHTML = svg;
    holder.querySelector("svg").setAttribute("aria-hidden", "true");
  }

  dialogEl.addEventListener("click", function (e) {
    if (e.target === dialogEl) closeDialog();
  });
  dialogEl.addEventListener("cancel", function (e) {
    e.preventDefault();
    closeDialog();
  });
  $("dialog-close").addEventListener("click", closeDialog);

  /* ---------- boot ---------------------------------------------- */

  loadData()
    .then(function (data) {
      if (!data || !Array.isArray(data.films) || !data.films.length) throw new Error("empty payload");
      setStatus("live", data);
      setStats(data);
      renderLedger(data.films);
    })
    .catch(function () {
      var snap = snapshotData();
      if (snap && Array.isArray(snap.films) && snap.films.length) {
        setStatus("snapshot", snap);
        setStats(snap);
        renderLedger(snap.films);
      } else {
        setStatus("offline", null);
        ledgerEmpty.textContent = "no data available";
      }
    });
})();
