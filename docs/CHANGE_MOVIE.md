# Managing the watchlist (films & cinemas)

## Two ways films get watched

1. **Visitor picks (cloud mode)** - anyone opens the voxwatch site, picks a film and a
   day, and clicks *track*. The site writes `{film, day, client_id}` to the Supabase
   `tracks` table; the cloud watcher (GitHub Actions, every 30 min) reads all rows and
   starts watching that film at the chosen cinema. *Untrack* deletes the visitor's own
   row (matched by the browser-generated `client_id`).
2. **`movies.conf` (PC mode)** - permanent, one film per line (see below).

## Adding a film in cloud mode (codeless)

Open the Supabase dashboard - Table Editor - `tracks` - **Insert row**:

| Column | Meaning | Example |
|--------|---------|---------|
| `slug` | URL-safe id; becomes the public topic `voxwatch-<slug>` | `the-odyssey` |
| `title` | Display name | `The Odyssey` |
| `url` | Vox movie page URL | `https://egy.voxcinemas.com/movies/the-odyssey` |
| `cinema` | Cinema heading (must match the page exactly); empty - `DEFAULT_CINEMA` | `City Centre Almaza` |
| `topic` | Optional ntfy topic override; empty - `voxwatch-<slug>` | *(empty)* |
| `day` | `YYYYMMDD` or empty (= any day) | `20260812` |
| `client_id` | Leave empty for owner rows (only used to match site untracks) | *(empty)* |

Visitors already do this from the site itself - the dashboard row is just the same
thing done manually. The cloud watcher also sends the visitor alerts straight to
`voxwatch-<slug>`, so they get pinged the moment their chosen day has showtimes.

## Adding / removing a film in PC mode

1. Open `movies.conf` - one film per line:

   ```bash
   # slug|Display Name|Cinema Name|Full Vox movie URL
   the-odyssey|The Odyssey|City Centre Almaza|https://egy.voxcinemas.com/movies/the-odyssey
   ```

2. **Add a film** - append a line. **Remove a film** - delete its line.

3. Reset that film's state so the first run treats it as new:

   ```bash
   rm -f .known_showtimes_<slug>
   ```

4. Test once:

   ```bash
   bash src/vox-monitor.sh
   ```

5. The scheduler (cron / Task Scheduler) needs **no changes** - it just runs
   the same script over the whole watchlist.

## Choosing the slug

The slug becomes the film's **public push topic** (`voxwatch-<slug>`) that site
visitors subscribe to, so pick something stable and URL-safe (lowercase, hyphens).
Changing a slug later means visitors must re-subscribe.

## Finding the right values

- **URL**: open the movie on voxcinemas.com and copy the URL (any country
  domain works - `egy.`, `ksa.`, `uae.`, ...).
- **Cinema name**: must match the cinema heading **exactly** as it appears on
  the page (e.g. `City Centre Almaza`, `Mall of Egypt`, `City Centre Alexandria`).

## Example - Dune: Part Three at Mall of Egypt

```bash
dune-part-three|Dune: Part Three|Mall of Egypt|https://egy.voxcinemas.com/movies/dune-part-three
```

That's it - one line (or one table row), and the film is watched from the next run.
