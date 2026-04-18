-- Turnier-Bugfixes + Voting-Deadline
-- 1) matches.date nullable machen (Turniere haben kein fixes Datum während der Voting-Phase)
-- 2) voting_deadline-Spalte hinzufügen

-- ====================================================
-- A. date nullable
-- ====================================================
alter table public.matches
  alter column date drop not null;

-- ====================================================
-- B. voting_deadline für Turnier-Abstimmungen
-- ====================================================
alter table public.matches
  add column if not exists voting_deadline timestamptz;
