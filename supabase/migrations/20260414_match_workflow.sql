-- Match-Workflow Erweiterung
-- Ergänzt: Treffpunkt, Fahrgemeinschaften, Zuschauer, Lokal-Voting, Feedback
-- Manuell in Supabase Studio anwenden oder via CLI `supabase db push`.

-- =========================
-- Treffpunkt (1:1 pro Match, vom Kapitän gesetzt)
-- =========================
create table if not exists public.match_meetups (
	match_id      uuid primary key references public.matches(id) on delete cascade,
	location_name text not null,
	location_url  text,
	meet_time     time not null,
	note          text,
	updated_by    uuid references public.players(id),
	updated_at    timestamptz default now()
);

alter table public.match_meetups enable row level security;

create policy "match_meetups read" on public.match_meetups
	for select using (true);

create policy "match_meetups write (kapitaen/admin)" on public.match_meetups
	for all
	using (
		exists (
			select 1 from public.players pl
			where pl.email = (auth.jwt() ->> 'email')
			  and pl.role in ('kapitaen', 'admin')
		)
	)
	with check (true);

-- =========================
-- Fahrgemeinschaften
-- =========================
create table if not exists public.match_carpools (
	id          uuid primary key default gen_random_uuid(),
	match_id    uuid not null references public.matches(id) on delete cascade,
	driver_id   uuid not null references public.players(id),
	seats_total smallint not null check (seats_total between 1 and 8),
	depart_time time,
	depart_from text,
	note        text,
	created_at  timestamptz default now(),
	unique(match_id, driver_id)
);

alter table public.match_carpools enable row level security;

create policy "match_carpools read" on public.match_carpools
	for select using (true);

create policy "match_carpools own driver" on public.match_carpools
	for all
	using (
		driver_id in (
			select id from public.players where email = (auth.jwt() ->> 'email')
		)
	)
	with check (
		driver_id in (
			select id from public.players where email = (auth.jwt() ->> 'email')
		)
	);

create table if not exists public.match_carpool_seats (
	carpool_id   uuid not null references public.match_carpools(id) on delete cascade,
	passenger_id uuid not null references public.players(id),
	created_at   timestamptz default now(),
	primary key(carpool_id, passenger_id)
);

alter table public.match_carpool_seats enable row level security;

create policy "match_carpool_seats read" on public.match_carpool_seats
	for select using (true);

create policy "match_carpool_seats own passenger" on public.match_carpool_seats
	for all
	using (
		passenger_id in (
			select id from public.players where email = (auth.jwt() ->> 'email')
		)
	)
	with check (
		passenger_id in (
			select id from public.players where email = (auth.jwt() ->> 'email')
		)
	);

-- =========================
-- Zuschauer
-- =========================
create table if not exists public.match_supporters (
	match_id   uuid not null references public.matches(id) on delete cascade,
	player_id  uuid not null references public.players(id),
	created_at timestamptz default now(),
	primary key(match_id, player_id)
);

alter table public.match_supporters enable row level security;

create policy "match_supporters read" on public.match_supporters
	for select using (true);

create policy "match_supporters own" on public.match_supporters
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
-- Lokal-Vorschläge & Votes
-- =========================
create table if not exists public.match_venues (
	id          uuid primary key default gen_random_uuid(),
	match_id    uuid not null references public.matches(id) on delete cascade,
	name        text not null,
	proposed_by uuid references public.players(id),
	created_at  timestamptz default now()
);

alter table public.match_venues enable row level security;

create policy "match_venues read" on public.match_venues
	for select using (true);

create policy "match_venues propose (any player)" on public.match_venues
	for insert
	with check (
		proposed_by in (
			select id from public.players where email = (auth.jwt() ->> 'email')
		)
	);

create policy "match_venues delete (own)" on public.match_venues
	for delete
	using (
		proposed_by in (
			select id from public.players where email = (auth.jwt() ->> 'email')
		)
	);

create table if not exists public.match_venue_votes (
	match_id  uuid not null references public.matches(id) on delete cascade,
	player_id uuid not null references public.players(id),
	venue_id  uuid not null references public.match_venues(id) on delete cascade,
	primary key(match_id, player_id)
);

alter table public.match_venue_votes enable row level security;

create policy "match_venue_votes read" on public.match_venue_votes
	for select using (true);

create policy "match_venue_votes own" on public.match_venue_votes
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
-- Feedback-Fragen-Pool + Antworten
-- =========================
create table if not exists public.feedback_questions (
	id         uuid primary key default gen_random_uuid(),
	prompt     text not null,
	active     boolean default true,
	created_at timestamptz default now()
);

alter table public.feedback_questions enable row level security;

create policy "feedback_questions read" on public.feedback_questions
	for select using (true);

create table if not exists public.match_feedback (
	id          uuid primary key default gen_random_uuid(),
	match_id    uuid not null references public.matches(id) on delete cascade,
	player_id   uuid not null references public.players(id),
	question_id uuid references public.feedback_questions(id),
	answer      text not null,
	created_at  timestamptz default now(),
	unique(match_id, player_id)
);

alter table public.match_feedback enable row level security;

create policy "match_feedback read own" on public.match_feedback
	for select using (
		player_id in (
			select id from public.players where email = (auth.jwt() ->> 'email')
		)
		or exists (
			select 1 from public.players pl
			where pl.email = (auth.jwt() ->> 'email')
			  and pl.role in ('kapitaen', 'admin')
		)
	);

create policy "match_feedback own" on public.match_feedback
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
-- Seed: 20 Feedback-Fragen
-- =========================
insert into public.feedback_questions (prompt) values
	('Was hätte man heute besser machen können?'),
	('Wie war die Stimmung im Team aus deiner Sicht?'),
	('Gab es etwas an der Organisation, das dich gestört hat?'),
	('Was hat dir heute besonders gut gefallen?'),
	('Hast du dich gut vorbereitet gefühlt?'),
	('Würdest du am Ablauf etwas ändern?'),
	('Wie zufrieden warst du mit dem Treffpunkt?'),
	('Hat die Anreise reibungslos geklappt?'),
	('Was könnte der Kapitän besser machen?'),
	('Wie war das Lokal nach dem Match?'),
	('Fühlst du dich im Team wohl?'),
	('Gibt es etwas, das dich frustriert?'),
	('Welchen Vorschlag hast du für das nächste Match?'),
	('Wie war die Kommunikation im Vorfeld?'),
	('Hast du dich fair behandelt gefühlt?'),
	('Was brauchst du, um besser zu spielen?'),
	('Gibt es Mitspieler, die zu kurz kommen?'),
	('Wie ist dein Energielevel nach dem Match?'),
	('Fehlt dir etwas an der App?'),
	('Ein Wort, das deinen heutigen Tag beschreibt?')
on conflict do nothing;
