-- KVWN — FOUND-05 Migration: players.push_prefs JSONB + CHECK-Whitelist
--
-- Quelle: 0-CONTEXT.md D-06, 0-RESEARCH.md Z 493-510
-- Pitfall: PITFALLS.md C9 (Push-Pref-Bypass via Tippfehler)
--
-- Wichtig: Keys MUESSEN identisch mit src/lib/constants/pushPrefs.js sein.
-- Bei Schema-Aenderung beide Files updaten (eigene Migration mit DROP+ADD).
--
-- File-Prefix: 20260430e_ (nach a/b/c/d aus Plans 0-06/0-07; alphabetisch geordnet
-- damit Supabase Migrations deterministisch runnen).

-- 1. Spalte ergaenzen (idempotent).
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS push_prefs JSONB NOT NULL DEFAULT '{}'::jsonb;

-- 2. CHECK-Constraint mit Whitelist (idempotent via DROP+ADD).
ALTER TABLE public.players
  DROP CONSTRAINT IF EXISTS players_push_prefs_keys;

ALTER TABLE public.players
  ADD CONSTRAINT players_push_prefs_keys CHECK (
    jsonb_typeof(push_prefs) = 'object'
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(push_prefs) k
      WHERE k NOT IN (
        'training_24h',
        'event_new',
        'event_reminder',
        'poll_close',
        'birthday'
      )
    )
  );
