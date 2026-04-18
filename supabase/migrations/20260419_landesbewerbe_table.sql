-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Landesbewerbe – eigenständige Tabelle                      ║
-- ║  (ersetzt matches-basiertes Design mit is_landesbewerb)     ║
-- ╚══════════════════════════════════════════════════════════════╝

create table if not exists public.landesbewerbe (
  id                    uuid        primary key default gen_random_uuid(),
  title                 text        not null,
  typ                   text        not null check (typ in (
    'einzel_ak_herren',
    'einzel_ak_damen',
    'nachwuchs_u10_maennlich',
    'nachwuchs_u10_weiblich',
    'nachwuchs_u15_maennlich',
    'nachwuchs_u15_weiblich',
    'nachwuchs_u19_maennlich',
    'nachwuchs_u19_weiblich',
    'nachwuchs_u23_maennlich',
    'nachwuchs_u23_weiblich',
    'ue50_herren',
    'ue50_damen',
    'ue60_herren',
    'ue60_damen',
    'lm_sprint_herren',
    'lm_sprint_damen',
    'tandem_mixed'
  )),
  location              text,
  date                  date,
  time                  time,
  registration_deadline timestamptz,
  created_at            timestamptz default now()
);

alter table public.landesbewerbe enable row level security;

create policy "landesbewerbe read" on public.landesbewerbe
  for select using (true);

create policy "landesbewerbe write (kapitaen)" on public.landesbewerbe
  for all
  using (
    exists (select 1 from public.players where email = (auth.jwt() ->> 'email') and role in ('kapitaen','admin'))
  )
  with check (true);

-- Anmeldungen
create table if not exists public.landesbewerb_registrations (
  landesbewerb_id uuid    not null references public.landesbewerbe(id) on delete cascade,
  player_id       uuid    not null references public.players(id),
  created_at      timestamptz default now(),
  primary key (landesbewerb_id, player_id)
);

alter table public.landesbewerb_registrations enable row level security;

create policy "lbr read" on public.landesbewerb_registrations
  for select using (true);

create policy "lbr own" on public.landesbewerb_registrations
  for all
  using  (player_id in (select id from public.players where email = (auth.jwt() ->> 'email')))
  with check (player_id in (select id from public.players where email = (auth.jwt() ->> 'email')));
