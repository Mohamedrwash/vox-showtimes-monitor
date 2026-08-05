# Managing the watchlist (films & cinemas)

The watchlist is **fully config-driven** — switching films requires no code
edits and no reinstall.

## Steps

1. Open `movies.conf` — one film per line:

   ```bash
   # slug|Display Name|Cinema Name|Full Vox movie URL
   the-odyssey|The Odyssey|City Centre Almaza|https://egy.voxcinemas.com/movies/the-odyssey
   ```

2. **Add a film** — append a line. **Remove a film** — delete its line.

3. Reset that film's state so the first run treats it as new:

   ```bash
   rm -f .known_showtimes_<slug>
   ```

4. Test once:

   ```bash
   bash src/vox-monitor.sh
   ```

5. The scheduler (cron / Task Scheduler) needs **no changes** — it just runs
   the same script over the whole watchlist.

## Choosing the slug

The slug becomes the film's **public push topic** (`voxwatch-<slug>`) that site
visitors subscribe to, so pick something stable and URL-safe (lowercase,
hyphens). Changing a slug later means visitors must re-subscribe.

## Finding the right values

- **URL**: open the movie on voxcinemas.com and copy the URL (any country
  domain works — `egy.`, `ksa.`, `uae.`, …).
- **Cinema name**: must match the cinema heading **exactly** as it appears on
  the page (e.g. `City Centre Almaza`, `Mall of Egypt`, `City Centre Alexandria`).

## Example — Dune: Part Three at Mall of Egypt

```bash
dune-part-three|Dune: Part Three|Mall of Egypt|https://egy.voxcinemas.com/movies/dune-part-three
```

That's it — one line, and the film appears on the site's watchlist after the
next run.
