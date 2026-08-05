# REPLICATION PROMPT â€” Vox Showtimes Monitor (multi-film + voxwatch site)

> Paste everything below the line into any AI coding assistant to rebuild this
> project from scratch. It is fully self-contained â€” no external files needed.

â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

You are building a complete, GitHub-ready project: a multi-film showtimes
monitor for the Vox Cinemas website (https://egy.voxcinemas.com) plus a small
static site ("voxwatch") that lets visitors pick a film and subscribe to that
film's public push topic.

## GOAL

A config-driven bash script that:

- Watches ANY number of movie pages (one line per film in movies.conf) at a
  configurable cinema each
- Checks every 5 minutes (cron on Linux/macOS, Windows Task Scheduler on Windows)
- Detects when showtimes appear / change / disappear per film
- Publishes every film's alerts to its own public ntfy topic (`voxwatch-<slug>`)
  â€” this is the visitor channel â€” and mirrors them to the owner's personal
  channels (Pushover / Telegram / Discord / Email / Gotify / private ntfy topic)
- Writes `site/data/showtimes.json` after every run (atomic) so the voxwatch
  site is live while the monitor runs
- Ships with a static site (index.html + css + js) that renders the watchlist
  from that JSON (live fetch, snapshot fallback), a subscribe dialog per film
  with a QR code of `https://ntfy.sh/voxwatch-<slug>`, and honest copy
- Ships with a full README and docs so anyone can download and use it

## SITE STRUCTURE (verify against the live site before coding)

The movie page at https://egy.voxcinemas.com/movies/<slug> contains:

1. Day-tab links in this format (note the HTML-encoded equals sign `&#x3D;`):

   `<a href="/movies/the-odyssey?d&#x3D;20260805#showtimes">Tomorrow</a>`
   `<a href="/movies/the-odyssey?d&#x3D;20260806#showtimes">Thu 06 Aug</a>`

   The default page (no `d=`) shows TODAY. Each tab is a date `d=YYYYMMDD`.

2. Showtimes are grouped per cinema inside
   `<h3 class="highlight">CINEMA NAME</h3>` sections. Within a cinema section,
   a `<strong>IMAX</strong>` / `<strong>GOLD</strong>` / `<strong>Standard</strong>`
   label precedes an `<ol>`, and each showtime is one of:

   - AVAILABLE: `<a class="action showtime" href="https://egy.voxcinemas.com/booking/ID" data-id="ID">7:00pm </a>`
   - UNAVAILABLE: `<span class="action showtime unavailable">7:15pm</span>`

3. To get a specific day's showtimes, fetch `MOVIE_URL?d=YYYYMMDD`.

4. ONLY `<a class="action showtime">` elements are bookable. Ignore the
   `<span class="action showtime unavailable">` ones entirely.

## PROJECT STRUCTURE (create exactly this)

```
vox-showtimes-monitor/
â”œâ”€â”€ README.md
â”œâ”€â”€ LICENSE                 (MIT)
â”œâ”€â”€ .gitignore              (ignore *.log, .known_showtimes*, .heartbeat,
â”‚                            .fail_flag*, .last_digest*, .json_tmp/,
â”‚                            monitor.conf, movies.conf)
â”œâ”€â”€ monitor.conf            (user's active config - gitignored)
â”œâ”€â”€ monitor.conf.example    (template - committed)
â”œâ”€â”€ movies.conf             (user's film watchlist - gitignored)
â”œâ”€â”€ movies.conf.example     (template - committed)
â”œâ”€â”€ src/
â”‚   â””â”€â”€ vox-monitor.sh      (the main script)
â”œâ”€â”€ scripts/
â”‚   â”œâ”€â”€ install-cron.sh         (Linux/macOS installer)
â”‚   â”œâ”€â”€ install-windows.ps1     (Windows Task Scheduler installer)
â”‚   â”œâ”€â”€ run_monitor_hidden.vbs  (hidden wrapper - no console flash)
â”‚   â””â”€â”€ run_digest_hidden.vbs
â”œâ”€â”€ site/
â”‚   â”œâ”€â”€ index.html          (voxwatch static page)
â”‚   â”œâ”€â”€ css/tokens.css      (design tokens: oklch palette, fonts, spacing)
â”‚   â”œâ”€â”€ css/style.css       (page styles)
â”‚   â”œâ”€â”€ js/main.js          (fetch JSON, render ledger, dialog + QR + copy)
â”‚   â”œâ”€â”€ js/vendor/qrcode.js (vendored qrcode-generator@1.4.4, MIT)
â”‚   â””â”€â”€ data/showtimes.json (WRITTEN BY THE MONITOR every run; commit a
â”‚                            baked snapshot copy so the site works offline)
â””â”€â”€ docs/
    â”œâ”€â”€ INSTALL.md
    â”œâ”€â”€ NOTIFICATIONS.md
    â”œâ”€â”€ CHANGE_MOVIE.md
    â””â”€â”€ FAQ.md
```

## CONFIG FILES

### monitor.conf / monitor.conf.example

Global settings + the owner's personal channels. Same variable names in both
files; the example file uses YOUR_ placeholders.

- `WRITE_SITE_DATA=true` â€” write site/data/showtimes.json each run
- `SITE_DATA_DIR` â€” default `$SCRIPT_DIR/../site/data`; not required to set
- `CHECK_INTERVAL=300` (seconds; used in docs/heartbeat hint)
- `HEARTBEAT_TIMEOUT=900` (alert if a run is missed this long)
- `IGNORE_TODAY_TOMORROW=true` (only monitor days AFTER tomorrow)
- `ENABLE_DIGEST=true`
- `USE_NTFY=true` â€” powers the public per-film topics; `NTFY_TOPIC` is an
  optional PRIVATE mirror topic (e.g. `voxwatch-owner-mysecret`), plus
  `NTFY_SERVER="https://ntfy.sh"`, `NTFY_PRIORITY="high"`, `NTFY_TAGS`
- Owner channels (all optional): `USE_PUSHOVER` / `PUSHOVER_USER_KEY` /
  `PUSHOVER_API_TOKEN`; `USE_TELEGRAM` / `TELEGRAM_BOT_TOKEN` /
  `TELEGRAM_CHAT_ID`; `USE_DISCORD` / `DISCORD_WEBHOOK_URL`; `USE_EMAIL` /
  `EMAIL_ADDRESS`; `USE_GOTIFY` / `GOTIFY_SERVER` / `GOTIFY_TOKEN` /
  `GOTIFY_PRIORITY`

The script must source monitor.conf with safe defaults for unset vars
(use `${VAR:-default}`) and support a `VOX_CONF` env var override.

### movies.conf / movies.conf.example

The watchlist. ONE FILM PER LINE:

```
# slug|Display Name|Cinema Name|Full Vox movie URL
the-odyssey|The Odyssey|City Centre Almaza|https://egy.voxcinemas.com/movies/the-odyssey
```

- `slug` is URL-safe (lowercase, hyphens) and becomes the public topic
  `voxwatch-<slug>`. Pick stable slugs â€” changing one breaks visitor
  subscriptions.
- Cinema name must match the page heading exactly.
- Lines starting with `#` and empty lines are ignored.

## SCRIPT BEHAVIOR (src/vox-monitor.sh)

1. Compute SCRIPT_DIR from the script's own location. Look for monitor.conf in
   SCRIPT_DIR, then SCRIPT_DIR/.. and movies.conf likewise (`VOX_MOVIES` env
   var override). Exit with a friendly error if missing.
2. All logs/state files live next to the script: `vox_showtimes.log`,
   `.heartbeat`, and PER-FILM files `.known_showtimes_<slug>`,
   `.fail_flag_<slug>`, `.last_digest_<slug>`, plus a `.json_tmp/` work dir.
3. Helpers:
   - `log_message()`: writes timestamped lines to LOG_FILE, prefixed with the
     film name.
   - `fetch_url()`: curl with `--max-time 30`, captures HTTP code, returns 0
     only on HTTP 200 + non-empty body, else 1.
   - `extract_available(html, cinema)`: awk that finds the cinema section,
     walks the `<strong>FORMAT</strong>` blocks and prints
     `TIME|FORMAT|https://egy.voxcinemas.com/booking/ID` for every
     `<a class="action showtime">` line only â€” never the unavailable spans.
4. Per-film monitoring pass (`monitor_film slug name cinema url`):
   - fetch base page; if unreachable, log + send "site unreachable" alert at
     most once per 30 minutes (gate on `.fail_flag_<slug>` mtime), continue.
   - Parse ALL day tabs from the page (date|label pairs).
   - If `IGNORE_TODAY_TOMORROW=true`, skip every tab date <= tomorrow.
   - For each remaining date, fetch `?d=DATE` and run extract_available.
   - Build CURRENT_SUMMARY (human lines `LABEL (DATE): TIME [FORMAT] -> LINK`)
     and CURRENT_SIG (machine string `%DATE=TIME1,TIME2,...` sorted).
   - If `.known_showtimes_<slug>` does not exist: write CURRENT_SIG, publish a
     "monitor started" notification to the PUBLIC topic `voxwatch-<slug>` AND
     mirror to owner channels, then continue.
   - Otherwise compare CURRENT_SIG with the known file. If different: publish
     "NEW SHOWTIME SCHEDULE" to the public topic + mirror, write new state.
     If identical, just log "No change".
   - Edge case: no future days found -> CURRENT_SIG="none".
5. Notification senders: public ntfy topic is always targeted with the film's
   topic; owner channels get the mirror (including a private ntfy mirror when
   `NTFY_TOPIC` is set). Each sender: if flag + creds present, send via curl,
   log "X sent" or "X failed"; otherwise silently skip. ntfy uses headers
   `Title:`, `Priority:`, `Tags:`, `Click: <first booking link>` with the body
   on stdin. `notify_all()` tracks success; if ALL fail, append the message to
   LOG_FILE as fallback.
6. Heartbeat: write current epoch to `.heartbeat` every run; if the previous
   heartbeat is older than HEARTBEAT_TIMEOUT, send a "monitor missed runs"
   alert to owner channels.
7. Digest mode (`vox-monitor.sh digest`): once per day per film (gate:
   `.last_digest_<slug>` equal to today's date), fetch today + tomorrow,
   summarize showtimes, send a "DAILY DIGEST" notification, then exit.
8. Site data: after the per-film loop, if `WRITE_SITE_DATA=true`, build
   `showtimes.json` from the per-film results (see JSON contract below),
   write to `$SITE_DATA_DIR/.showtimes.tmp`, then `mv` over
   `showtimes.json` (atomic).
9. Main pass: heartbeat check first, then loop over every line of movies.conf
   (strip comments/blanks), then write site data.

## SITE DATA JSON CONTRACT (site/data/showtimes.json)

```json
{
  "last_synced": "2026-08-04T23:51:00+03:00",
  "films": [
    {
      "slug": "the-odyssey",
      "title": "The Odyssey",
      "cinema": "City Centre Almaza",
      "url": "https://egy.voxcinemas.com/movies/the-odyssey",
      "topic": "voxwatch-the-odyssey",
      "watched": true,
      "checked_at": "2026-08-04T23:51:00+03:00",
      "days": [
        {
          "date": "20260806",
          "label": "Thu 06",
          "times": [
            { "time": "11:15", "format": "2D", "booking": "" },
            { "time": "20:30", "format": "IMAX", "booking": "https://egy.voxcinemas.com/booking/ID" }
          ]
        }
      ]
    }
  ]
}
```

- `label` derived from the day-tab text ("Thu 06 Aug" -> "Thu 06").
- Times come from `extract_available` (bookable only); `booking` is the link
  when present, empty string otherwise.
- Use GNU `date -d` for the timestamps (fall back to epoch seconds if you
  prefer) and a JSON escaping helper for names.

## THE STATIC SITE (site/)

"voxwatch" â€” dark atmosphere, lowercase prose, serif display + mono labels.
Must look hand-made, not templated: no purple gradients, no centered
everything, no emoji icons, no invented metrics. Copy is honest about what the
project is (a bash script, one config file, one always-on machine).

- **index.html**: nav pill with live/snapshot/offline status dot; hero with
  headline + CTA + a small instrument-panel apparatus (dial whose needle angle
  encodes the number of films watched, e.g. 24.3deg per film, capped 243deg);
  "01 watchlist" ledger section; "02 how it works" three steps; "03 channels"
  spec sheet; "04 run your own" install block (clone/config/schedule with a
  `Mohamedrwash` placeholder); footer statement. A `<dialog>` for subscribing:
  title, cinema, all time chips, a QR code (generated client-side from
  `https://ntfy.sh/<topic>`) on a light field, topic text + copy button, and a
  "subscribe in ntfy" link.
- **data mode**: `<script type="application/json" id="snapshot-data">` holds a
  baked copy of the JSON (fallback when the fetch fails or the watcher is
  offline). main.js fetches `data/showtimes.json` with a ~4s AbortController
  timeout; on success shows "live Â· N films Â· synced <time>", on timeout
  falls back to the snapshot and shows "snapshot".
- **ledger**: one row per film (title, cinema, next showtime, watching-status
  dot, "notify me" button). Row click opens the dialog. Rows enter with a
  staggered rise (40ms per row, capped at 320ms; disabled under
  prefers-reduced-motion).
- **css**: token-based (oklch palette on a near-black cool-violet paper,
  brass accent, focus ring, qr field/module colors); fluid type; no
  `transition: all`; all animation on transform/opacity only; hover effects
  gated behind `@media (hover: hover) and (pointer: fine)`; `overflow-x: clip`
  on html AND body; press feedback `scale(0.97)`; a `prefers-reduced-motion`
  block that keeps opacity/color feedback and drops movement.
- **js**: vanilla, no dependencies except the vendored qrcode lib.
  copy button flips to "copied" (inline state, no toast). Focus ring is
  instant (no transition). All clickable text stays on one line at 320px.
- **accessibility**: decorative SVG aria-hidden; dialog labelled by its title;
  rows are keyboard-operable (role=button, tabindex, Enter/Space opens).

## NOTIFICATION MESSAGE FORMATS

- Monitor started: `ðŸŽ¬ Monitoring <MOVIE> at <CINEMA> (day-by-day):\n<summary>`
- Schedule changed: `ðŸŽ¬ NEW SHOWTIME SCHEDULE - <MOVIE> at <CINEMA>\n\n<summary>`
- Site unreachable: `âš ï¸ Cannot reach <URL>\nSite may be down...`
- Heartbeat miss: `âš ï¸ <MOVIE> showtime monitor missed runs!\nLast successful: <time>`
- Digest: `ðŸ“… DAILY DIGEST - <MOVIE> at <CINEMA>\n\n<per-day lines>`

Public topic messages carry a `Click:` header with the first booking link.

## INSTALLERS

- `scripts/install-cron.sh`: idempotent. Removes any previous vox-monitor cron
  lines, then adds:
  - `*/5 * * * * <abs path>/vox-monitor.sh`
  - `0 9 * * * <abs path>/vox-monitor.sh digest`
  Prints the resulting crontab for verification.
- `scripts/install-windows.ps1`: creates two Task Scheduler tasks via schtasks:
  - `VoxShowtimesMonitor` every 5 minutes
  - `VoxShowtimesDigest` daily at 09:00
  Both invoke `wscript.exe <abs path>\run_*_hidden.vbs` so no console window
  flashes. The two .vbs files run the wsl.exe command with window hidden (0).
- Verify commands:
  - Linux: `crontab -l | grep vox-monitor`
  - Windows: `schtasks /query /tn VoxShowtimesMonitor /v /fo LIST`

## README.md must include

- Feature list (multi-film watchlist, public per-film topics, live site data)
- A table of all 6 notification channels with cost + sign-up needed
- Quick start: clone, `cp monitor.conf.example monitor.conf` +
  `cp movies.conf.example movies.conf`, add films, test with
  `bash src/vox-monitor.sh`, then install cron / Task Scheduler
- "Adding a film" section: one line in movies.conf, `rm .known_showtimes_<slug>`,
  no scheduler changes needed
- Requirements: bash, curl, sed, grep, awk, date; cron (Linux) or WSL (Windows);
  optional `mail`
- Disclaimer: reads only public page data; keep interval reasonable; respect ToS
- MIT License badge + reference

## DOCS (docs/)

- INSTALL.md: prerequisites, config (movies.conf format), manual test,
  scheduling (cron + Windows), verification steps.
- NOTIFICATIONS.md: the public per-film ntfy topics vs the private mirror;
  sign-up flow for all 6 channels; how to test a notification.
- CHANGE_MOVIE.md: add/remove films in movies.conf; slug guidance; reset
  `.known_showtimes_<slug>`.
- FAQ.md: no-notifications troubleshooting (right topic, app permissions),
  "console window flashing" fix (VBS wrappers), stale site data, "no showtimes
  found" (site HTML changed, view selectors).

## TESTING REQUIREMENTS

Before finishing, confirm (against the live site where reachable, otherwise
against a mock Vox HTML fixture served locally â€” the script must take the URL
from movies.conf so a fixture works):

1. `bash src/vox-monitor.sh` with no state files -> initializes per film,
   logs, publishes to the public topic + owner channels once.
2. Run again -> logs "No change" per film, no duplicate notifications.
3. `bash src/vox-monitor.sh digest` -> sends the daily digest per film.
4. Temporarily corrupt `.known_showtimes_<slug>` -> run -> a change alert is
   sent.
5. Verify that available times (from `<a class="action showtime">`) are
   reported and the "unavailable" `<span>` times are never included.
6. Verify `site/data/showtimes.json` is rewritten after each run and parses
   as the JSON contract above.
7. Verify the site renders from the written JSON (static file server) and
   falls back to the baked snapshot when the JSON is blocked.

## NOTES

- Use `set -uo pipefail` in the bash script but guard any `$1` reads with
  `${1:-}` to avoid "unbound variable" errors when run with no arguments.
- The `-h`/`--help` flag should print usage and exit 0.
- Script must be robust to minor site HTML changes; single-file bash script is
  preferred over a build step.
- No invented metrics or fake testimonials anywhere on the site; every number
  on the page must trace to the actual system (scan cadence, channel count,
  film count, cost).

â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

END OF PROMPT â€” paste everything above into the AI.
