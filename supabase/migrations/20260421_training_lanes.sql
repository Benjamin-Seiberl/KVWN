-- Training bookings: zurück auf lane-basiert.
-- Backfill existing NULL lane_numbers, enforce NOT NULL + unique (date,start,lane),
-- replace book_training_slot with book_training_lane, update cancel_training_booking
-- to preserve lane when promoting waitlist head.

-- 1. Backfill: assign lane_number via row_number per (date,start_time), clamp to capacity.
WITH ranked AS (
  SELECT
    b.id,
    ROW_NUMBER() OVER (PARTITION BY b.date, b.start_time ORDER BY b.id) AS rn,
    public._training_capacity(b.date, b.start_time) AS cap
  FROM training_bookings b
  WHERE b.lane_number IS NULL
)
UPDATE training_bookings tb
SET    lane_number = r.rn::smallint
FROM   ranked r
WHERE  tb.id = r.id
  AND  r.rn <= GREATEST(r.cap, 1);

-- Safety: drop any overflow rows (> capacity). Should be zero in practice.
WITH ranked AS (
  SELECT
    b.id,
    ROW_NUMBER() OVER (PARTITION BY b.date, b.start_time ORDER BY b.id) AS rn,
    public._training_capacity(b.date, b.start_time) AS cap
  FROM training_bookings b
  WHERE b.lane_number IS NULL
)
DELETE FROM training_bookings tb
USING  ranked r
WHERE  tb.id = r.id
  AND  r.rn > GREATEST(r.cap, 1);

-- 2. lane_number NOT NULL.
ALTER TABLE training_bookings ALTER COLUMN lane_number SET NOT NULL;

-- 3. Unique (date, start_time, lane_number).
ALTER TABLE training_bookings
  DROP CONSTRAINT IF EXISTS training_bookings_lane_unique;
ALTER TABLE training_bookings
  ADD CONSTRAINT training_bookings_lane_unique
  UNIQUE (date, start_time, lane_number);

-- 4. Drop old capacity-based RPC.
DROP FUNCTION IF EXISTS public.book_training_slot(date, time);

-- 5. New lane-based booking RPC.
CREATE OR REPLACE FUNCTION public.book_training_lane(
  p_date  date,
  p_start time,
  p_lane  smallint
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_pid  UUID;
  v_cap  INT;
  v_taken INT;
  v_existing_lane SMALLINT;
  v_existing_pos  INT;
  v_pos  INT;
BEGIN
  SELECT id INTO v_pid FROM players
    WHERE email = (auth.jwt() ->> 'email');
  IF v_pid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  v_cap := public._training_capacity(p_date, p_start);
  IF v_cap <= 0 THEN
    RAISE EXCEPTION 'slot_closed';
  END IF;

  IF p_lane < 1 OR p_lane > v_cap THEN
    RAISE EXCEPTION 'invalid_lane';
  END IF;

  -- Idempotenz: user hat bereits Buchung in diesem Slot.
  SELECT lane_number INTO v_existing_lane FROM training_bookings
    WHERE date = p_date AND start_time = p_start AND player_id = v_pid;
  IF v_existing_lane IS NOT NULL THEN
    RETURN jsonb_build_object('status', 'already_booked', 'lane', v_existing_lane);
  END IF;

  -- Idempotenz: user ist bereits auf Warteliste.
  SELECT position INTO v_existing_pos FROM training_waitlist
    WHERE date = p_date AND start_time = p_start AND player_id = v_pid;
  IF v_existing_pos IS NOT NULL THEN
    RETURN jsonb_build_object('status', 'already_waitlisted', 'position', v_existing_pos);
  END IF;

  -- Lane belegt?
  IF EXISTS (
    SELECT 1 FROM training_bookings
     WHERE date = p_date AND start_time = p_start AND lane_number = p_lane
  ) THEN
    SELECT COUNT(*) INTO v_taken FROM training_bookings
      WHERE date = p_date AND start_time = p_start;

    IF v_taken >= v_cap THEN
      -- Slot komplett voll → Warteliste.
      SELECT COALESCE(MAX(position), 0) + 1 INTO v_pos FROM training_waitlist
        WHERE date = p_date AND start_time = p_start;
      INSERT INTO training_waitlist(date, start_time, player_id, position)
        VALUES (p_date, p_start, v_pid, v_pos);
      RETURN jsonb_build_object('status', 'waitlisted', 'position', v_pos);
    ELSE
      -- Nur die gewählte Lane ist belegt, andere sind frei.
      RETURN jsonb_build_object('status', 'lane_taken');
    END IF;
  END IF;

  INSERT INTO training_bookings(date, start_time, player_id, lane_number)
    VALUES (p_date, p_start, v_pid, p_lane);
  RETURN jsonb_build_object('status', 'booked', 'lane', p_lane);
END $function$;

-- 6. Cancel-RPC: Lane beim Nachrücken beibehalten.
CREATE OR REPLACE FUNCTION public.cancel_training_booking(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_pid   UUID;
  v_row   training_bookings%ROWTYPE;
  v_next  training_waitlist%ROWTYPE;
  v_lane  SMALLINT;
BEGIN
  SELECT id INTO v_pid FROM players
    WHERE email = (auth.jwt() ->> 'email');
  IF v_pid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_row FROM training_bookings WHERE id = p_booking_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_row.player_id <> v_pid THEN RAISE EXCEPTION 'not_your_booking'; END IF;

  IF v_row.date <= CURRENT_DATE THEN
    RAISE EXCEPTION 'same_day_storno_forbidden';
  END IF;

  v_lane := v_row.lane_number;

  DELETE FROM training_bookings WHERE id = p_booking_id;

  SELECT * INTO v_next FROM training_waitlist
    WHERE date = v_row.date AND start_time = v_row.start_time
    ORDER BY position ASC
    LIMIT 1;

  IF v_next.id IS NOT NULL THEN
    INSERT INTO training_bookings(date, start_time, player_id, lane_number)
      VALUES (v_next.date, v_next.start_time, v_next.player_id, v_lane);
    DELETE FROM training_waitlist WHERE id = v_next.id;
    UPDATE training_waitlist
      SET position = position - 1
      WHERE date = v_next.date
        AND start_time = v_next.start_time
        AND position > v_next.position;
    RETURN jsonb_build_object(
      'promoted_player_id', v_next.player_id,
      'date',               v_row.date,
      'start_time',         v_row.start_time,
      'promoted_lane',      v_lane
    );
  END IF;

  RETURN jsonb_build_object('promoted_player_id', NULL);
END $function$;

-- 7. Grants.
GRANT EXECUTE ON FUNCTION public.book_training_lane(date, time, smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_training_booking(uuid)            TO authenticated;
