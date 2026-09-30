-- Server-trusted trophies for ranked live matchmaking.
-- trophies_seeded: the first ranked join may import the client's value (capped), once.
-- cheat_flags: count of rejected / implausible inputs, for manual review.
ALTER TABLE players ADD COLUMN IF NOT EXISTS trophies INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS trophies_seeded BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE players ADD COLUMN IF NOT EXISTS cheat_flags INTEGER NOT NULL DEFAULT 0;
