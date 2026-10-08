-- "In a game" flag sent with the /social poll: an invite cannot be accepted while its
-- challenger is busy (the duel would open nowhere). Expires on its own if polls stop.
ALTER TABLE players ADD COLUMN IF NOT EXISTS busy_until TIMESTAMPTZ;
