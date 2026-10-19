-- Shop economy, owned by the server. coin_ledger is the wallet: the balance is the sum of
-- its rows, and (reason, ref) makes every payout idempotent (a duel, a day, a quest, a
-- league or a pass tier pays once). Purchases are negative rows.
-- player_items: catalogue items bought with coins (pass items come from claimed tiers).
-- jokers_bought: {joker_id: count}, added to the jokers won in the pass.
CREATE TABLE IF NOT EXISTS coin_ledger (
    id BIGSERIAL PRIMARY KEY,
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,
    reason TEXT NOT NULL,
    ref TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (player_id, reason, ref)
);

CREATE TABLE IF NOT EXISTS player_items (
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    item_id TEXT NOT NULL,
    price INTEGER NOT NULL,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (player_id, item_id)
);

ALTER TABLE players ADD COLUMN IF NOT EXISTS jokers_bought JSONB NOT NULL DEFAULT '{}'::jsonb;
