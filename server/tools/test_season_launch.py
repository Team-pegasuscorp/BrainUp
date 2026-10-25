"""Checks the launch season (« Saison 1 · Givre », id givre): it is the only season loaded
(Éveil sits in data/pass/drafts/), every pass item exists in the shop catalogue, the pacing targets of docs/ECONOMIE.md (game repo), and the
duel XP that drops after 5 duels a day, on the local database inside a rolled-back
transaction (nothing is written). Needs the local stack and `pip install sqlalchemy psycopg[binary]`.
Usage: DATABASE_URL=postgresql+psycopg://quizz:<password>@localhost:5432/quizz python tools/test_season_launch.py"""
import sys
import uuid
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import battle_pass  # noqa: E402
import shop  # noqa: E402
from db import engine  # noqa: E402
from sqlalchemy import text  # noqa: E402

failures = []


def check(label: str, ok: bool, detail="") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(label)


# --- Season data ---------------------------------------------------------------------

seasons = {season["id"]: season for season in battle_pass.SEASONS}
s2 = seasons.get("givre")
check("only the launch season is loaded", list(seasons) == ["givre"], list(seasons))
check("named Saison 1 · Givre", s2["name"]["fr"] == "Saison 1 · Givre")
check("running during the tests", battle_pass.current_season(s2["_start"])["id"] == "givre")
check("40 tiers of 1000 XP", len(s2["tiers"]) == 40 and s2["tier_xp"] == 1000)

items = [r["id"] for t in s2["tiers"] for r in (t["free"], t["premium"]) if r and r["type"] == "item"]
missing = [i for i in items if i not in shop.CATALOG]
check("every pass item is in the catalogue", not missing, str(missing))
check("pass items are not sold in the shop", all(shop.CATALOG[i].get("source") == "pass" for i in items if i in shop.CATALOG))
premium_items = [t["premium"]["id"] for t in s2["tiers"] if t["premium"]["type"] == "item"]
check("3 exclusive avatars in the premium track",
      sum(1 for i in premium_items if shop.CATALOG[i]["kind"] == "avatar") == 3)
premium_coins = sum(t["premium"].get("amount", 0) for t in s2["tiers"] if t["premium"]["type"] == "coins")
check("premium track pays ~1000 Neurones", premium_coins == 1000, str(premium_coins))
weekly_ids = [c["id"] for week in s2["weekly"] for c in week]
check("weekly ids unique", len(weekly_ids) == len(set(weekly_ids)))


def finish_day(duels: int, win: float, quests: int, weekly_share: float) -> float:
    rules = s2["xp"]
    per = rules["duel"] + rules["duel_win_bonus"] * win
    full = min(duels, rules["duels_full_per_day"])
    day = full * per + (duels - full) * per * rules["duel_extra_factor"] + rules["daily"] + quests * rules["quest"]
    weekly = sum(c["xp"] for week in s2["weekly"] for c in week) * weekly_share / 42
    return 40 * s2["tier_xp"] / (day + weekly)


regular = finish_day(4, 0.5, 3, 0.7)
grinder = finish_day(10, 0.55, 3, 1.0)
check("regular player finishes around week 5", 32 <= regular <= 38, f"day {regular:.0f}")
check("grinder finishes after week 3", grinder >= 21, f"day {grinder:.0f}")


# --- Duel XP after 5 duels a day (local DB, rolled back) -------------------------------

game_day = s2["_start"] + __import__("datetime").timedelta(days=1)
battle_pass.today = lambda: game_day  # inside the season, and "today" for the duel count
noon = datetime.combine(game_day, datetime.min.time(), tzinfo=timezone.utc).replace(hour=12)
yesterday_late = noon.replace(hour=0) - __import__("datetime").timedelta(hours=1)

with engine.connect() as conn:
    tx = conn.begin()
    try:
        player = str(conn.execute(
            text("INSERT INTO players (device_id, display_name) VALUES (:d, 'S2Test') RETURNING id"),
            {"d": f"test-s2-{uuid.uuid4()}"},
        ).scalar_one())

        def paid_duels(n: int) -> None:
            for _ in range(n):
                conn.execute(
                    text("INSERT INTO coin_ledger (player_id, amount, reason, ref, created_at) "
                         "VALUES (:p, 15, 'duel', :r, :t)"),
                    {"p": player, "r": str(uuid.uuid4()), "t": noon},
                )

        check("no duel yet today", battle_pass.duels_today(conn, player) == 0)
        paid_duels(4)
        xp = battle_pass.record_duel(conn, player, "classic", True, 0)
        check("5th duel of the day: full XP", xp == 160, str(xp))
        paid_duels(1)
        xp = battle_pass.record_duel(conn, player, "classic", True, 0)
        ## Also the 2nd win of the week: the weekly "win 2 duels" (+500) is never halved.
        check("6th duel of the day: half XP, weekly bonus whole", xp == 80 + 500, str(xp))
        xp = battle_pass.record_duel(conn, player, "classic", False, 0)
        check("6th+ duel lost: half of 100", xp == 50, str(xp))

        conn.execute(
            text("INSERT INTO coin_ledger (player_id, amount, reason, ref, created_at) "
                 "VALUES (:p, 15, 'duel', :r, :t)"),
            {"p": player, "r": str(uuid.uuid4()), "t": yesterday_late},
        )
        check("yesterday's duels are not counted", battle_pass.duels_today(conn, player) == 5)

        battle_pass.today = lambda: s2["_end"]
        check("no season after the end: no pass XP", battle_pass.record_duel(conn, player, "classic", True, 0) == 0)
    finally:
        tx.rollback()

print()
print("ALL PASS" if not failures else f"{len(failures)} FAILURE(S): {failures}")
sys.exit(1 if failures else 0)
