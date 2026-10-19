-- What the player wears (shop avatar / frame / banner ids), shown to other players.
-- Unowned catalogue items are reset to "" on registration (see shop.sanitize_cosmetics, 011).
ALTER TABLE players ADD COLUMN IF NOT EXISTS cosmetics JSONB NOT NULL DEFAULT '{}'::jsonb;
