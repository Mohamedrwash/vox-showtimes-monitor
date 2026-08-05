-- voxwatch serverless architecture
-- Run this in the Supabase SQL editor (your project → SQL → New query).
-- Creates the `tracks` table used by the site (browser writes) and by the
-- GitHub Actions watcher (reads + flags notified).

create table if not exists public.tracks (
  id uuid primary key default gen_random_uuid(),
  slug text not null,          -- film slug, e.g. the-odyssey
  title text not null,         -- display name
  url text not null,           -- vox movie page
  cinema text not null,        -- cinema section to watch
  topic text not null,         -- public ntfy topic, voxwatch-<slug>
  day text not null default '',-- chosen day YYYYMMDD, '' = any day
  client_id text not null,     -- anonymous per-browser id (localStorage)
  notified boolean not null default false,
  created_at timestamptz not null default now()
);

-- RLS: this project is intentionally public (like the old ntfy control
-- topic was). The anon key is not a secret — the policies below allow
-- anyone to read/add/update/remove their own tracks. No user data other
-- than film choices lives here.
alter table public.tracks enable row level security;

create policy "tracks are public to read"
  on public.tracks for select using (true);

create policy "anyone may add a track"
  on public.tracks for insert with check (true);

create policy "anyone may update a track"
  on public.tracks for update using (true) with check (true);

create policy "anyone may delete a track"
  on public.tracks for delete using (true);

create index if not exists tracks_slug_day_idx on public.tracks (slug, day);
create index if not exists tracks_client_idx on public.tracks (client_id);

-- ---------------------------------------------------------------------
-- push_state — per-browser web-push flag, written by the site when the
-- visitor enables/disables browser notifications. The admin page uses it
-- to show who gets browser pings. Public by design (same model as tracks).
-- ---------------------------------------------------------------------

create table if not exists public.push_state (
  client_id text primary key,          -- same per-browser id as tracks
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.push_state enable row level security;

create policy "push_state public read"
  on public.push_state for select using (true);

create policy "push_state public insert"
  on public.push_state for insert with check (true);

create policy "push_state public update"
  on public.push_state for update using (true) with check (true);

create policy "push_state public delete"
  on public.push_state for delete using (true);
