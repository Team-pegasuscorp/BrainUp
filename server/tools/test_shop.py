"""Checks the server-side shop: coin payouts (duel, daily, quests, pass, leagues), purchases of
items and jokers, refusals, and worn items reset when not owned. Needs the stack running with
SHOP_DEMO_ITEMS=0 (`docker compose -p quizz-backend up -d`) and `pip install websockets`.
Usage: python tools/test_shop.py  (~1 minute: the bot joins after 20 s)"""
import asyncio
import json
import random
import subprocess
import urllib.error
import urllib.request
import uuid

import websockets

API = "http://localhost:8000"
WS = "ws://localhost:8000/ws/live"
failures = []


def check(label: str, ok: bool, detail="") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(label)


def call(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def psql(sql: str) -> str:
    out = subprocess.run(["docker", "exec", "quizz-backend-postgres-1", "psql", "-U", "quizz", "-d", "quizz",
                          "-tAc", sql], capture_output=True, text=True, check=True)
    return out.stdout.strip()


def in_api(code: str) -> str:
    """Runs Python inside the API container (to call shop.py on the real database)."""
    out = subprocess.run(["docker", "exec", "quizz-backend-api-1", "python", "-c", code],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def grant(player_id: str, amount: int) -> None:
    psql(f"INSERT INTO coin_ledger (player_id, amount, reason, ref) "
         f"VALUES ('{player_id}', {amount}, 'test', '{uuid.uuid4()}')")


async def duel(player_id: str) -> dict:
    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({"type": "join_queue", "player_id": player_id, "mode": "classic",
                                  "locale": "fr", "trophies": 100, "trophy_range": 100000}))
        while True:
            message = json.loads(await asyncio.wait_for(ws.recv(), timeout=120))
            if message["type"] == "question":
                await ws.send(json.dumps({"type": "answer", "index": message["index"],
                                          "selected_index": random.randrange(4)}))
            elif message["type"] == "reveal" and message.get("read_time"):
                await ws.send(json.dumps({"type": "ready", "index": message["index"]}))
            elif message["type"] == "match_over":
                return message


async def main() -> None:
    device = f"shop-{uuid.uuid4().hex[:10]}"
    _, player = call("POST", "/players", {"device_id": device, "display_name": "ShopTest"})
    pid = player["id"]
    status, state = call("GET", f"/shop?device_id={device}")
    check("new player starts with 0 coins and nothing bought", status == 200 and state["coins"] == 0
          and not any(i.startswith(("frame_ocean", "avatar_s1")) for i in state["owned"]), state.get("coins"))
    check("prices list shop items only", state["prices"].get("frame_ocean") == 300
          and "frame_neon" not in state["prices"] and "avatar_s1_1" not in state["prices"])
    check("demo avatars are not for sale here", "avatar_panther" not in state["prices"])
    check("unknown device is refused", call("GET", "/shop?device_id=nobody")[0] == 404)

    status, body = call("POST", "/shop/buy", {"device_id": device, "item_id": "frame_ocean"})
    check("cannot buy without coins", status == 402 and body["detail"] == "not_enough_coins", body)
    grant(pid, 1000)
    status, state = call("POST", "/shop/buy", {"device_id": device, "item_id": "frame_ocean"})
    check("purchase spends the price and owns the item",
          status == 200 and state["coins"] == 700 and "frame_ocean" in state["owned"], state.get("coins"))
    status, body = call("POST", "/shop/buy", {"device_id": device, "item_id": "frame_ocean"})
    check("an item is bought once", status == 409 and body["detail"] == "already_owned", body)
    for item_id, reason in (("avatar_s1_1", "not_for_sale"), ("avatar_panther", "not_for_sale"),
                            ("frame_neon", "not_for_sale"), ("nope", "unknown_item")):
        status, body = call("POST", "/shop/buy", {"device_id": device, "item_id": item_id})
        check(f"{item_id} refused ({reason})", body.get("detail") == reason, body)

    before = state["jokers"]["joker_5050"]
    status, state = call("POST", "/shop/joker", {"device_id": device, "item_id": "joker_5050"})
    check("joker purchase adds one to the stock", status == 200 and state["coins"] == 550
          and state["jokers"]["joker_5050"] == before + 1, state.get("jokers"))

    ## Two taps at once must not spend the same coins twice: 550 coins, three frames at 300.
    loop = asyncio.get_running_loop()
    results = await asyncio.gather(*(loop.run_in_executor(None, call, "POST", "/shop/buy",
                                     {"device_id": device, "item_id": item}) for item in
                                     ("frame_forest", "banner_ocean", "banner_forest")))
    bought = [r for r in results if r[0] == 200]
    _, state = call("GET", f"/shop?device_id={device}")
    check("concurrent purchases never overspend", len(bought) == 1 and state["coins"] == 250,
          f"{[r[0] for r in results]} coins {state['coins']}")

    _, worn = call("POST", "/players", {"device_id": device, "display_name": "ShopTest",
                                        "cosmetics": {"avatar": "lucas", "frame": "frame_ocean", "banner": "banner_gold"}})
    check("owned and starter items are kept, unowned ones reset",
          worn["cosmetics"] == {"avatar": "lucas", "frame": "frame_ocean", "banner": ""}, worn["cosmetics"])

    gains = [call("POST", "/pass/quest", {"device_id": device, "quest_id": f"q{i}"})[1].get("coins_gained") for i in range(4)]
    check("three quests pay coins per day, not four", gains == [20, 20, 20, 0], gains)

    status, daily = call("POST", "/daily-challenge/result", {"player_id": pid, "score": 0, "correct_count": 0,
                                                              "total_count": 7, "max_combo": 0})
    again = call("POST", "/daily-challenge/result", {"player_id": pid, "score": 0, "correct_count": 0,
                                                      "total_count": 7, "max_combo": 0})[1]
    check("daily challenge pays once", daily.get("coins_gained") == 30 and again.get("coins_gained") == 0,
          f"{daily.get('coins_gained')} / {again.get('coins_gained')}")

    psql(f"UPDATE pass_progress SET xp = 1700 WHERE player_id = '{pid}'")
    status, body = call("POST", "/pass/claim", {"device_id": device, "tier": 2, "track": "free"})
    amount = body.get("reward", {}).get("amount")
    check("a coin tier of the pass credits the wallet", status == 200 and body.get("coins_gained") == amount, body)

    _, state = call("GET", f"/shop?device_id={device}")
    coins_before_duel = state["coins"]
    over = await duel(pid)
    expected = 15 + (10 if over["won"] else 0)
    check("ranked duel pays coins", over.get("coins_gained") == expected + over.get("league_coins", -1)
          and over.get("coins") == coins_before_duel + over["coins_gained"], over.get("coins_gained"))

    league = in_api(
        "from db import engine\nimport shop\n"
        "with engine.begin() as c:\n"
        f"    a = shop.record_duel(c, '{pid}', 'league-a', True, 480, 1250)\n"
        f"    b = shop.record_duel(c, '{pid}', 'league-b', True, 1300, 1150)\n"
        f"    d = shop.record_duel(c, '{pid}', 'league-c', True, 1150, 1210)\n"
        "    print(a['league_coins'], b['league_coins'], d['league_coins'])")
    check("each league pays once, even after dropping and climbing back", league == "300 0 0", league)

    print(f"\n{len(failures)} FAILED: {failures}" if failures else "\nALL PASSED")


if __name__ == "__main__":
    asyncio.run(main())
