DROP POLICY IF EXISTS "match_feedback read own" ON public.match_feedback;
CREATE POLICY "match_feedback read own" ON public.match_feedback
  FOR SELECT USING (
    player_id IN (SELECT id FROM public.players WHERE email = (auth.jwt() ->> 'email'))
  );

CREATE OR REPLACE FUNCTION public.read_anon_feedback(p_match_id uuid)
RETURNS TABLE(id uuid, question_id uuid, answer text, created_at timestamptz)
SECURITY DEFINER
LANGUAGE sql
AS $$
  SELECT f.id, f.question_id, f.answer, f.created_at
  FROM public.match_feedback f
  WHERE f.match_id = p_match_id
    AND EXISTS (
      SELECT 1 FROM public.players
      WHERE email = (auth.jwt() ->> 'email') AND role IN ('kapitaen','admin')
    );
$$;

REVOKE ALL ON FUNCTION public.read_anon_feedback(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.read_anon_feedback(uuid) TO authenticated;
