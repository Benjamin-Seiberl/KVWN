-- Codify existing training tables (templates, overrides, bookings).
-- Tables exist live but had no migration file. Also makes
-- training_bookings.lane_number nullable so the new capacity-based flow can
-- insert rows without a lane. A follow-up migration drops the column entirely.

CREATE TABLE IF NOT EXISTS public.training_templates (
  id          UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
  day_of_week SMALLINT  NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time  TIME      NOT NULL,
  end_time    TIME      NOT NULL,
  lane_count  SMALLINT  NOT NULL DEFAULT 4,
  active      BOOLEAN   DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.training_overrides (
  id         UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  date       DATE    NOT NULL,
  start_time TIME    NOT NULL,
  closed     BOOLEAN DEFAULT FALSE,
  note       TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS training_overrides_date_time_uk
  ON public.training_overrides(date, start_time);

CREATE TABLE IF NOT EXISTS public.training_bookings (
  id          UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
  date        DATE     NOT NULL,
  start_time  TIME     NOT NULL,
  lane_number SMALLINT,
  player_id   UUID     REFERENCES public.players(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Drop legacy NOT NULL on lane_number (capacity-based flow doesn't set it)
ALTER TABLE public.training_bookings
  ALTER COLUMN lane_number DROP NOT NULL;

-- Guarantee player_id NOT NULL (was nullable in live schema)
UPDATE public.training_bookings SET player_id = NULL WHERE player_id IS NULL;
DELETE FROM public.training_bookings WHERE player_id IS NULL;
ALTER TABLE public.training_bookings
  ALTER COLUMN player_id SET NOT NULL;

-- Idempotent uniqueness so a player can't double-book a slot
CREATE UNIQUE INDEX IF NOT EXISTS training_bookings_slot_player_uk
  ON public.training_bookings(date, start_time, player_id);

CREATE INDEX IF NOT EXISTS training_bookings_date_time_idx
  ON public.training_bookings(date, start_time);

-- ── RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.training_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.training_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.training_bookings  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "training_templates read"        ON public.training_templates;
DROP POLICY IF EXISTS "training_templates captain"     ON public.training_templates;
DROP POLICY IF EXISTS "training_overrides read"        ON public.training_overrides;
DROP POLICY IF EXISTS "training_overrides captain"     ON public.training_overrides;
DROP POLICY IF EXISTS "training_bookings read"         ON public.training_bookings;
DROP POLICY IF EXISTS "training_bookings own"          ON public.training_bookings;

CREATE POLICY "training_templates read"
  ON public.training_templates FOR SELECT USING (true);

CREATE POLICY "training_templates captain"
  ON public.training_templates FOR ALL
  USING (EXISTS (SELECT 1 FROM public.players
                 WHERE email = (auth.jwt() ->> 'email')
                   AND role IN ('kapitaen','admin')))
  WITH CHECK (EXISTS (SELECT 1 FROM public.players
                      WHERE email = (auth.jwt() ->> 'email')
                        AND role IN ('kapitaen','admin')));

CREATE POLICY "training_overrides read"
  ON public.training_overrides FOR SELECT USING (true);

CREATE POLICY "training_overrides captain"
  ON public.training_overrides FOR ALL
  USING (EXISTS (SELECT 1 FROM public.players
                 WHERE email = (auth.jwt() ->> 'email')
                   AND role IN ('kapitaen','admin')))
  WITH CHECK (EXISTS (SELECT 1 FROM public.players
                      WHERE email = (auth.jwt() ->> 'email')
                        AND role IN ('kapitaen','admin')));

CREATE POLICY "training_bookings read"
  ON public.training_bookings FOR SELECT USING (true);

CREATE POLICY "training_bookings own"
  ON public.training_bookings FOR ALL
  USING (player_id IN (SELECT id FROM public.players
                       WHERE email = (auth.jwt() ->> 'email')))
  WITH CHECK (player_id IN (SELECT id FROM public.players
                            WHERE email = (auth.jwt() ->> 'email')));
