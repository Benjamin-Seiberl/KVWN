-- Add is_friendly flag for Freundschaftsspiele.
-- XOR-style guard: a match is at most ONE of {tournament, landesbewerb, friendly}.
-- League matches have all three flags = false (and a league_id set).

ALTER TABLE matches ADD COLUMN IF NOT EXISTS is_friendly BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE matches DROP CONSTRAINT IF EXISTS matches_type_xor;
ALTER TABLE matches ADD CONSTRAINT matches_type_xor CHECK (
  (is_tournament::int + is_landesbewerb::int + is_friendly::int) <= 1
);
