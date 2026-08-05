# FAQ & Troubleshooting

## General

**Q: The script says "Configuration not found".**
A: Create it: `cp monitor.conf.example monitor.conf` and
`cp movies.conf.example movies.conf`, then edit both.

**Q: No notifications arrive, but the log says "sent".**
A: The API accepted the message. Check the app on your phone:
- Installed and opened at least once
- Subscribed to the **right topic** (`voxwatch-<slug>` for the film, or your
  private `NTFY_TOPIC`) and not to a lookalike
- Notifications enabled for the app (and not Do-Not-Disturb)

**Q: I keep getting alerts about days that don't matter.**
A: Set `IGNORE_TODAY_TOMORROW=true` (default). It watches only days **after**
tomorrow.

**Q: The site shows a film that is no longer in my watchlist.**
A: `site/data/showtimes.json` only holds what the monitor wrote last run. Remove
the film's line from `movies.conf`, delete `.known_showtimes_<slug>`, and run
`bash src/vox-monitor.sh` once — the site updates on the next write.

**Q: The movie page structure changed and nothing is found.**
A: Run `bash src/vox-monitor.sh` and check `vox_showtimes.log`. If the day
tabs or cinema headings changed on the Vox site, the selectors in
`src/vox-monitor.sh` (`extract_available` and the `DAY_TABS` grep) may need a
small update. Inspect the HTML:
```bash
curl -s "https://egy.voxcinemas.com/movies/<slug>" | grep -o '<h3 class="highlight">[^<]*</h3>'
```

## Windows

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
A: Yes — the scripts are bash. Either run them inside WSL, or install Git Bash.

## Heartbeat

**Q: I got a "monitor missed runs" alert.**
A: A scheduled run didn't finish in time (laptop asleep / WSL hung / network
off). The monitor resumes on its own next run. If it persists, check that the
scheduled task is enabled and WSL starts (try `wsl -d Ubuntu echo ok`).

## Tuning

**Q: I want faster checks.**
A: Edit `CHECK_INTERVAL` in `monitor.conf` and the cron/task schedule
(5 min → 1 min). Mind the site's terms — don't over-fetch.

**Q: Can I opt out of the daily digest?**
A: Set `ENABLE_DIGEST=false` (and remove/uninstall the digest task or cron
line).