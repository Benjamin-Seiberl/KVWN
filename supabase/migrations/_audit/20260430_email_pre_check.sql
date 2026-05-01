-- KVWN — FOUND-01 Pre-Deploy-Audit (NICHT auto-applied — _audit/-Subordner)
-- Run in Supabase Studio. BEIDE Result-Sets muessen 0 Rows liefern VOR `supabase db push`.
--
-- Wenn Rows vorhanden -> siehe docs/runbooks/email-cleanup.md fuer Captain-Konsolidierungs-Schritte.
-- Re-run dieses Skripts bis beide Queries 0 Rows liefern.

-- Query 1: NULL-Emails (Spieler ohne Email-Adresse)
SELECT id, name, email
FROM public.players
WHERE email IS NULL
ORDER BY name;

-- Query 2: Duplicate-Emails (case-insensitive — lower() weil Migration retroaktiv lowercased)
SELECT
  lower(email) AS norm_email,
  COUNT(*)     AS dupe_count,
  array_agg(id ORDER BY name) AS player_ids,
  array_agg(name ORDER BY name) AS player_names
FROM public.players
WHERE email IS NOT NULL
GROUP BY lower(email)
HAVING COUNT(*) > 1
ORDER BY norm_email;
