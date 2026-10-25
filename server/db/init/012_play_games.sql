-- Google Play Games account link: one Google account per player row.
ALTER TABLE players ADD COLUMN IF NOT EXISTS play_games_player_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS players_play_games_player_id_key
    ON players (play_games_player_id)
    WHERE play_games_player_id IS NOT NULL;
