-- RPCs for capacity-based training bookings.
-- _training_capacity : resolves capacity for a (date, start_time) — special > template, override closes.
-- book_training_slot : atomic book or waitlist.
-- cancel_training_booking : storno + promote head of waitlist (with position compaction).

-- ── capacity resolver ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._training_capacity(p_date DATE, p_start TIME)
RETURNS INT
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE cap INT;
BEGIN
  -- closed override → 0 (can't book)
  IF EXISTS (SELECT 1 FROM training_overrides
             WHERE date = p_date AND start_time = p_start AND closed) THEN
    RETURN 0;
  END IF;

  -- special session wins over template
  SELECT capacity INTO cap FROM training_specials
    WHERE date = p_date AND start_time = p_start;
  IF cap IS NOT NULL THEN RETURN cap; END IF;

  -- template match via weekday + time range
  SELECT lane_count INTO cap FROM training_templates
    WHERE active
      AND day_of_week = EXTRACT(DOW FROM p_date)::INT
      AND start_time <= p_start
      AND end_time   > p_start
    ORDER BY start_time DESC
    LIMIT 1;

  RETURN COALESCE(cap, 0);
END $$;

-- ── book / waitlist ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.book_training_slot(p_date DATE, p_start TIME)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_pid   UUID;
  v_cap   INT;
  v_taken INT;
  v_pos   INT;
BEGIN
  SELECT id INTO v_pid FROM players
    WHERE email = (auth.jwt() ->> 'email');
  IF v_pid IS NULL THEN
    RAISE EXCEPTION 'no_player';
  END IF;

  v_cap := public._training_capacity(p_date, p_start);
  IF v_cap <= 0 THEN
    RAISE EXCEPTION 'slot_not_bookable';
  END IF;

  -- idempotency: already booked
  IF EXISTS (SELECT 1 FROM training_bookings
             WHERE date = p_date AND start_time = p_start AND player_id = v_pid) THEN
    RETURN jsonb_build_object('status', 'already_booked');
  END IF;

  -- idempotency: already on waitlist
  IF EXISTS (SELECT 1 FROM training_waitlist
             WHERE date = p_date AND start_time = p_start AND player_id = v_pid) THEN
    RETURN jsonb_build_object('status', 'already_waitlisted');
  END IF;

  SELECT COUNT(*) INTO v_taken FROM training_bookings
    WHERE date = p_date AND start_time = p_start;

  IF v_taken < v_cap THEN
    INSERT INTO training_bookings(date, start_time, player_id)
      VALUES (p_date, p_start, v_pid);
    RETURN jsonb_build_object('status', 'booked');
  END IF;

  SELECT COALESCE(MAX(position), 0) + 1 INTO v_pos FROM training_waitlist
    WHERE date = p_date AND start_time = p_start;

  INSERT INTO training_waitlist(date, start_time, player_id, position)
    VALUES (p_date, p_start, v_pid, v_pos);

  RETURN jsonb_build_object('status', 'waitlisted', 'position', v_pos);
END $$;

-- ── cancel + promote ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_training_booking(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_pid  UUID;
  v_row  training_bookings%ROWTYPE;
  v_next training_waitlist%ROWTYPE;
BEGIN
  SELECT id INTO v_pid FROM players
    WHERE email = (auth.jwt() ->> 'email');
  IF v_pid IS NULL THEN RAISE EXCEPTION 'no_player'; END IF;

  SELECT * INTO v_row FROM training_bookings WHERE id = p_booking_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_row.player_id <> v_pid THEN RAISE EXCEPTION 'not_your_booking'; END IF;

  -- Fair-play: storno only until 23:59 day before
  IF v_row.date <= CURRENT_DATE THEN
    RAISE EXCEPTION 'same_day_storno_forbidden';
  END IF;

  DELETE FROM training_bookings WHERE id = p_booking_id;

  SELECT * INTO v_next FROM training_waitlist
    WHERE date = v_row.date AND start_time = v_row.start_time
    ORDER BY position ASC
    LIMIT 1;

  IF v_next.id IS NOT NULL THEN
    INSERT INTO training_bookings(date, start_time, player_id)
      VALUES (v_next.date, v_next.start_time, v_next.player_id);
    DELETE FROM training_waitlist WHERE id = v_next.id;
    UPDATE training_waitlist
      SET position = position - 1
      WHERE date = v_next.date AND start_time = v_next.start_time;
    RETURN jsonb_build_object(
      'promoted_player_id', v_next.player_id,
      'date',               v_row.date,
      'start_time',         v_row.start_time
    );
  END IF;

  RETURN jsonb_build_object('promoted_player_id', NULL);
END $$;

REVOKE ALL ON FUNCTION public._training_capacity(DATE, TIME)     FROM PUBLIC;
REVOKE ALL ON FUNCTION public.book_training_slot(DATE, TIME)     FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_training_booking(UUID)      FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public._training_capacity(DATE, TIME)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.book_training_slot(DATE, TIME)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_training_booking(UUID)   TO authenticated;
