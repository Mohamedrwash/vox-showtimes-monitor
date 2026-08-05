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
