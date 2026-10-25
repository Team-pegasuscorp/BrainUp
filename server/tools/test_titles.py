"""Checks titles, the cosmetic shown under the pseudo: a title the player does not own is
reset on registration, a bought one is kept and shown to others (social search), season
titles are not for sale, and bots may wear a shop title. Needs the local stack
(`docker compose -p quizz-backend up -d`) with SHOP_DEMO_ITEMS=0.
Usage: python tools/test_titles.py  (a few seconds)"""
import json
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))

API = "http://localhost:8000"
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


device = f"test-titles-{uuid.uuid4()}"
name = "Tit" + uuid.uuid4().hex[:6]
look = {"avatar": "", "frame": "", "banner": "", "title": "title_curious"}

status, player = call("POST", "/players", {"device_id": device, "display_name": name, "cosmetics": look})
check("register with a title", status == 200, status)
check("title not owned -> reset", player.get("cosmetics", {}).get("title") == "", player.get("cosmetics"))

status, shop_state = call("GET", f"/shop?device_id={device}")
prices = shop_state.get("prices", {})
check("shop titles for sale", prices.get("title_curious") == 300 and prices.get("title_quiz_master") == 1500)
check("season titles not for sale", "title_givre_ice_cold" not in prices)

psql(f"INSERT INTO coin_ledger (player_id, amount, reason, ref) VALUES ('{player['id']}', 300, 'test', 'titles')")
status, bought = call("POST", "/shop/buy", {"device_id": device, "item_id": "title_curious"})
check("buy a title", status == 200 and "title_curious" in bought.get("owned", []), status)
status, bought = call("POST", "/shop/buy", {"device_id": device, "item_id": "title_givre_ice_cold"})
check("buying a season title refused", status != 200, status)

status, player = call("POST", "/players", {"device_id": device, "display_name": name, "cosmetics": look})
check("owned title kept", player.get("cosmetics", {}).get("title") == "title_curious", player.get("cosmetics"))

status, other = call("POST", "/players", {"device_id": f"test-titles-{uuid.uuid4()}", "display_name": "Tit" + uuid.uuid4().hex[:6]})
status, found = call("GET", f"/players/search?device_id={other['device_id']}&q={name}")
rows = found if isinstance(found, list) else found.get("results", found.get("players", []))
seen = [r for r in rows if r.get("display_name") == name or r.get("name") == name]
check("others see the title", bool(seen) and seen[0].get("cosmetics", {}).get("title") == "title_curious", str(rows)[:200])

old_client = {"avatar": "", "frame": "", "banner": ""}
status, player = call("POST", "/players", {"device_id": device, "display_name": name, "cosmetics": old_client})
check("older client without title accepted", status == 200)

import bots  # noqa: E402
titles = {bots.cosmetics_for(str(i)).get("title") for i in range(300)}
check("bots wear shop titles only", titles - {""} and all(t.startswith("title_") and "_s" not in t[5:8] for t in titles - {""}), titles)

psql("DELETE FROM coin_ledger WHERE player_id IN (SELECT id FROM players WHERE device_id LIKE 'test-titles-%')")
psql("DELETE FROM player_items WHERE player_id IN (SELECT id FROM players WHERE device_id LIKE 'test-titles-%')")
psql("DELETE FROM players WHERE device_id LIKE 'test-titles-%'")

print()
print("ALL PASS" if not failures else f"{len(failures)} FAILURE(S): {failures}")
sys.exit(1 if failures else 0)
