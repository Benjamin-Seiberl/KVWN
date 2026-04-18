-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Turnier-System – eigenständige Tabellen (ersetzt matches-  ║
-- ║  basiertes Design aus 20260415 / 20260417)                  ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ── 1. Kern-Tabelle ──────────────────────────────────────────────
create table if not exists public.tournaments (
  id               uuid        primary key default gen_random_uuid(),
  title            text        not null,
  location         text,
  status           text        not null default 'voting'
                               check (status in ('voting','voting_closed','scheduling','confirmed')),
  voting_deadline  timestamptz,
  confirmed_date   date,
  confirmed_time   time,
  created_at       timestamptz default now()
);

alter table public.tournaments enable row level security;

create policy "tournaments read" on public.tournaments
  for select using (true);

create policy "tournaments write (kapitaen)" on public.tournaments
  for all
  using (
    exists (select 1 from public.players where email = (auth.jwt() ->> 'email') and role in ('kapitaen','admin'))
  )
  with check (true);

-- ── 2. Mögliche Turniertage (Abstimmungs-Optionen) ──────────────
create table if not exists public.tournament_date_options (
  id            uuid        primary key default gen_random_uuid(),
  tournament_id uuid        not null references public.tournaments(id) on delete cascade,
  date          date        not null,
  created_at    timestamptz default now()
);

alter table public.tournament_date_options enable row level security;
create policy "tdo read"  on public.tournament_date_options for select using (true);
create policy "tdo write" on public.tournament_date_options
  for all using (
    exists (select 1 from public.players where email = (auth.jwt() ->> 'email') and role in ('kapitaen','admin'))
  ) with check (true);

-- ── 3. Teilnahme-Abstimmung ──────────────────────────────────────
create table if not exists public.tournament_votes (
  tournament_id uuid    not null references public.tournaments(id) on delete cascade,
  player_id     uuid    not null references public.players(id),
  wants_to_play boolean not null default true,
  created_at    timestamptz default now(),
  primary key (tournament_id, player_id)
);

alter table public.tournament_votes enable row level security;
create policy "tv read" on public.tournament_votes for select using (true);
create policy "tv own"  on public.tournament_votes
  for all
  using  (player_id in (select id from public.players where email = (auth.jwt() ->> 'email')))
  with check (player_id in (select id from public.players where email = (auth.jwt() ->> 'email')));

-- ── 4. Terminwahl ────────────────────────────────────────────────
create table if not exists public.tournament_date_votes (
  tournament_id  uuid not null references public.tournaments(id)          on delete cascade,
  player_id      uuid not null references public.players(id),
  date_option_id uuid not null references public.tournament_date_options(id) on delete cascade,
  primary key (tournament_id, player_id, date_option_id)
);

alter table public.tournament_date_votes enable row level security;
create policy "tdv read" on public.tournament_date_votes for select using (true);
create policy "tdv own"  on public.tournament_date_votes
  for all
  using  (player_id in (select id from public.players where email = (auth.jwt() ->> 'email')))
  with check (player_id in (select id from public.players where email = (auth.jwt() ->> 'email')));

-- ── 5. Durchgänge (je 1 Team mit fester Startzeit) ──────────────
create table if not exists public.tournament_rounds (
  id            uuid     primary key default gen_random_uuid(),
  tournament_id uuid     not null references public.tournaments(id) on delete cascade,
  round_number  smallint not null,
  team_name     text,
  start_time    time     not null,
  lane_count    smallint not null default 4,
  created_at    timestamptz default now()
);

alter table public.tournament_rounds enable row level security;
create policy "tr read"  on public.tournament_rounds for select using (true);
create policy "tr write" on public.tournament_rounds
  for all using (
    exists (select 1 from public.players where email = (auth.jwt() ->> 'email') and role in ('kapitaen','admin'))
  ) with check (true);

-- ── 6. Spieler-Zuweisung zu Bahnen ──────────────────────────────
create table if not exists public.tournament_round_players (
  round_id    uuid     not null references public.tournament_rounds(id) on delete cascade,
  lane_number smallint not null,
  player_id   uuid     references public.players(id),
  score       integer,
  primary key (round_id, lane_number)
);

alter table public.tournament_round_players enable row level security;
create policy "trp read"        on public.tournament_round_players for select using (true);
create policy "trp write"       on public.tournament_round_players
  for all using (
    exists (select 1 from public.players where email = (auth.jwt() ->> 'email') and role in ('kapitaen','admin'))
  ) with check (true);
create policy "trp self-assign" on public.tournament_round_players
  for insert with check (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );
create policy "trp self-remove" on public.tournament_round_players
  for delete using (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );
