-- Versus win / loss streaks, for the trophy streak bonuses (same rules as the client's TrophySystem).
ALTER TABLE players ADD COLUMN IF NOT EXISTS versus_win_streak INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS versus_loss_streak INTEGER NOT NULL DEFAULT 0;
