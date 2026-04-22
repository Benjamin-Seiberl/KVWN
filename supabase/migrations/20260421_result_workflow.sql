-- Enums (idempotent via DO block)
DO $$ BEGIN
  CREATE TYPE result_state_t AS ENUM ('empty','draft','published');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE result_mode_t AS ENUM ('gesamt','detailliert');
EXCEPTION WHEN duplicate_object THEN null; END $$;

ALTER TABLE public.game_plan_players
  ADD COLUMN IF NOT EXISTS result_state result_state_t NOT NULL DEFAULT 'empty',
  ADD COLUMN IF NOT EXISTS published_at timestamptz;

ALTER TABLE public.game_plans
  ADD COLUMN IF NOT EXISTS result_mode         result_mode_t NOT NULL DEFAULT 'gesamt',
  ADD COLUMN IF NOT EXISTS result_published_at timestamptz;

CREATE TABLE IF NOT EXISTS public.game_plan_player_lanes (
  id                   uuid primary key default gen_random_uuid(),
  game_plan_player_id  uuid not null references public.game_plan_players(id) on delete cascade,
  bahn                 smallint not null check (bahn between 1 and 4),
  volle                integer  check (volle     is null or volle     >= 0),
  abraeumen            integer  check (abraeumen is null or abraeumen >= 0),
  created_at           timestamptz default now(),
  unique (game_plan_player_id, bahn)
);

CREATE INDEX IF NOT EXISTS idx_gpp_result_state   ON public.game_plan_players (result_state) WHERE result_state <> 'empty';
CREATE INDEX IF NOT EXISTS idx_gp_result_published ON public.game_plans (result_published_at) WHERE result_published_at IS NOT NULL;

-- Backfill
UPDATE public.game_plan_players
   SET result_state='published', published_at=now()
 WHERE played=true AND score IS NOT NULL AND result_state='empty';

UPDATE public.game_plans gp
   SET result_published_at = now()
 WHERE result_published_at IS NULL
   AND EXISTS (SELECT 1 FROM public.game_plan_players p WHERE p.game_plan_id = gp.id AND p.result_state='published');

-- RLS lanes
ALTER TABLE public.game_plan_player_lanes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "game_plan_player_lanes read published or captain" ON public.game_plan_player_lanes;
CREATE POLICY "game_plan_player_lanes read published or captain" ON public.game_plan_player_lanes
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.game_plan_players p
      JOIN public.game_plans gp ON gp.id = p.game_plan_id
      WHERE p.id = game_plan_player_lanes.game_plan_player_id
        AND (gp.result_published_at IS NOT NULL
          OR EXISTS (SELECT 1 FROM public.players WHERE email = (auth.jwt() ->> 'email') AND role IN ('kapitaen','admin')))
    )
  );

DROP POLICY IF EXISTS "game_plan_player_lanes kapitaen write" ON public.game_plan_player_lanes;
CREATE POLICY "game_plan_player_lanes kapitaen write" ON public.game_plan_player_lanes
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.players WHERE email = (auth.jwt() ->> 'email') AND role IN ('kapitaen','admin'))
  ) WITH CHECK (true);
