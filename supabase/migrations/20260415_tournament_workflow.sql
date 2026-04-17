-- Tournament Workflow Erweiterung
-- Ergänzt: tournament_rounds, tournament_round_players (bisher fehlend),
--          tournament_date_options, tournament_votes, tournament_date_votes
-- sowie tournament_status-Spalte auf matches.
-- Manuell in Supabase Studio anwenden oder via CLI `supabase db push`.

-- =========================
-- Status-Spalte auf matches
-- =========================
alter table public.matches
  add column if not exists tournament_status text default 'voting'
  check (tournament_status in ('voting','voting_closed','scheduling','confirmed'));

-- =========================
-- Turnier-Durchgänge / Teams
-- =========================
create table if not exists public.tournament_rounds (
  id           uuid    primary key default gen_random_uuid(),
  match_id     uuid    not null references public.matches(id) on delete cascade,
  round_number smallint not null,
  start_time   time    not null,
  lane_count   smallint not null default 4,
  team_name    text,
  created_at   timestamptz default now()
);

alter table public.tournament_rounds enable row level security;

create policy "tournament_rounds read" on public.tournament_rounds
  for select using (true);

create policy "tournament_rounds write (kapitaen)" on public.tournament_rounds
  for all
  using (
    exists (
      select 1 from public.players pl
      where pl.email = (auth.jwt() ->> 'email')
        and pl.role in ('kapitaen','admin')
    )
  )
  with check (true);

-- =========================
-- Spieler-Zuweisung zu Bahnen
-- =========================
create table if not exists public.tournament_round_players (
  round_id    uuid     not null references public.tournament_rounds(id) on delete cascade,
  lane_number smallint not null,
  player_id   uuid     references public.players(id),
  score       integer,
  primary key (round_id, lane_number)
);

alter table public.tournament_round_players enable row level security;

create policy "tournament_round_players read" on public.tournament_round_players
  for select using (true);

create policy "tournament_round_players write (kapitaen)" on public.tournament_round_players
  for all
  using (
    exists (
      select 1 from public.players pl
      where pl.email = (auth.jwt() ->> 'email')
        and pl.role in ('kapitaen','admin')
    )
  )
  with check (true);

-- Spieler können sich selbst in eine freie Bahn eintragen (Selbst-Zuweisung)
create policy "tournament_round_players self-assign" on public.tournament_round_players
  for insert
  with check (
    player_id in (
      select id from public.players where email = (auth.jwt() ->> 'email')
    )
  );

create policy "tournament_round_players self-remove" on public.tournament_round_players
  for delete
  using (
    player_id in (
      select id from public.players where email = (auth.jwt() ->> 'email')
    )
  );

-- =========================
-- Mögliche Turniertage (bis 5)
-- =========================
create table if not exists public.tournament_date_options (
  id            uuid  primary key default gen_random_uuid(),
  tournament_id uuid  not null references public.matches(id) on delete cascade,
  date          date  not null,
  created_at    timestamptz default now()
);

alter table public.tournament_date_options enable row level security;

create policy "tournament_date_options read" on public.tournament_date_options
  for select using (true);

create policy "tournament_date_options write (kapitaen)" on public.tournament_date_options
  for all
  using (
    exists (
      select 1 from public.players pl
      where pl.email = (auth.jwt() ->> 'email')
        and pl.role in ('kapitaen','admin')
    )
  )
  with check (true);

-- =========================
-- Teilnahme-Abstimmung
-- =========================
create table if not exists public.tournament_votes (
  tournament_id uuid    not null references public.matches(id) on delete cascade,
  player_id     uuid    not null references public.players(id),
  wants_to_play boolean not null default true,
  created_at    timestamptz default now(),
  primary key (tournament_id, player_id)
);

alter table public.tournament_votes enable row level security;

create policy "tournament_votes read" on public.tournament_votes
  for select using (true);

create policy "tournament_votes own" on public.tournament_votes
  for all
  using (
    player_id in (
      select id from public.players where email = (auth.jwt() ->> 'email')
    )
  )
  with check (
    player_id in (
      select id from public.players where email = (auth.jwt() ->> 'email')
    )
  );

-- =========================
-- Terminwahl pro Spieler
-- =========================
create table if not exists public.tournament_date_votes (
  tournament_id  uuid not null references public.matches(id) on delete cascade,
  player_id      uuid not null references public.players(id),
  date_option_id uuid not null references public.tournament_date_options(id) on delete cascade,
  primary key (tournament_id, player_id, date_option_id)
);

alter table public.tournament_date_votes enable row level security;

create policy "tournament_date_votes read" on public.tournament_date_votes
  for select using (true);

create policy "tournament_date_votes own" on public.tournament_date_votes
  for all
  using (
    player_id in (
      select id from public.players where email = (auth.jwt() ->> 'email')
    )
  )
  with check (
    player_id in (
      select id from public.players where email = (auth.jwt() ->> 'email')
    )
  );
