## Filler players for the trophy leaderboard, so the board looks alive at launch.
## Like live bots they are hidden from the client: same fields as real players.
## They live in their own table and drift a little every day.
import random
from datetime import date

from sqlalchemy import text
from sqlalchemy.engine import Connection

import bots

COUNT = 80
MAX_TROPHIES = 3300
## Daily move per bot: slightly upward on average, like an active player.
DAILY_DRIFT = (-40, 60)


def _names(count: int) -> list[str]:
    rng = random.Random()
    pool = list(bots.PSEUDOS)
    rng.shuffle(pool)
    names = []
    while len(names) < count:
        base = pool[len(names) % len(pool)]
        ## Second pass through the pool gets gamer-style suffixes to avoid duplicates.
        if len(names) < len(pool):
            names.append(base)
        elif base[-1].isdigit():
            names.append(f"{base}_{rng.choice(['fr', 'x', 'pro', 'qc'])}")
        else:
            names.append(f"{base}{rng.randint(2, 99)}")
    return names


def ensure(conn: Connection) -> None:
    """Seeds the bots on first use, then applies the daily drift once per day."""
    ## Serialises concurrent first requests so the bots are seeded / drifted only once.
    conn.execute(text("SELECT pg_advisory_xact_lock(4242)"))
    if conn.execute(text("SELECT count(*) FROM leaderboard_bots")).scalar_one() == 0:
        for name in _names(COUNT):
            ## Skewed low: many beginners, a few strong players at the top.
            trophies = int(MAX_TROPHIES * random.random() ** 1.8)
            conn.execute(
                text("INSERT INTO leaderboard_bots (display_name, trophies) VALUES (:n, :t)"),
                {"n": name, "t": trophies},
            )
        return

    today = date.today()
    stale = conn.execute(
        text("SELECT id, trophies, updated_on FROM leaderboard_bots WHERE updated_on < :today FOR UPDATE"),
        {"today": today},
    ).all()
    for bot_id, trophies, updated_on in stale:
        for _ in range(min((today - updated_on).days, 30)):
            trophies = max(0, min(MAX_TROPHIES + 500, trophies + random.randint(*DAILY_DRIFT)))
        conn.execute(
            text("UPDATE leaderboard_bots SET trophies = :t, updated_on = :today WHERE id = :id"),
            {"t": trophies, "today": today, "id": bot_id},
        )
