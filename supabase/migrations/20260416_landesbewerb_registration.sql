-- Landesbewerb-Anmeldung + Migration bestehender Events
-- ───────────────────────────────────────────────────────────
-- 1) registration_deadline-Spalte auf matches
-- 2) Bestehende "Meisterschaft"-Events aus events → matches verschieben
--    (werden zu Landesbewerben mit is_landesbewerb=true, is_tournament=true)
-- 3) Anmeldungen nutzen die bestehende Tabelle tournament_votes
--    (Anmeldung = Zeile mit wants_to_play=true)

-- ====================================================
-- A. registration_deadline-Spalte
-- ====================================================
alter table public.matches
  add column if not exists registration_deadline timestamptz;

-- ====================================================
-- B. Events → Landesbewerbe migrieren
-- ====================================================
-- Keyword-basiert: landesmeisterschaft | landesbewerb | bezirksmeisterschaft |
--                  nö-/noe- (als Prefix) | meisterschaft
-- Case-insensitive Regex (~*)

insert into public.matches (
  id, date, time, is_landesbewerb, is_tournament,
  tournament_title, tournament_location, opponent, home_away
)
select
  gen_random_uuid(),
  e.date,
  e.time,
  true,
  true,
  e.title,
  e.location,
  e.title,
  'HEIM'
from public.events e
where e.title ~* '(landesmeisterschaft|landesbewerb|bezirksmeisterschaft|n[öo]\.?-|meisterschaft)';

delete from public.events
where title ~* '(landesmeisterschaft|landesbewerb|bezirksmeisterschaft|n[öo]\.?-|meisterschaft)';
