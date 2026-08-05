# Install & Setup

voxwatch runs two ways:

- **Cloud mode (recommended)** - site on GitHub Pages, visitor picks in a Supabase
  table, watcher on GitHub Actions every 30 minutes. Your PC is never involved.
- **PC mode (optional)** - the original self-hosted watcher on your own machine.

---

## Cloud mode (recommended)

### 1. Create a Supabase project

Sign up free at https://supabase.com, create a project, then open the **SQL editor**
and run the whole of [`docs/supabase-schema.sql`](supabase-schema.sql). It creates the
`tracks` table and its RLS policies.

The table is **public-by-design**: site visitors track films without accounts. The
RLS policies allow anyone read/insert/update/delete - the equivalent of the old
public ntfy control topic, but easier to manage.

### 2. Fill in the site config

Copy your **Project URL** and **anon public** key (Supabase dashboard - Settings - API)
into `site/js/config.js`:

```js
window.VOXWATCH_SUPABASE = {
  url: "https://<project-ref>.supabase.co",
  anonKey: "<anon-public-key>"
};
```

The anon key is *meant* to be public - it ships in the site's HTML anyway. The RLS
policies protect the data, not the key.

### 3. Push the repo to GitHub

```bash
git remote add origin https://github.com/<you>/vox-showtimes-monitor.git
git push -u origin master
```

### 4. Add repository secrets

Repo - Settings - Secrets and variables - Actions - New repository secret:

| Secret | Value |
|--------|-------|
| `SUPABASE_URL` | the same project URL as in config.js |
| `SUPABASE_ANON_KEY` | the same anon key as in config.js |
| `NTFY_MIRROR` *(optional)* | a private mirror topic name, e.g. `vox-odyssey-monitor-abc123` |

The workflow (`.github/workflows/watcher.yml`) passes these to
`scripts/serverless-watch.sh` on every run.

### 5. Enable GitHub Pages

Repo - Settings - Pages - **Deploy from a branch** - branch `master`, folder `/site`.
Your site is then at `https://<you>.github.io/vox-showtimes-monitor/`.

### 6. Run the watcher once

Actions - **voxwatch watcher** - **Run workflow**, then watch the log. The bot commits
fresh `site/data/showtimes.json`; open the site to confirm.

That's it - the workflow then runs itself every 30 minutes.

---

## PC mode (optional)

### Step 1 - Get the project

```bash
git clone https://github.com/Mohamedrwash/vox-showtimes-monitor.git
cd vox-showtimes-monitor
```

or download the ZIP from the GitHub page and extract it.

### Step 2 - Configure

```bash
cp monitor.conf.example monitor.conf
cp movies.conf.example movies.conf
nano movies.conf
```

`movies.conf` is the watchlist - **one film per line**:

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
personal notification channels - flip at least one `USE_*` to `true` (see
[NOTIFICATIONS.md](NOTIFICATIONS.md)). `USE_NTFY=true` is what powers the public
per-film topics visitors subscribe to; keep it on.

`DEFAULT_CINEMA` is the cinema used for films that have no cinema of their own.

The site's catalog (`site/data/catalog.json`, 10 "What's On" films scraped from the Vox
homepage) is refreshed manually when the lineup changes:

```bash
bash scripts/update-catalog.sh   # rewrites site/data/catalog.json
```

### Step 3 - Test manually

```bash
bash src/vox-monitor.sh
```

Expected output: a log line in `vox_showtimes.log` and (first run only) a "monitoring
started" notification. Run it again - it should say "No change".

### Step 4 - Schedule

#### Linux / macOS (cron)

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

#### Windows (Task Scheduler)

Run in PowerShell from the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-windows.ps1
```

This creates two tasks running `wsl.exe` invisibly via VBS wrappers:

- `VoxShowtimesMonitor` - every 5 minutes
- `VoxShowtimesDigest` - daily at 09:00

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

### Step 5 - Verify

```bash
# Linux
bash src/vox-monitor.sh digest

# Windows
schtasks /run /tn VoxShowtimesMonitor
tail -5 vox_showtimes.log   # after ~10 s
```

You should see a fresh timestamped check in the log, and (if changed) a phone notification.
