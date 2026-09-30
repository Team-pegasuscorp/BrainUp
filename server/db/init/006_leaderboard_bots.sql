-- Filler players for the trophy leaderboard while the player base is small.
-- Kept apart from players: never matched, never logged in, invisible to the client as bots.
CREATE TABLE IF NOT EXISTS leaderboard_bots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name TEXT NOT NULL,
    trophies INTEGER NOT NULL,
    updated_on DATE NOT NULL DEFAULT CURRENT_DATE
);
