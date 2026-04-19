-- Rundencode direkt am Match speichern.
-- Ermöglicht Eligibility-Prüfung über Ligen hinweg ohne season-join.
-- Beispielwerte: 'H01', 'H02', 'F01', 'F03' usw.
ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS round_code TEXT;

-- game_plans: Rundencode übernehmen + Publish-Workflow
ALTER TABLE game_plans
  ADD COLUMN IF NOT EXISTS round_code            TEXT,
  ADD COLUMN IF NOT EXISTS lineup_published_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS confirmation_deadline DATE;

-- Index für Eligibility-Query: alle Aufstellungen einer Runde über alle Ligen
CREATE INDEX IF NOT EXISTS idx_game_plans_round_code ON game_plans (round_code)
  WHERE round_code IS NOT NULL;

-- Index für ActionHub-Query: offene Bestätigungen mit Frist
CREATE INDEX IF NOT EXISTS idx_game_plans_deadline ON game_plans (confirmation_deadline)
  WHERE lineup_published_at IS NOT NULL;
