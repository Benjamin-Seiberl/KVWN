-- event_rsvps — Source-control sync for the table that backs Event-Zusagen
-- (Kalender EventDetailSheet & Profil/Termine). Table was created directly in
-- production at some point in the 2026-04-15 cluster but never committed as a
-- migration file. This migration captures the live shape so a fresh project
-- bootstrap is reproducible. Idempotent — safe to re-apply.

CREATE TABLE IF NOT EXISTS public.event_rsvps (
    event_id    uuid        NOT NULL REFERENCES public.events(id)  ON DELETE CASCADE,
    player_id   uuid        NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    response    text        NOT NULL CHECK (response IN ('yes','no')),
    created_at  timestamptz          DEFAULT now(),
    PRIMARY KEY (event_id, player_id)
);

ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;

-- SELECT: every authenticated player sees all RSVPs (club-wide event visibility).
DROP POLICY IF EXISTS "Players read all rsvps" ON public.event_rsvps;
CREATE POLICY "Players read all rsvps"
    ON public.event_rsvps
    FOR SELECT
    TO authenticated
    USING (true);

-- INSERT/UPDATE/DELETE: only the row owner (own-row pattern via email bridge).
DROP POLICY IF EXISTS "Players manage own rsvps" ON public.event_rsvps;
CREATE POLICY "Players manage own rsvps"
    ON public.event_rsvps
    FOR ALL
    TO authenticated
    USING (
        player_id = (
            SELECT id FROM public.players
            WHERE email = (auth.jwt() ->> 'email')
            LIMIT 1
        )
    )
    WITH CHECK (
        player_id = (
            SELECT id FROM public.players
            WHERE email = (auth.jwt() ->> 'email')
            LIMIT 1
        )
    );

-- The PK btree (event_id, player_id) already covers "all RSVPs for event X"
-- lookups as the leading column — no extra index needed.
