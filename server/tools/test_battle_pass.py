"""Checks the battle pass: duel XP, weekly challenges, capped quests, reward claims and the
development premium unlock. Needs the stack running with PASS_DEV_UNLOCK=1
(`docker compose -p quizz-backend up -d`) and `pip install websockets`.
Usage: python tools/test_battle_pass.py  (~1 minute: the bot joins after 20 s)"""
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


async def duel(player_id: str) -> dict:
    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({"type": "join_queue", "player_id": player_id, "mode": "classic",
                                  "locale": "fr", "trophies": 500, "trophy_range": 100000}))
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
    device = f"pass-{uuid.uuid4().hex[:10]}"
    _, player = call("POST", "/players", {"device_id": device, "display_name": "PassTest"})
    status, state = call("GET", f"/pass?device_id={device}")
    check("pass state for a new player", status == 200 and state.get("active") and state["xp"] == 0, state.get("xp"))
    check("season has 40 tiers", len(state.get("tiers", [])) == 40)
    check("dev unlock enabled on this server", state.get("dev_unlock") is True)
    check("unknown device is refused", call("GET", "/pass?device_id=nobody")[0] == 404)

    over = await duel(player["id"])
    status, state = call("GET", f"/pass?device_id={device}")
    expected = 100 + (60 if over["won"] else 0)
    check("duel pays pass XP", over.get("pass_xp", 0) >= expected and state["xp"] == over["pass_xp"],
          f"{over.get('pass_xp')} / state {state['xp']}")
    played = next(c for c in state["weekly"] if c["type"] == "duels_played") if state["week"] == 1 else None
    if played:
        check("weekly challenge counts the duel", played["progress"] == 1, played)

    gains = [call("POST", "/pass/quest", {"device_id": device, "quest_id": f"q{i}"})[1]["pass_xp"] for i in range(4)]
    check("three quests pay per day, not four", gains == [100, 100, 100, 0], gains)
    check("the same quest never pays twice", call("POST", "/pass/quest", {"device_id": device, "quest_id": "q0"})[1]["pass_xp"] == 0)

    status, body = call("POST", "/pass/claim", {"device_id": device, "tier": 10, "track": "free"})
    check("a tier not reached cannot be claimed", status == 409 and body["detail"] == "not_reached", body)
    psql(f"UPDATE pass_progress SET xp = 1700 WHERE player_id = '{player['id']}'")
    status, body = call("POST", "/pass/claim", {"device_id": device, "tier": 2, "track": "free"})
    check("a reached tier gives its reward", status == 200 and body["reward"]["type"] == "coins", body)
    status, body = call("POST", "/pass/claim", {"device_id": device, "tier": 2, "track": "free"})
    check("a reward is claimed only once", status == 409 and body["detail"] == "already_claimed", body)
    status, body = call("POST", "/pass/claim", {"device_id": device, "tier": 1, "track": "premium"})
    check("premium rewards need premium", status == 409 and body["detail"] == "not_premium", body)
    check("a fake receipt is refused", call("POST", "/pass/premium", {"device_id": device, "receipt": "fake"})[0] == 402)
    status, state = call("POST", "/pass/premium", {"device_id": device, "receipt": "dev"})
    check("dev receipt unlocks premium", status == 200 and state["premium"] is True)
    status, body = call("POST", "/pass/claim", {"device_id": device, "tier": 1, "track": "premium"})
    check("premium reward claimed after unlock", status == 200 and body["reward"]["type"] == "item", body)

    print(f"\n{len(failures)} FAILED: {failures}" if failures else "\nALL PASSED")


if __name__ == "__main__":
    asyncio.run(main())
