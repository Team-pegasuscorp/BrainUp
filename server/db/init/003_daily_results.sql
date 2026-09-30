-- One result per player per day for the shared daily challenge (first play counts).
CREATE TABLE IF NOT EXISTS daily_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id),
    day DATE NOT NULL,
    category TEXT NOT NULL,
    score INTEGER NOT NULL,
    correct_count INTEGER NOT NULL,
    total_count INTEGER NOT NULL,
    max_combo INTEGER NOT NULL,
    played_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (player_id, day)
);

CREATE INDEX IF NOT EXISTS idx_daily_results_day_score ON daily_results(day, score DESC);
