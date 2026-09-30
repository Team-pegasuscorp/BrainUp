## Battle pass: seasons read from data/pass/season_*.json, progress in pass_progress.
## The server owns the XP: duels and the daily challenge add it directly, daily quests are
## claimed by the client but capped per day, weekly challenges are counted from duel results.
import json
import os
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.engine import Connection

PASS_DIR = Path(__file__).parent / "data" / "pass"
## Unlocks premium without a store receipt. Only for local development: never set it in production.
DEV_UNLOCK = os.environ.get("PASS_DEV_UNLOCK") == "1"
QUEST_DAYS_KEPT = 3


def _load_seasons() -> list[dict]:
    seasons = []
    for path in sorted(PASS_DIR.glob("season_*.json")):
        with path.open(encoding="utf-8") as file:
            season = json.load(file)
        start = date.fromisoformat(season["start"])
        season["_start"] = start
        season["_end"] = start + timedelta(weeks=int(season["weeks"]))
        seasons.append(season)
    return seasons


SEASONS = _load_seasons()


def today() -> date:
    return datetime.now(timezone.utc).date()


def current_season(day: date | None = None) -> dict | None:
    day = day or today()
    for season in SEASONS:
        if season["_start"] <= day < season["_end"]:
            return season
    return None


def week_of(season: dict, day: date | None = None) -> int:
    """1-based week inside the season."""
    day = day or today()
    return min(int(season["weeks"]), (day - season["_start"]).days // 7 + 1)


def tier_for(season: dict, xp: int) -> int:
    return min(len(season["tiers"]), xp // int(season["tier_xp"]))


def _row(conn: Connection, player_id: str, season: dict, lock: bool = True) -> dict:
    conn.execute(
        text("INSERT INTO pass_progress (player_id, season_id) VALUES (:p, :s) ON CONFLICT DO NOTHING"),
        {"p": player_id, "s": season["id"]},
    )
    return dict(conn.execute(
        text("SELECT xp, premium, claimed, weekly, quests FROM pass_progress "
             "WHERE player_id = :p AND season_id = :s" + (" FOR UPDATE" if lock else "")),
        {"p": player_id, "s": season["id"]},
    ).mappings().one())


def _save(conn: Connection, player_id: str, season: dict, row: dict) -> None:
    conn.execute(
        text("""UPDATE pass_progress SET xp = :xp, premium = :premium, claimed = CAST(:claimed AS jsonb),
                weekly = CAST(:weekly AS jsonb), quests = CAST(:quests AS jsonb), updated_at = now()
                WHERE player_id = :p AND season_id = :s"""),
        {
            "xp": row["xp"], "premium": row["premium"],
            "claimed": json.dumps(row["claimed"]), "weekly": json.dumps(row["weekly"]),
            "quests": json.dumps(row["quests"]), "p": player_id, "s": season["id"],
        },
    )


def _advance_weekly(season: dict, row: dict, event: dict) -> int:
    """Counts one event towards this week's challenges; returns XP of newly finished ones."""
    gained = 0
    for challenge in season["weekly"][week_of(season) - 1]:
        kind = challenge["type"]
        step = 0
        if kind == "duels_played" and event.get("duel"):
            step = 1
        elif kind == "duels_won" and event.get("won"):
            step = 1
        elif kind == "mode_played" and event.get("duel") and event.get("mode") == challenge.get("mode"):
            step = 1
        elif kind == "mode_won" and event.get("won") and event.get("mode") == challenge.get("mode"):
            step = 1
        elif kind == "correct_answers":
            step = int(event.get("correct", 0))
        elif kind == "daily_played" and event.get("daily"):
            step = 1
        if step <= 0:
            continue
        before = int(row["weekly"].get(challenge["id"], 0))
        after = min(before + step, int(challenge["target"]))
        row["weekly"][challenge["id"]] = after
        if before < challenge["target"] <= after:
            gained += int(challenge["xp"])
    return gained


def record_duel(conn: Connection, player_id: str, mode: str, won: bool, correct: int) -> int:
    """XP for a finished ranked duel (+ weekly challenges). Returns the XP gained."""
    season = current_season()
    if season is None:
        return 0
    row = _row(conn, player_id, season)
    rules = season["xp"]
    gained = int(rules["duel"]) + (int(rules["duel_win_bonus"]) if won else 0)
    gained += _advance_weekly(season, row, {"duel": True, "won": won, "mode": mode, "correct": correct})
    row["xp"] += gained
    _save(conn, player_id, season, row)
    return gained


def record_daily(conn: Connection, player_id: str) -> int:
    """XP for today's shared challenge (call once, on the first result of the day)."""
    season = current_season()
    if season is None:
        return 0
    row = _row(conn, player_id, season)
    gained = int(season["xp"]["daily"]) + _advance_weekly(season, row, {"daily": True})
    row["xp"] += gained
    _save(conn, player_id, season, row)
    return gained


def claim_quest(conn: Connection, player_id: str, quest_id: str) -> int:
    """Daily quests live on the phone: the server only caps how many pay per UTC day."""
    season = current_season()
    if season is None:
        return 0
    row = _row(conn, player_id, season)
    day = today().isoformat()
    claimed_today = list(row["quests"].get(day, []))
    if quest_id in claimed_today or len(claimed_today) >= int(season["xp"]["quests_per_day"]):
        return 0
    claimed_today.append(quest_id[:40])
    oldest = (today() - timedelta(days=QUEST_DAYS_KEPT - 1)).isoformat()
    row["quests"] = {d: ids for d, ids in row["quests"].items() if d >= oldest}
    row["quests"][day] = claimed_today
    gained = int(season["xp"]["quest"])
    row["xp"] += gained
    _save(conn, player_id, season, row)
    return gained


def claim_reward(conn: Connection, player_id: str, tier: int, track: str) -> dict:
    """Marks a reached tier as claimed and returns its reward for the client's inventory.
    Raises ValueError with a short reason when the claim is not allowed."""
    season = current_season()
    if season is None:
        raise ValueError("no_season")
    if track not in ("free", "premium") or not 1 <= tier <= len(season["tiers"]):
        raise ValueError("bad_tier")
    row = _row(conn, player_id, season)
    reward = season["tiers"][tier - 1].get(track)
    if not reward:
        raise ValueError("no_reward")
    if tier > tier_for(season, row["xp"]):
        raise ValueError("not_reached")
    if track == "premium" and not row["premium"]:
        raise ValueError("not_premium")
    claimed = row["claimed"].setdefault(track, [])
    if tier in claimed:
        raise ValueError("already_claimed")
    claimed.append(tier)
    _save(conn, player_id, season, row)
    return reward


def unlock_premium(conn: Connection, player_id: str, receipt: str) -> bool:
    """TODO(billing): verify a Google Play purchase token with the Play Developer API.
    Until then only a development server (PASS_DEV_UNLOCK=1) accepts the "dev" receipt."""
    season = current_season()
    if season is None or not (DEV_UNLOCK and receipt == "dev"):
        return False
    row = _row(conn, player_id, season)
    row["premium"] = True
    _save(conn, player_id, season, row)
    return True


def state(conn: Connection, player_id: str) -> dict:
    """Everything the pass screen needs: season, tiers, progress, this week's challenges."""
    season = current_season()
    if season is None:
        return {"active": False}
    row = _row(conn, player_id, season, lock=False)
    week = week_of(season)
    return {
        "active": True,
        "season_id": season["id"],
        "name": season["name"],
        "ends_at": season["_end"].isoformat(),
        "days_left": (season["_end"] - today()).days,
        "week": week,
        "tier_xp": season["tier_xp"],
        "xp": row["xp"],
        "tier": tier_for(season, row["xp"]),
        "premium": row["premium"],
        "claimed": row["claimed"],
        "tiers": season["tiers"],
        "xp_rules": season["xp"],
        "weekly": [
            {**challenge, "progress": int(row["weekly"].get(challenge["id"], 0))}
            for challenge in season["weekly"][week - 1]
        ],
        "quests_today": len(row["quests"].get(today().isoformat(), [])),
        "dev_unlock": DEV_UNLOCK,
    }
