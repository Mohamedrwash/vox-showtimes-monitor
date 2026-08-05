# Install & Setup

## Prerequisites

- **Linux / macOS**
  - `bash`, `curl`, `sed`, `grep`, `awk`, `date` â€” preinstalled on all mainstream distros
  - `cron` (most distros ship it; on Ubuntu it's `cron` package)

- **Windows**
  - WSL2 with any distro (we use Ubuntu):
    ```powershell
    wsl --install -d Ubuntu
    ```
  - Then run `bash` scripts inside WSL, e.g. `wsl -d Ubuntu bash /path/to/vox-monitor.sh`

## Step 1 â€” Get the project

```bash
git clone https://github.com/Mohamedrwash/vox-showtimes-monitor.git
cd vox-showtimes-monitor
```

or download the ZIP from the GitHub page and extract it.

## Step 2 â€” Configure

```bash
cp monitor.conf.example monitor.conf
cp movies.conf.example movies.conf
nano movies.conf
```

`movies.conf` is the watchlist â€” **one film per line**:

| Part | Meaning | Example |
|------|---------|---------|
| `slug` | URL-safe id; becomes the public topic `voxwatch-<slug>` | `the-odyssey` |
| Display name | Shown in alerts and on the site | `The Odyssey` |
| Cinema name | Cinema section to watch (must match the page heading exactly) | `City Centre Almaza` |
| URL | Vox movie page URL | `https://egy.voxcinemas.com/movies/the-odyssey` |

```bash
# slug|Display Name|Cinema Name|Full Vox movie URL
the-odyssey|The Odyssey|City Centre Almaza|https://egy.voxcinemas.com/movies/the-odyssey
```

`monitor.conf` holds global settings (site-data output, heartbeat, digest) and your
personal notification channels â€” flip at least one `USE_*` to `true` (see
[NOTIFICATIONS.md](NOTIFICATIONS.md)). `USE_NTFY=true` is what powers the public
per-film topics visitors subscribe to; keep it on.

Two optional-but-useful settings for visitor picks:

| Setting | Meaning | Example |
|---------|---------|---------|
| `CONTROL_TOPIC` | Public ntfy topic the site publishes `PICK <slug>` / `UNPICK <slug>` to; the monitor polls it every run | `voxwatch-control` |
| `DEFAULT_CINEMA` | Cinema used for visitor-picked films (picks have no cinema of their own) | `City Centre Almaza` |

The site's catalog (`site/data/catalog.json`, 10 "What's On" films scraped from the Vox
homepage) is refreshed manually when the lineup changes:

```bash
bash scripts/update-catalog.sh   # rewrites site/data/catalog.json
```

## Step 3 â€” Test manually

```bash
bash src/vox-monitor.sh
```

Expected output: a log line in `vox_showtimes.log` and (first run only) a "monitoring started" notification. Run it again â€” it should say "No change".

## Step 4 â€” Schedule

### Linux / macOS (cron)

```bash
bash scripts/install-cron.sh
crontab -l | grep vox-monitor
```

This creates:

```
*/5 * * * *  /path/to/vox-showtimes-monitor/src/vox-monitor.sh
0 9 * * *    /path/to/vox-showtimes-monitor/src/vox-monitor.sh digest
```

Manually instead:

```bash
crontab -e
# add:
*/5 * * * * /path/to/vox-monitor.sh
0 9 * * *   /path/to/vox-monitor.sh digest
```

### Windows (Task Scheduler)

Run in PowerShell from the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-windows.ps1
```

This creates two tasks running `wsl.exe` invisibly via VBS wrappers:

- `VoxShowtimesMonitor` â€” every 5 minutes
- `VoxShowtimesDigest` â€” daily at 09:00

Useful commands:

```powershell
schtasks /run  /tn VoxShowtimesMonitor      # run now
schtasks /query /tn VoxShowtimesMonitor /v /fo LIST
schtasks /change /tn VoxShowtimesMonitor /disable   # pause
schtasks /change /tn VoxShowtimesMonitor /enable    # resume
schtasks /delete /tn VoxShowtimesMonitor /f         # remove
```

> The VBS wrappers point at `C:\Users\Medo\...` hard-coded paths. If you put the
> project elsewhere, regenerate the wrappers by editing the two lines in
> `scripts/run_monitor_hidden.vbs` and `scripts/run_digest_hidden.vbs`.

## Step 5 â€” Verify

```bash
# Linux
bash src/vox-monitor.sh digest

# Windows
schtasks /run /tn VoxShowtimesMonitor
tail -5 vox_showtimes.log   # after ~10 s
```

You should see a fresh timestamped check in the log, and (if changed) a phone notification.