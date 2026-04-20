-- Kalender Übersicht features: Geburtstage + Schlüssel-Dienst

-- Geburtstage für Geburtstags-Pillen im Feed
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS birth_date DATE;

-- Schlüssel-Dienst pro Trainings-Session (date + start_time)
CREATE TABLE IF NOT EXISTS public.training_key_duties (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date       DATE NOT NULL,
  start_time TIME NOT NULL,
  player_id  UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(date, start_time)
);

ALTER TABLE public.training_key_duties ENABLE ROW LEVEL SECURITY;

-- Alle eingeloggten Mitglieder dürfen lesen
CREATE POLICY "training_key_duties read" ON public.training_key_duties
  FOR SELECT USING (true);

-- Nur eigener Eintrag (übernehmen / freigeben)
CREATE POLICY "training_key_duties own player" ON public.training_key_duties
  FOR ALL
  USING (
    player_id IN (
      SELECT id FROM public.players WHERE email = (auth.jwt() ->> 'email')
    )
  )
  WITH CHECK (
    player_id IN (
      SELECT id FROM public.players WHERE email = (auth.jwt() ->> 'email')
    )
  );
