-- Profil Self-Service: neue players-Spalten, Attest-Storage-Bucket,
-- erstmalige RLS auf public.players (self-update mit geschützten Spalten,
-- Kapitän-Override für alles, Select für alle Eingeloggten).

-- 1. Neue Spalten auf players (idempotent via IF NOT EXISTS).
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS jersey_number           int,
  ADD COLUMN IF NOT EXISTS shoe_size               text,
  ADD COLUMN IF NOT EXISTS emergency_contact_name  text,
  ADD COLUMN IF NOT EXISTS emergency_contact_phone text,
  ADD COLUMN IF NOT EXISTS iban                    text,
  ADD COLUMN IF NOT EXISTS account_holder          text,
  ADD COLUMN IF NOT EXISTS member_since            date,
  ADD COLUMN IF NOT EXISTS membership_status       text
    DEFAULT 'aktiv'
    CHECK (membership_status IN ('aktiv','passiv','nachwuchs','ehrenmitglied','ruhend')),
  ADD COLUMN IF NOT EXISTS drivers_license         boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS default_car_seats       int,
  ADD COLUMN IF NOT EXISTS dietary_notes           text,
  ADD COLUMN IF NOT EXISTS consent_photo           boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS consent_liga_data       boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS consent_whatsapp        boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS consent_accepted_at     timestamptz,
  ADD COLUMN IF NOT EXISTS attest_url              text;

-- 2. Trikotnummer 1..99 (nur wenn gesetzt).
ALTER TABLE public.players
  DROP CONSTRAINT IF EXISTS players_jersey_number_range;
ALTER TABLE public.players
  ADD CONSTRAINT players_jersey_number_range
  CHECK (jersey_number IS NULL OR (jersey_number BETWEEN 1 AND 99));

-- 3. Trikotnummer clubweit eindeutig (nur wenn gesetzt).
CREATE UNIQUE INDEX IF NOT EXISTS players_jersey_number_uq
  ON public.players (jersey_number)
  WHERE jersey_number IS NOT NULL;

-- 4. Storage-Bucket für Atteste (privat).
INSERT INTO storage.buckets (id, name, public)
  VALUES ('attests', 'attests', false)
  ON CONFLICT (id) DO NOTHING;

-- 4a. Storage-Policies: Spieler liest/schreibt nur eigenen Ordner
--     (attests/<player_id>/…). Kapitän/Admin liest alle.
DROP POLICY IF EXISTS "attests read own"        ON storage.objects;
DROP POLICY IF EXISTS "attests write own"       ON storage.objects;
DROP POLICY IF EXISTS "attests update own"      ON storage.objects;
DROP POLICY IF EXISTS "attests kapitaen read"   ON storage.objects;

CREATE POLICY "attests read own" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'attests'
    AND (storage.foldername(name))[1] = (
      SELECT id::text FROM public.players WHERE email = (auth.jwt() ->> 'email')
    )
  );

CREATE POLICY "attests write own" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'attests'
    AND (storage.foldername(name))[1] = (
      SELECT id::text FROM public.players WHERE email = (auth.jwt() ->> 'email')
    )
  );

CREATE POLICY "attests update own" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'attests'
    AND (storage.foldername(name))[1] = (
      SELECT id::text FROM public.players WHERE email = (auth.jwt() ->> 'email')
    )
  );

CREATE POLICY "attests kapitaen read" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'attests'
    AND EXISTS (
      SELECT 1 FROM public.players
      WHERE email = (auth.jwt() ->> 'email')
        AND role IN ('kapitaen','admin')
    )
  );

-- 5. RLS auf public.players (erstmalig).
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

-- 5a. Alle Eingeloggten lesen alle Spieler (Kader, Statistiken, Suche etc.).
DROP POLICY IF EXISTS "players read" ON public.players;
CREATE POLICY "players read" ON public.players
  FOR SELECT USING (true);

-- 5b. Kapitän/Admin schreibt alles.
DROP POLICY IF EXISTS "players kapitaen write" ON public.players;
CREATE POLICY "players kapitaen write" ON public.players
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.players p
      WHERE p.email = (auth.jwt() ->> 'email')
        AND p.role IN ('kapitaen','admin')
    )
  );

-- 5c. Self-Update: eigene Zeile, geschützte Spalten dürfen sich nicht ändern.
--     role / active / membership_status / member_since / email bleiben gleich.
DROP POLICY IF EXISTS "players self update" ON public.players;
CREATE POLICY "players self update" ON public.players
  FOR UPDATE
  USING (email = (auth.jwt() ->> 'email'))
  WITH CHECK (
    email = (auth.jwt() ->> 'email')
    AND role              IS NOT DISTINCT FROM (SELECT role              FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    AND active            IS NOT DISTINCT FROM (SELECT active            FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    AND membership_status IS NOT DISTINCT FROM (SELECT membership_status FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    AND member_since      IS NOT DISTINCT FROM (SELECT member_since      FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    AND email             IS NOT DISTINCT FROM (auth.jwt() ->> 'email')
  );
