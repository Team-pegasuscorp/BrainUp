-- What the player wears (shop avatar / frame / banner ids), shown to other players.
-- Ids are only format-checked: purchases are still client-side for now.
ALTER TABLE players ADD COLUMN IF NOT EXISTS cosmetics JSONB NOT NULL DEFAULT '{}'::jsonb;
