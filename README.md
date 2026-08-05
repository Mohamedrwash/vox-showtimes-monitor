# Vox Showtimes Monitor â€” the marquee, watched for you

Watches a **Vox Cinemas** movie page per film in `movies.conf` and pings your phone (and
everyone subscribed) the moment showtimes go live â€” no more refreshing the site every
5 minutes.

Every film gets its own **public push topic** (`voxwatch-<slug>` on ntfy.sh). Website
visitors pick a film, tap **notify me**, and get the same alerts as the owner. The monitor
also writes `site/data/showtimes.json` on every run, so the voxwatch site stays live.

Built for **"The Odyssey â€“ City Centre Almaza"**, works for **any movie at any cinema**.

![works](https://img.shields.io/badge/works-on%20Linux%20%7C%20macOS%20%7C%20Windows%20(WSL)-green)

---

## Features

- **Multi-film watchlist** â€” one line per film in `movies.conf` (`slug|name|cinema|url`)
- **Public per-film topics** â€” `voxwatch-<slug>` on ntfy.sh; visitors subscribe with zero
  accounts, you get a private mirror topic
- **Live website data** â€” `site/data/showtimes.json` rewritten every run (atomic)
- **Checks every 5 minutes** (cron on Linux, Task Scheduler on Windows)
- **Day-by-day tracking** â€” knows which future days have showtimes
- **Format aware** â€” includes IMAX / GOLD / Standard in alerts
- **Booking links** in every notification (tap-to-book)
- **State tracking** â€” no duplicate alerts for the same schedule
- **Failure handling** â€” distinguishes "site down" from "no showtimes"
- **Heartbeat** â€” alerts you if the monitor itself stops running
- **6 notification channels** â€” most are free
- **Optional "ignore today & tomorrow"** mode (for presale hunting)

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

---

## Quick start

### 1. Install

```bash
git clone https://github.com/Mohamedrwash/vox-showtimes-monitor.git
cd vox-showtimes-monitor

# configure
cp monitor.conf.example monitor.conf
cp movies.conf.example movies.conf
```

Open `movies.conf` â€” one film per line:

```bash
the-odyssey|The Odyssey|City Centre Almaza|https://egy.voxcinemas.com/movies/the-odyssey
```

Then pick your notification channel(s) in `monitor.conf` â€” flip the matching `USE_*` to
`true` and fill in credentials. See [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md).

### 2. Test it

```bash
bash src/vox-monitor.sh          # one monitoring pass over all films
bash src/vox-monitor.sh digest   # force the daily digest
```

### 3. Schedule it

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

Absolutely codeless â€” one line in `movies.conf`:

```bash
# slug|Display Name|Cinema Name|Full Vox movie URL
dune-part-three|Dune: Part Three|Mall of Egypt|https://egy.voxcinemas.com/movies/dune-part-three
```

1. Pick a **stable slug** â€” it becomes the public topic `voxwatch-dune-part-three`.
2. The cinema name must match the heading on the movie page exactly.
3. Delete that film's old state file to start fresh:
   ```bash
   rm .known_showtimes_dune-part-three
   ```
4. Done â€” the scheduler picks it up on the next run. The site's watchlist updates
   automatically.

---

## How it works

```
                â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
   cron/Task â”€â”€â–¶â”‚ vox-monitor.shâ”‚â”€â”€â–¶ for each film in movies.conf
   every 5 min  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜       â”‚
                           â”‚  fetch movie page â†’ parse day-tabs (d=YYYYMMDD)
                           â–¼
                    for each future day
                           â”‚  fetch day page â†’ extract available showtimes
                           â”‚  (format + booking link) for target cinema
                           â–¼
                 current_sig vs .known_showtimes_<slug>
                           â”‚
                    changed? â”€â”€noâ”€â”€â–¶ log only
                        â”‚yes
                        â–¼
                 notify public topic (voxwatch-<slug>) + owner
                 channels + update state + rewrite site JSON
```

- **State files**: `.known_showtimes_<slug>` (one per film). Changed schedule â†’ alert + update.
- **Site data**: `site/data/showtimes.json` â€” atomic write every run; the voxwatch site
  fetches it live, and falls back to a baked snapshot when the watcher is offline.
- **Log**: `vox_showtimes.log` (timestamped activity).
- **Heartbeat**: `.heartbeat` timestamp; if a run is missed > `HEARTBEAT_TIMEOUT`, you get an alert.
- **Digest**: `vox-monitor.sh digest` sends today + tomorrow per film once per day (`.last_digest_<slug>` gate).

## Requirements

- `bash`, `curl`, `sed`, `grep`, `awk` (present on every Linux/WSL distro)
- `date` (GNU coreutils)
- **Linux/macOS**: `cron`
- **Windows**: WSL with a distro (e.g. Ubuntu), Task Scheduler
- Optional: `mail` (mailutils) for the email channel

## Documentation

- [Install / setup](docs/INSTALL.md)
- [Notification setup (all 6 channels)](docs/NOTIFICATIONS.md)
- [Managing the watchlist](docs/CHANGE_MOVIE.md)
- [FAQ & troubleshooting](docs/FAQ.md)

## Disclaimer

This project reads *publicly visible* showtime data from Vox Cinemas. Use it for personal
convenience only â€” do not hammer the site (5-minute minimum interval is a sensible default),
and respect their terms of service.

## License

[MIT](LICENSE)
