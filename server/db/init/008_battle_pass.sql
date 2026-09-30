-- Battle pass progress, one row per player and season. The server owns the XP:
-- duels and the daily challenge add it directly, daily quests are claimed (capped per day).
-- claimed: {"free": [tiers], "premium": [tiers]}; weekly: {challenge_id: progress};
-- quests: {"YYYY-MM-DD": [quest ids]} (only recent days are kept).
CREATE TABLE IF NOT EXISTS pass_progress (
    player_id UUID NOT NULL REFERENCES players(id),
    season_id TEXT NOT NULL,
    xp INTEGER NOT NULL DEFAULT 0,
    premium BOOLEAN NOT NULL DEFAULT false,
    claimed JSONB NOT NULL DEFAULT '{"free": [], "premium": []}'::jsonb,
    weekly JSONB NOT NULL DEFAULT '{}'::jsonb,
    quests JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (player_id, season_id)
);
