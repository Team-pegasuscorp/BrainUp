CREATE TABLE IF NOT EXISTS challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    category TEXT NOT NULL,
    challenger_id UUID NOT NULL REFERENCES players(id),
    opponent_id UUID REFERENCES players(id),
    challenger_score INTEGER,
    challenger_correct_count INTEGER,
    opponent_score INTEGER,
    opponent_correct_count INTEGER,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_challenges_code ON challenges(code);
