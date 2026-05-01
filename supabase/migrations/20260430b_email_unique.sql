-- KVWN — FOUND-01 Schritt 2/2: NOT NULL + UNIQUE + lowercase-Trigger
--
-- VORAUSSETZUNGEN:
--   1. Captain-Cleanup ist erfolgt (Audit-Skript zeigt 0 Rows)
--   2. 20260430a_email_audit.sql ist gelaufen (alle existierenden Emails sind lowercase)
--
-- Nach diesem Step:
--   - players.email ist NOT NULL UNIQUE (Index `players_email_uq`)
--   - BEFORE-INSERT/UPDATE-Trigger forciert lowercase auf zukuenftige Writes
--
-- Source: 0-RESEARCH.md Z 273-294 (verbatim).

-- 1. NOT NULL ergaenzen.
ALTER TABLE public.players ALTER COLUMN email SET NOT NULL;

-- 2. UNIQUE-Index (idempotent).
CREATE UNIQUE INDEX IF NOT EXISTS players_email_uq ON public.players (email);

-- 3. Trigger-Funktion: forciert lowercase auf INSERT/UPDATE OF email.
CREATE OR REPLACE FUNCTION public.players_email_lower()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.email := lower(NEW.email);
  RETURN NEW;
END;
$$;

-- 4. Trigger an die players-Tabelle binden (idempotent via DROP+CREATE).
DROP TRIGGER IF EXISTS players_email_lower_tg ON public.players;
CREATE TRIGGER players_email_lower_tg
  BEFORE INSERT OR UPDATE OF email ON public.players
  FOR EACH ROW EXECUTE FUNCTION public.players_email_lower();
