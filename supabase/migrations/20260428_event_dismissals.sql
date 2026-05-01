-- Persistent dismiss for dashboard events. A player can swipe-hide an event
-- (e.g. "for me not relevant") and it stays hidden across devices and reloads.
-- Cascades when the underlying event is deleted. Re-show: delete the row
-- via /kalender (event re-appears in the dashboard list).

create table if not exists public.event_dismissals (
  event_id     uuid not null references public.events(id) on delete cascade,
  player_id    uuid not null references public.players(id) on delete cascade,
  dismissed_at timestamptz not null default now(),
  primary key (event_id, player_id)
);

alter table public.event_dismissals enable row level security;

drop policy if exists "own_select" on public.event_dismissals;
create policy "own_select" on public.event_dismissals
  for select using (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );

drop policy if exists "own_insert" on public.event_dismissals;
create policy "own_insert" on public.event_dismissals
  for insert with check (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );

drop policy if exists "own_delete" on public.event_dismissals;
create policy "own_delete" on public.event_dismissals
  for delete using (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );
