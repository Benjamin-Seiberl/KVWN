-- One-off ("Sonder") trainings outside the weekly template.
-- Separate table from training_overrides because fields (end_time, capacity)
-- and semantics (create a session vs modify one) differ.

CREATE TABLE IF NOT EXISTS public.training_specials (
  id         UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
  date       DATE     NOT NULL,
  start_time TIME     NOT NULL,
  end_time   TIME     NOT NULL,
  capacity   SMALLINT NOT NULL DEFAULT 4,
  note       TEXT,
  created_by UUID     REFERENCES public.players(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(date, start_time)
);

CREATE INDEX IF NOT EXISTS training_specials_date_idx
  ON public.training_specials(date);

ALTER TABLE public.training_specials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "specials read"    ON public.training_specials;
DROP POLICY IF EXISTS "specials captain" ON public.training_specials;

CREATE POLICY "specials read"
  ON public.training_specials FOR SELECT USING (true);

CREATE POLICY "specials captain"
  ON public.training_specials FOR ALL
  USING (EXISTS (SELECT 1 FROM public.players
                 WHERE email = (auth.jwt() ->> 'email')
                   AND role IN ('kapitaen','admin')))
  WITH CHECK (EXISTS (SELECT 1 FROM public.players
                      WHERE email = (auth.jwt() ->> 'email')
                        AND role IN ('kapitaen','admin')));
