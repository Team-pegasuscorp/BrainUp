-- Friends, friend requests and friend duel invites, plus presence and joker usage.
-- friendships holds both directions (a,b) and (b,a) so "my friends" is one index scan.
-- jokers_used: {joker_id: count}; the stock is (jokers won in claimed pass tiers) - used.
ALTER TABLE players ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE players ADD COLUMN IF NOT EXISTS jokers_used JSONB NOT NULL DEFAULT '{}'::jsonb;
-- Profile level as reported by the phone (display only, shown to friends).
ALTER TABLE players ADD COLUMN IF NOT EXISTS level INTEGER NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_players_name_lower ON players (lower(display_name) text_pattern_ops);

CREATE TABLE IF NOT EXISTS friendships (
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    friend_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (player_id, friend_id)
);

CREATE TABLE IF NOT EXISTS friend_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    to_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (from_id, to_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_id);

-- status: pending -> accepted -> played, or declined / cancelled / expired.
CREATE TABLE IF NOT EXISTS friend_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    to_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    mode TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_friend_challenges_to ON friend_challenges(to_id, status);
CREATE INDEX IF NOT EXISTS idx_friend_challenges_from ON friend_challenges(from_id, status);
