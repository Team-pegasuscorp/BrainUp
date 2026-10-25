"""Checks the daily shop selection (app/shop.py rotation): 2 common, 2 rare, 1 epic and
1 legendary a day, stable for a day, every item dealt within its cycle, few repeats from
one day to the next; then on the local API started with SHOP_ROTATION=1: `prices` only
lists the selection and buying outside it is refused.
Usage: SHOP_ROTATION=1 docker compose -p quizz-backend up -d --build api
       python tools/test_rotation.py   (needs sqlalchemy: shop.py imports the db layer)"""
import json
import math
import os
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from collections import Counter
from datetime import date, timedelta
from pathlib import Path

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg://unused@localhost/unused")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import shop  # noqa: E402

API = "http://localhost:8000"
failures = []


def check(label: str, ok: bool, detail="") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(label)


# --- Selection ---------------------------------------------------------------------

day = date(2026, 11, 9)
today = shop.rotation(day)
picked = today["featured"] + today["items"]
rarities = Counter(shop.CATALOG[i]["rarity"] for i in picked)
check("6 items a day", len(picked) == 6, picked)
check("2 common, 2 rare, 1 epic, 1 legendary",
      rarities == Counter({"common": 2, "rare": 2, "epic": 1, "legendary": 1}), dict(rarities))
check("featured = legendary + epic",
      [shop.CATALOG[i]["rarity"] for i in today["featured"]] == ["legendary", "epic"])
check("only shop items", all(shop._for_sale(shop.CATALOG[i]) for i in picked))
check("no duplicate in a day", len(set(picked)) == 6)
check("stable for the day", shop.rotation(day) == today)
check("ends at next 00:00 UTC", today["ends_at"] == "2026-11-10T00:00:00+00:00", today["ends_at"])

for rarity, slots in shop.ROTATION_SLOTS:
    pool = {i for i, item in shop.CATALOG.items() if shop._for_sale(item) and item["rarity"] == rarity}
    cycle = math.ceil(len(pool) / slots)
    start = shop.ROTATION_EPOCH + timedelta(days=cycle * 40)  # a cycle boundary
    seen = set()
    for d in range(cycle):
        r = shop.rotation(start + timedelta(days=d))
        seen |= {i for i in r["featured"] + r["items"] if shop.CATALOG[i]["rarity"] == rarity}
    check(f"{rarity}: all {len(pool)} items within a {cycle}-day cycle", seen == pool, len(seen))

repeats = 0
for d in range(120):
    a = shop.rotation(day + timedelta(days=d))
    b = shop.rotation(day + timedelta(days=d + 1))
    repeats += len(set(a["featured"] + a["items"]) & set(b["featured"] + b["items"]))
check("few repeats day to day", repeats <= 30, f"{repeats} over 120 days")


# --- Local API with SHOP_ROTATION=1 -----------------------------------------------------

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


device = f"test-rotation-{uuid.uuid4()}"
status, player = call("POST", "/players", {"device_id": device, "display_name": "Rot" + uuid.uuid4().hex[:6]})
status, state = call("GET", f"/shop?device_id={device}")
live = state.get("rotation")
if not live:
    check("API runs with SHOP_ROTATION=1", False, "rotation is null: restart the api with SHOP_ROTATION=1")
else:
    on_sale = set(live["featured"] + live["items"])
    check("prices = today's selection only", set(state["prices"]) == on_sale, sorted(state["prices"]))
    outside = next(i for i, item in shop.CATALOG.items() if shop._for_sale(item) and i not in on_sale)
    inside = live["items"][0]
    psql(f"INSERT INTO coin_ledger (player_id, amount, reason, ref) VALUES ('{player['id']}', 5000, 'test', 'rotation')")
    status, body = call("POST", "/shop/buy", {"device_id": device, "item_id": outside})
    check("buying outside the selection refused", status == 409 and body.get("detail") == "not_in_rotation", (status, body))
    status, body = call("POST", "/shop/buy", {"device_id": device, "item_id": inside})
    check("buying from the selection works", status == 200 and inside in body.get("owned", []), status)
    status, body = call("POST", "/shop/joker", {"device_id": device, "item_id": "joker_5050"})
    check("jokers always on sale", status == 200, status)

psql("DELETE FROM coin_ledger WHERE player_id IN (SELECT id FROM players WHERE device_id LIKE 'test-rotation-%')")
psql("DELETE FROM player_items WHERE player_id IN (SELECT id FROM players WHERE device_id LIKE 'test-rotation-%')")
psql("DELETE FROM players WHERE device_id LIKE 'test-rotation-%'")

print()
print("ALL PASS" if not failures else f"{len(failures)} FAILURE(S): {failures}")
sys.exit(1 if failures else 0)
