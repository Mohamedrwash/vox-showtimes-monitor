# Vox Showtimes Monitor - the marquee, watched for you

Watches **Vox Cinemas** movie pages and pings your phone (and everyone subscribed) the
moment the showtimes you care about go live - no more refreshing the site every
5 minutes.

Every film gets its own **public push topic** (`voxwatch-<slug>` on ntfy.sh). Website
visitors pick a film, choose **the day they want to see it**, and get pinged only when
that day's showtimes appear.

Two ways to run the watcher:

1. **Cloud mode (recommended, zero PC)** - the site lives on GitHub Pages, visitor
   picks live in a Supabase table, and a GitHub Actions cron scans every 30 minutes.
   Works whether or not your computer is on. See **Deploy to the cloud** below.
2. **PC mode** - the original: `vox-monitor.sh` runs on your machine (cron /
   Windows Task Scheduler) and writes live data for a locally-served site.

Built for **"The Odyssey - City Centre Almaza"**, works for **any movie at any cinema**.

![works](https://img.shields.io/badge/works-on%20Linux%20%7C%20macOS%20%7C%20Windows%20(WSL)-green)

---

## Features

- **Multi-film watchlist** - one line per film in `movies.conf` (PC mode), or visitor picks from the site (cloud mode)
- **Full-catalog site** - the voxwatch site shows the current Vox lineup (`site/data/catalog.json`) and lets visitors **pick their film + day** right there
- **Day picker** - pick any day of the next week (or *any*); you're pinged only when that day has showtimes
- **Cloud watcher (GitHub Actions)** - scans every 30 min on GitHub's servers; your PC is never needed
- **Visitor picks (Supabase)** - the site writes `{film, day}` to a Supabase `tracks` table (public anon key, RLS-secured by design); the cloud watcher reads it
- **Public per-film topics** - `voxwatch-<slug>` on ntfy.sh; visitors subscribe with zero accounts, you get a private mirror topic
- **Live website data** - `site/data/showtimes.json` rewritten on every cloud run and committed to the repo (atomic)
- **Checks every 30 minutes in cloud mode** (every 5 minutes in PC mode)
- **Day-by-day tracking** - knows which future days have showtimes
- **Format aware** - includes IMAX / GOLD / Standard in alerts
- **Booking links** in every notification (tap-to-book)
- **State tracking** - no duplicate alerts for the same schedule (per film + day)
- **Failure handling** - distinguishes "site down" from "no showtimes"
- **Heartbeat** (PC mode) - alerts you if the PC monitor itself stops running
- **6 notification channels** - most are free

## Notification channels (all optional, mix & match)

| Channel | Cost | Sign-up | Notes |
|---------|------|---------|-------|
| [ntfy.sh](https://ntfy.sh) | **Free** | **None needed** | **The visitor channel**: every film gets `voxwatch-<slug>`, plus your private mirror topic |
| [Gotify](https://gotify.net) | **Free** | No account* | Self-hosted via Docker |
| [Pushover](https://pushover.net) | Free tier (7,500/mo) | One-time $5 iOS or free Android app license | Fastest, most reliable |
| [Telegram](https://t.me/BotFather) | **Free** | Yes (bot) | No limits |
| [Discord](https://support.discord.com/hc/en-us/articles/228383668) | **Free** | Yes | Webhook |
| Email / SMS-gateway | **Free** | No | Needs `mail` binary |

\* Gotify is free software; you run your own server so there's no subscription.

> The cloud watcher (GitHub Actions) uses **ntfy only** - it powers the public
> per-film topics visitors subscribe to. The other channels are available in
> PC mode. See [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md).

---

## Quick start

### Cloud mode (recommended - no PC required)

1. **Create a Supabase project** (free at [supabase.com](https://supabase.com)) - SQL editor -
   paste and run [`docs/supabase-schema.sql`](docs/supabase-schema.sql) (creates the `tracks`
   table + RLS policies).
2. **Fill in the site config** - project URL + anon key (project settings - API) into
   `site/js/config.js` (the anon key is public by design - RLS protects the data, not the key).
3. **Push this repo to GitHub**, then:
   - add repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`
   - (optional) `NTFY_MIRROR` secret = your private mirror topic name
   - enable **GitHub Pages** - Deploy from a branch - `master` - folder `/site`
4. Done. The `voxwatch watcher` workflow runs every 30 minutes (plus manual runs via
   *Actions - watcher - Run workflow*), commits fresh `site/data/showtimes.json`, and pings
   ntfy topics when chosen days have showtimes.

### PC mode (optional)

```bash
git clone https://github.com/Mohamedrwash/vox-showtimes-monitor.git
cd vox-showtimes-monitor

# configure
cp monitor.conf.example monitor.conf
cp movies.conf.example movies.conf
```

Open `movies.conf` - one film per line:

```bash
the-odyssey|The Odyssey|City Centre Almaza|https://egy.voxcinemas.com/movies/the-odyssey
```

Then pick your notification channel(s) in `monitor.conf` - flip the matching `USE_*` to
`true` and fill in credentials. See [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md).

#### Test it

```bash
bash src/vox-monitor.sh          # one monitoring pass over all films
bash src/vox-monitor.sh digest   # force the daily digest
```

#### Schedule it

**Linux / macOS:**
```bash
bash scripts/install-cron.sh     # cron: every 5 min + daily digest at 09:00
crontab -l                       # verify
```

**Windows (WSL required):**
```bash
# inside PowerShell, from the project folder
powershell -ExecutionPolicy Bypass -File scripts/install-windows.ps1
schtasks /query /tn VoxShowtimesMonitor /v /fo LIST   # verify
```

> Windows note: the tasks run `wsl.exe` **invisibly** (via a VBS wrapper), so no terminal window flashes every 5 minutes.

---

## Adding a film

**Visitors** open the voxwatch site, pick a film and a day, and hit *track* - the row
lands in the Supabase `tracks` table, and the next cloud watcher run (within 30 min)
starts checking that film.

**You** (cloud mode, codeless) - insert a row in the Supabase dashboard
(Table Editor - `tracks` - Insert row): `slug`, `title`, `url`, `cinema` (or empty for
`DEFAULT_CINEMA`), `day` (`YYYYMMDD` or empty = any). Details in
[docs/CHANGE_MOVIE.md](docs/CHANGE_MOVIE.md).

**You** (PC mode) - one line in `movies.conf`:

```bash
# slug|Display Name|Cinema Name|Full Vox movie URL
dune-part-three|Dune: Part Three|Mall of Egypt|https://egy.voxcinemas.com/movies/dune-part-three
```

1. Pick a **stable slug** - it becomes the public topic `voxwatch-dune-part-three`.
2. The cinema name must match the heading on the movie page exactly.
3. Done - the next run picks it up. The site's watchlist updates automatically.

---

## How it works (cloud mode)

```
 visitor opens the site (GitHub Pages)          visitor's phone (ntfy app)
        |  picks film + day                             ^
        v                                               |
  Supabase `tracks` table <----------------->  ntfy topics: voxwatch-<slug>
        |                                       (+ your private NTFY_MIRROR)
        v  read every 30 min
  GitHub Actions: serverless-watch.sh
        |  fetch Vox movie page -> parse day tabs
        |  fetch chosen day page -> extract showtimes (format + booking link)
        v
  chosen day has showtimes?
     no   -> keep waiting; the dedupe key is cleared so you're pinged the
             moment that day appears
     yes  -> first time today? -> notify film topic + mirror
        |
        v
  rewrite site/data/showtimes.json -> commit -> site always shows live data
```

- **Visitor picks**: the site writes `{film, day, client_id}` to the Supabase `tracks`
  table (public anon key by design; RLS allows anyone read/insert/update/delete).
  The cloud watcher reads all rows on every run.
- **Day matching**: a track's `day` is `YYYYMMDD`; an empty `day` means "any" - alert
  on the first day that has showtimes.
- **Dedupe**: `site/data/notified.json` remembers `slug|day` per calendar day, so a
  subscriber gets one alert per day the chosen day has showtimes - no spam.
- **Site data**: `site/data/showtimes.json` is rewritten and committed on every run;
  the site fetches it live, and falls back to a baked-in snapshot when the data is stale.
- **PC mode** (optional): `src/vox-monitor.sh` instead - every 5 minutes, with state
  files `.known_showtimes_<slug>`, a heartbeat alert and a daily digest.

## Requirements

- `bash`, `curl`, `sed`, `grep`, `awk`, `jq` (cloud watcher; preinstalled on GitHub runners)
- **Cloud mode**: a free Supabase project + a GitHub repo with Actions and Pages
- **PC mode**: **Linux/macOS** - `cron`; **Windows** - WSL with a distro (e.g. Ubuntu), Task Scheduler
- Optional: `mail` (mailutils) for the email channel

## Documentation

- [Install / setup (cloud + PC)](docs/INSTALL.md)
- [Notification setup (all 6 channels)](docs/NOTIFICATIONS.md)
- [Managing the watchlist](docs/CHANGE_MOVIE.md)
- [FAQ & troubleshooting](docs/FAQ.md)

## Disclaimer

This project reads *publicly visible* showtime data from Vox Cinemas. Use it for personal
convenience only - do not hammer the site (30-minute cloud interval / 5-minute PC interval
is a sensible default), and respect their terms of service.

## License

[MIT](LICENSE)
