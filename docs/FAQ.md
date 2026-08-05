# FAQ & Troubleshooting

> **Cloud mode** questions are about the GitHub Actions watcher + Supabase.
> **PC mode** is the original self-hosted setup. Questions that apply to only
> one mode say so.

## General

**Q: The script says "Configuration not found".**
A: (PC mode) Create it: `cp monitor.conf.example monitor.conf` and
`cp movies.conf.example movies.conf`, then edit both.

**Q: No notifications arrive, but the log says "sent".**
A: The API accepted the message. Check the app on your phone:
- Installed and opened at least once
- Subscribed to the **right topic** (`voxwatch-<slug>` for the film, or your
  private `NTFY_TOPIC` / `NTFY_MIRROR`) and not to a lookalike
- Notifications enabled for the app (and not Do-Not-Disturb)

**Q: I keep getting alerts about days that don't matter.**
A: (PC mode) Set `IGNORE_TODAY_TOMORROW=true` (default). It watches only days
**after** tomorrow. In cloud mode, each visitor chooses their own day, so
alerts only fire for chosen days.

**Q: The site shows a film that is no longer in my watchlist.**
A: `site/data/showtimes.json` only holds what the watcher wrote last run -
it's rewritten (and committed) on every cloud run. In PC mode, remove the
film's line from `movies.conf`, delete `.known_showtimes_<slug>`, and run
`bash src/vox-monitor.sh` once. Note the site's *browse* list
(`site/data/catalog.json`, the 10 "What's On" films) is separate - that one
is refreshed manually with `bash scripts/update-catalog.sh`.

**Q: I clicked *track* on the site but the film never gets watched.**
A: The site writes to the Supabase `tracks` table and the cloud watcher picks
it up on its next run (within 30 minutes). If it still doesn't show, check:
- the row exists: Supabase dashboard - Table Editor - `tracks` (you can even
  watch it appear as you click)
- the latest Actions run: Actions - **voxwatch watcher** - open the latest run
- the log output: "no day tabs found" means the film's URL/slug doesn't parse
  (Vox changed or the slug is wrong); "unreachable" means the URL is bad
- `site/js/config.js` is filled in (empty anon key = the write fails silently)

**Q: I clicked *untrack* but the film stays on the site.**
A: Untrack deletes **your** row (matched by `client_id` in your browser's
localStorage). Other visitors' tracks are independent. If it still shows in
your list, hard-refresh the page - the site caches your tracks in
localStorage. In PC mode, films in `movies.conf` can't be unpicked from the
site (the owner's list wins).

**Q: The Actions workflow fails.**
A: Open the run log. Common causes:
- secrets missing: check `SUPABASE_URL` / `SUPABASE_ANON_KEY` exist in
  Repo - Settings - Secrets (and match config.js)
- "supabase tracks fetch failed": the URL or key is wrong, or the `tracks`
  table wasn't created (run `docs/supabase-schema.sql`)
- the bot can't push: the workflow needs `contents: write` (it's already set
  in `.github/workflows/watcher.yml`); don't make the repo read-only for Actions

**Q: The movie page structure changed and nothing is found.**
A: Run the watcher manually (Actions - Run workflow) and check the log. If the
day tabs or cinema headings changed on the Vox site, the selectors in
`scripts/serverless-watch.sh` (`extract_available` and the `DAY_TABS` grep)
may need a small update. Inspect the HTML:
```bash
curl -s "https://egy.voxcinemas.com/movies/<slug>" | grep -o '<h3 class="highlight">[^<]*</h3>'
```

## Cloud mode

**Q: How do I test the cloud watcher without waiting for the cron?**
A: Actions - **voxwatch watcher** - Run workflow. Every run also commits the
site data, so you can verify via the repo's `site/data/showtimes.json`.

**Q: Can I run the cloud watcher on my PC for testing?**
A: Yes - it needs `bash` + `jq` and reads the same env vars:
```bash
SUPABASE_URL="https://<ref>.supabase.co" SUPABASE_KEY="<anon-key>" \
NTFY_MIRROR="vox-odyssey-monitor-abc123" bash scripts/serverless-watch.sh
```
Or fully offline with a mock tracks file (see the top of the script;
`MOCK_TRACKS` bypasses Supabase entirely).

**Q: Is it OK that the Supabase anon key is public?**
A: Yes - by design. The key ships in the site's HTML anyway; the RLS policies
on `tracks` only allow exactly the operations the site needs
(read/insert/update/delete), and the table holds no secrets - just film picks.

## Windows (PC mode)

**Q: A console window flashes every 5 minutes.**
A: The installer uses hidden VBS wrappers, so this shouldn't happen. If you
created tasks by hand with `wsl.exe` directly, switch to the VBS wrapper:
```powershell
schtasks /create /tn VoxShowtimesMonitor /tr "wscript.exe <abs path>\run_monitor_hidden.vbs" /sc MINUTE /mo 5 /f
```

**Q: Tasks run but nothing is logged.**
A: The VBS wrappers hard-code the project path
(`C:\Users\Medo\vox-showtimes-monitor`). If you moved the project, update
`scripts/run_monitor_hidden.vbs` / `run_digest_hidden.vbs` to the new path.

**Q: Do I need WSL?**
A: Yes - the scripts are bash. Either run them inside WSL, or install Git Bash.

## Heartbeat (PC mode)

**Q: I got a "monitor missed runs" alert.**
A: A scheduled run didn't finish in time (laptop asleep / WSL hung / network
off). The monitor resumes on its own next run. If it persists, check that the
scheduled task is enabled and WSL starts (try `wsl -d Ubuntu echo ok`).

## Tuning

**Q: I want faster checks.**
A: (PC mode) Edit `CHECK_INTERVAL` in `monitor.conf` and the cron/task
schedule (5 min - 1 min). Mind the site's terms - don't over-fetch. The cloud
watcher is fixed at 30 minutes (GitHub Actions' free-tier-friendly cadence).

**Q: Can I opt out of the daily digest?**
A: (PC mode) Set `ENABLE_DIGEST=false` (and remove/uninstall the digest task
or cron line). The cloud watcher has no digest.
