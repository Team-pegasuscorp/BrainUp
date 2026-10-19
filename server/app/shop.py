## Shop economy: the server owns the coins, the items bought and the jokers bought.
## The wallet is coin_ledger (balance = sum of rows); every payout has a (reason, ref) key so
## a duel, a daily challenge, a quest, a league or a pass tier can never pay twice.
## Prices come from data/shop/catalog.json, a manual copy of the game's catalogue: re-copy it
## when items or prices change in the game repo (like data/questions).
import json
import os
import uuid
from datetime import date
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.engine import Connection

import battle_pass

CATALOG_PATH = Path(__file__).parent / "data" / "shop" / "catalog.json"
## Sells the placeholder "demo" avatars. Only for local development: never set it in production.
DEMO_ITEMS = os.environ.get("SHOP_DEMO_ITEMS") == "1"

## Payouts, sized so a common item (300) takes ~15-20 ranked duels.
DUEL_COINS = 15
DUEL_WIN_BONUS = 10
DAILY_COINS = 30
QUEST_COINS = 20
QUESTS_PER_DAY = 3
## One payout per league, the first time the player reaches it. Thresholds mirror the
## game's TrophyLeagues (scripts/profile/trophy_leagues.gd): change both together.
LEAGUES = (
    ("bronze", 0, 0),
    ("silver", 500, 100),
    ("gold", 1200, 200),
    ("platinum", 2000, 300),
    ("diamond", 2800, 500),
)
JOKER_PRICES = {"joker_5050": 150, "joker_time": 150}


class ShopError(Exception):
    def __init__(self, reason: str, status: int = 409):
        super().__init__(reason)
        self.reason = reason
        self.status = status


def _load_catalog() -> dict[str, dict]:
    with CATALOG_PATH.open(encoding="utf-8") as file:
        return {str(item["id"]): item for item in json.load(file)["items"]}


CATALOG = _load_catalog()


def _for_sale(item: dict) -> bool:
    return (int(item.get("price", 0)) > 0 and item.get("source", "shop") == "shop"
            and (DEMO_ITEMS or not item.get("demo")))


def credit(conn: Connection, player_id: str, amount: int, reason: str, ref: str) -> int:
    """Adds one ledger row; returns the amount, or 0 when (reason, ref) already paid."""
    if amount == 0:
        return 0
    row = conn.execute(
        text("""INSERT INTO coin_ledger (player_id, amount, reason, ref) VALUES (:p, :a, :r, :ref)
                ON CONFLICT (player_id, reason, ref) DO NOTHING RETURNING amount"""),
        {"p": player_id, "a": amount, "r": reason, "ref": ref[:120]},
    ).first()
    return int(row[0]) if row else 0


def balance(conn: Connection, player_id: str) -> int:
    return int(conn.execute(
        text("SELECT COALESCE(SUM(amount), 0) FROM coin_ledger WHERE player_id = :p"), {"p": player_id}
    ).scalar_one())


def owned_items(conn: Connection, player_id: str) -> set[str]:
    bought = conn.execute(
        text("SELECT item_id FROM player_items WHERE player_id = :p"), {"p": player_id}
    ).scalars().all()
    return set(bought) | battle_pass.pass_items(conn, player_id)


def is_owned(item_id: str, owned: set[str]) -> bool:
    """Free catalogue items count as owned; ids outside the catalogue (starter avatars) too."""
    item = CATALOG.get(item_id)
    if item is None:
        return True
    if item.get("source", "shop") == "pass":
        return item_id in owned
    return int(item.get("price", 0)) <= 0 or item_id in owned


def _lock_player(conn: Connection, player_id: str) -> None:
    """Serializes purchases of one player so two taps cannot spend the same coins twice."""
    conn.execute(text("SELECT 1 FROM players WHERE id = :p FOR UPDATE"), {"p": player_id})


def buy_item(conn: Connection, player_id: str, item_id: str) -> None:
    item = CATALOG.get(item_id)
    if item is None:
        raise ShopError("unknown_item", 404)
    if not _for_sale(item):
        raise ShopError("not_for_sale")
    _lock_player(conn, player_id)
    if item_id in owned_items(conn, player_id):
        raise ShopError("already_owned")
    price = int(item["price"])
    if balance(conn, player_id) < price:
        raise ShopError("not_enough_coins", 402)
    credit(conn, player_id, -price, "buy", item_id)
    conn.execute(
        text("INSERT INTO player_items (player_id, item_id, price) VALUES (:p, :i, :price)"),
        {"p": player_id, "i": item_id, "price": price},
    )


def buy_joker(conn: Connection, player_id: str, joker_id: str) -> None:
    price = JOKER_PRICES.get(joker_id)
    if price is None:
        raise ShopError("unknown_item", 404)
    _lock_player(conn, player_id)
    if balance(conn, player_id) < price:
        raise ShopError("not_enough_coins", 402)
    ## Jokers can be bought again and again: each purchase gets its own ref.
    credit(conn, player_id, -price, "buy_joker", f"{joker_id}:{uuid.uuid4()}")
    conn.execute(
        text("""UPDATE players SET jokers_bought = jsonb_set(jokers_bought, ARRAY[CAST(:j AS text)],
                to_jsonb(COALESCE((jokers_bought->>:j)::int, 0) + 1)) WHERE id = :p"""),
        {"j": joker_id, "p": player_id},
    )


def league_index(trophies: int) -> int:
    index = 0
    for i, (_, minimum, _) in enumerate(LEAGUES):
        if trophies >= minimum:
            index = i
    return index


def record_duel(conn: Connection, player_id: str, match_id: str, won: bool,
                trophies_before: int, trophies_after: int) -> dict:
    """Coins for a finished ranked duel, plus the bonus of every league reached for the first time."""
    duel = credit(conn, player_id, DUEL_COINS + (DUEL_WIN_BONUS if won else 0), "duel", match_id)
    league = 0
    for i in range(league_index(trophies_before) + 1, league_index(trophies_after) + 1):
        league_id, _, reward = LEAGUES[i]
        league += credit(conn, player_id, reward, "league", league_id)
    return {"coins_gained": duel + league, "league_coins": league}


def record_daily(conn: Connection, player_id: str, day: date) -> int:
    return credit(conn, player_id, DAILY_COINS, "daily", day.isoformat())


def record_quest(conn: Connection, player_id: str, quest_id: str, claimed_day: str | None) -> int:
    """Same phone-day rule as the pass quests (battle_pass.quest_day), capped per day."""
    day = battle_pass.quest_day(claimed_day)
    paid_today = conn.execute(
        text("SELECT COUNT(*) FROM coin_ledger WHERE player_id = :p AND reason = 'quest' AND ref LIKE :d"),
        {"p": player_id, "d": day + ":%"},
    ).scalar_one()
    if paid_today >= QUESTS_PER_DAY:
        return 0
    return credit(conn, player_id, QUEST_COINS, "quest", f"{day}:{quest_id[:40]}")


def record_pass_reward(conn: Connection, player_id: str, season_id: str, track: str, tier: int,
                       reward: dict) -> int:
    if reward.get("type") != "coins":
        return 0
    return credit(conn, player_id, max(int(reward.get("amount", 0)), 0), "pass", f"{season_id}:{track}:{tier}")


def sanitize_cosmetics(conn: Connection, player_id: str | None, cosmetics: dict) -> dict:
    """Resets worn catalogue items the player does not own to "" (the default look)."""
    owned = owned_items(conn, player_id) if player_id else set()
    return {slot: item_id if is_owned(str(item_id), owned) else "" for slot, item_id in cosmetics.items()}


def state(conn: Connection, player_id: str) -> dict:
    """Everything the shop screen needs. `prices` lists what can be bought right now.
    `trophies` is the server's count once it tracks this player (None before the first ranked join)."""
    trophies, seeded = conn.execute(
        text("SELECT trophies, trophies_seeded FROM players WHERE id = :p"), {"p": player_id}
    ).one()
    return {
        "coins": balance(conn, player_id),
        "trophies": trophies if seeded else None,
        "owned": sorted(owned_items(conn, player_id)),
        "prices": {item_id: int(item["price"]) for item_id, item in CATALOG.items() if _for_sale(item)},
        "jokers": battle_pass.jokers_available(conn, player_id),
        "joker_prices": JOKER_PRICES,
        "rules": {
            "duel": DUEL_COINS, "duel_win_bonus": DUEL_WIN_BONUS, "daily": DAILY_COINS,
            "quest": QUEST_COINS, "quests_per_day": QUESTS_PER_DAY,
            "leagues": [{"id": league_id, "min_trophies": minimum, "coins": reward}
                        for league_id, minimum, reward in LEAGUES[1:]],
        },
    }
