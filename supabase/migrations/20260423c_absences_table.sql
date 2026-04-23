-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Abwesenheiten – Spieler melden Zeiträume in denen sie      ║
-- ║  nicht verfügbar sind (Urlaub, Verletzung, Beruf, …).       ║
-- ║  Wird von Aufstellungs-/Eligibility-Logik konsumiert.       ║
-- ╚══════════════════════════════════════════════════════════════╝

create table if not exists public.absences (
  id         uuid        primary key default gen_random_uuid(),
  player_id  uuid        not null references public.players(id) on delete cascade,
  from_date  date        not null,
  to_date    date        not null,
  reason     text,
  created_at timestamptz not null default now(),
  check (from_date <= to_date)
);

-- Schneller Lookup für Eligibility / Konflikt-Check
create index if not exists absences_player_range_idx
  on public.absences (player_id, from_date, to_date);

alter table public.absences enable row level security;

-- eigene Zeilen lesen
drop policy if exists "absences_select_own" on public.absences;
create policy "absences_select_own" on public.absences
  for select using (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );

-- kapitaen / admin sehen alle
drop policy if exists "absences_select_kapitaen" on public.absences;
create policy "absences_select_kapitaen" on public.absences
  for select using (
    exists (
      select 1 from public.players
      where email = (auth.jwt() ->> 'email')
        and role in ('kapitaen','admin')
    )
  );

-- eigene Abwesenheit eintragen
drop policy if exists "absences_insert_own" on public.absences;
create policy "absences_insert_own" on public.absences
  for insert with check (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );

-- eigene Abwesenheit löschen
drop policy if exists "absences_delete_own" on public.absences;
create policy "absences_delete_own" on public.absences
  for delete using (
    player_id in (select id from public.players where email = (auth.jwt() ->> 'email'))
  );
