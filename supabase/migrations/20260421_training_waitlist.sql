-- Waitlist for full training slots. Capacity-based bookings push overflow here;
-- cancel_training_booking promotes head of the waitlist.

CREATE TABLE IF NOT EXISTS public.training_waitlist (
  id         UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
  date       DATE     NOT NULL,
  start_time TIME     NOT NULL,
  player_id  UUID     NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  position   SMALLINT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(date, start_time, player_id),
  UNIQUE(date, start_time, position)
);

CREATE INDEX IF NOT EXISTS training_waitlist_slot_idx
  ON public.training_waitlist(date, start_time, position);

ALTER TABLE public.training_waitlist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "waitlist read"          ON public.training_waitlist;
DROP POLICY IF EXISTS "waitlist insert own"    ON public.training_waitlist;
DROP POLICY IF EXISTS "waitlist delete own"    ON public.training_waitlist;

CREATE POLICY "waitlist read"
  ON public.training_waitlist FOR SELECT USING (true);

CREATE POLICY "waitlist insert own"
  ON public.training_waitlist FOR INSERT
  WITH CHECK (player_id IN (SELECT id FROM public.players
                            WHERE email = (auth.jwt() ->> 'email')));

CREATE POLICY "waitlist delete own"
  ON public.training_waitlist FOR DELETE
  USING (
    player_id IN (SELECT id FROM public.players WHERE email = (auth.jwt() ->> 'email'))
    OR EXISTS (SELECT 1 FROM public.players
               WHERE email = (auth.jwt() ->> 'email')
                 AND role IN ('kapitaen','admin'))
  );
-- no UPDATE policy → updates denied
