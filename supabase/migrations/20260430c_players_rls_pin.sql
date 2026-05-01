-- KVWN — FOUND-02: RLS-Policy 'players kapitaen write' mit WITH CHECK ergaenzen.
--
-- KORREKTUR zu CONTEXT D-04: NICHT die 2 bestehenden Policies (`players kapitaen write`
-- + `players self update`) zu 1 combined-Policy verschmelzen. Stattdessen NUR die
-- Captain-Policy um WITH CHECK ergaenzen. `players self update` bleibt unveraendert
-- (existiert bereits korrekt mit Email-Pin in WITH CHECK — siehe 0-RESEARCH.md Z 91-97).
--
-- ZIEL: Defense-in-depth. Heute kann Captain `role`, `active`, `email` einer beliebigen
-- Row auf beliebige Werte setzen — ohne Constraint. Nach dieser Migration:
--   - USING-Klausel UND WITH CHECK-Klausel beide pruefen Captain-Status
--   - Verhindert insbesondere Tippfehler-Self-Demotion (Captain setzt versehentlich
--     eigenes role='user' — ohne WITH CHECK ginge das durch).
--
-- Pitfall-Source: PITFALLS.md C1 (RLS-Cross-Write).
-- Pattern-Analog: 20260421_training_codify.sql Z 67-73 (`training_templates captain`).

-- DROP+CREATE der Captain-Policy (idempotent).
-- WICHTIG: Nur `players kapitaen write` aendern — `players self update` und `players read`
-- bleiben unveraendert.
DROP POLICY IF EXISTS "players kapitaen write" ON public.players;

CREATE POLICY "players kapitaen write" ON public.players
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.players p
      WHERE p.email = (auth.jwt() ->> 'email')
        AND p.role IN ('kapitaen','admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.players p
      WHERE p.email = (auth.jwt() ->> 'email')
        AND p.role IN ('kapitaen','admin')
    )
  );
