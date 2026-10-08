"""Friends end to end: search, request, accept, friend list with presence, a duel invite,
the private live room (no bot, no trophies) and both jokers. Needs the stack running
(docker compose up), migration 009 applied, and `pip install websockets`.
Usage: python tools/test_friends.py  (~1 minute)"""
import asyncio
import json
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


def call(method: str, path: str, body: dict | None = None) -> tuple[int, object]:
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def register(name: str) -> dict:
    device = f"friends-{uuid.uuid4().hex[:10]}"
    _status, player = call("POST", "/players", {"device_id": device, "display_name": name})
    return {"device": device, "id": player["id"], "name": name}


def psql(sql: str) -> None:
    subprocess.run(
        ["docker", "compose", "-p", "quizz-backend", "exec", "-T", "postgres", "sh", "-c",
         'psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"'],
        input=sql.encode(), check=True,
    )


def give_jokers(player_id: str) -> None:
    """Pretend tier 5 of season 1 was claimed on both tracks: 1x 50/50 + 2x time."""
    psql(f"""INSERT INTO pass_progress (player_id, season_id, xp, premium, claimed)
             VALUES ('{player_id}', 's1', 4000, true, '{{"free": [5], "premium": [5]}}')
             ON CONFLICT (player_id, season_id) DO UPDATE SET claimed = EXCLUDED.claimed;""")


async def play_friend(player: dict, challenge_id: str, use_jokers: bool) -> dict:
    seen = {"found": None, "jokers": [], "over": None, "opponent_jokers": 0, "bonus": 0.0}
    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({"type": "join_friend", "player_id": player["id"],
                                  "challenge_id": challenge_id, "locale": "fr"}))
        while True:
            message = json.loads(await asyncio.wait_for(ws.recv(), timeout=120))
            kind = message["type"]
            if kind == "match_found":
                seen["found"] = message
                choices = (message.get("draft") or {}).get("choices", [])
                if choices:
                    await ws.send(json.dumps({"type": "draft_vote", "category": choices[0]}))
            elif kind == "question":
                if use_jokers and message["index"] == 0:
                    await ws.send(json.dumps({"type": "joker", "joker": "joker_5050", "index": 0}))
                    await ws.send(json.dumps({"type": "joker", "joker": "joker_time", "index": 0}))
                if use_jokers and message["index"] == 1:
                    ## Second 50/50 in the same match: refused (once per kind and match).
                    await ws.send(json.dumps({"type": "joker", "joker": "joker_5050", "index": 1}))
                await asyncio.sleep(0.6)
                await ws.send(json.dumps({"type": "answer", "index": message["index"], "selected_index": 0}))
            elif kind == "joker_result":
                seen["jokers"].append(message)
            elif kind == "opponent_joker":
                seen["opponent_jokers"] += 1
            elif kind == "reveal":
                seen["bonus"] = max(seen["bonus"], float(message["your_result"].get("bonus", 0)))
                if message.get("read_time", 0) > 0:
                    await ws.send(json.dumps({"type": "ready", "index": message["index"]}))
            elif kind in ("match_over", "match_aborted"):
                seen["over"] = message
                return seen


async def main() -> None:
    suffix = uuid.uuid4().hex[:5]
    alice = register(f"Alice{suffix}")
    bob = register(f"Bob{suffix}")

    status, found = call("GET", f"/players/search?device_id={alice['device']}&q=bob{suffix}")
    check("search finds Bob by prefix (case-insensitive)", status == 200 and [p["id"] for p in found] == [bob["id"]], found)

    status, sent = call("POST", "/friends/requests", {"device_id": alice["device"], "player_id": bob["id"]})
    check("request sent", status == 200 and sent["status"] == "sent", sent)
    _s, bob_view = call("GET", f"/social?device_id={bob['device']}")
    incoming = bob_view["requests_in"]
    check("Bob sees the request", len(incoming) == 1 and incoming[0]["player"]["id"] == alice["id"], incoming)

    status, _r = call("POST", f"/friends/challenges", {"device_id": alice["device"], "friend_id": bob["id"], "mode": "classic"})
    check("no duel invite before being friends", status == 403, status)

    status, _r = call("POST", f"/friends/requests/{incoming[0]['id']}/accept", {"device_id": bob["device"]})
    check("Bob accepts", status == 200, status)
    _s, alice_view = call("GET", f"/social?device_id={alice['device']}")
    friend = alice_view["friends"][0] if alice_view["friends"] else {}
    check("Alice lists Bob, online", friend.get("id") == bob["id"] and friend.get("online") is True, friend)
    status, _r = call("POST", "/friends/requests", {"device_id": alice["device"], "player_id": bob["id"]})
    check("second request refused (already friends)", status == 409, status)

    status, invite = call("POST", "/friends/challenges", {"device_id": alice["device"], "friend_id": bob["id"], "mode": "classic"})
    check("Alice invites Bob (classic)", status == 200 and invite["status"] == "pending", invite)
    _s, bob_view = call("GET", f"/social?device_id={bob['device']}")
    check("Bob sees the invite", [c["id"] for c in bob_view["challenges_in"]] == [invite["id"]], bob_view["challenges_in"])

    ## Challenger offline: accepting is refused, the invite stays pending.
    psql(f"UPDATE players SET last_seen_at = now() - interval '10 minutes' WHERE id = '{alice['id']}';")
    status, refused = call("POST", f"/friends/challenges/{invite['id']}/accept", {"device_id": bob["device"]})
    check("accept refused while Alice is offline", status == 409 and refused["detail"] == "challenger_offline", refused)
    ## Challenger in a game (busy poll): refused too, the invite stays pending.
    call("GET", f"/social?device_id={alice['device']}&busy=true")
    status, refused = call("POST", f"/friends/challenges/{invite['id']}/accept", {"device_id": bob["device"]})
    check("accept refused while Alice is in a game", status == 409 and refused["detail"] == "challenger_busy", refused)
    call("GET", f"/social?device_id={alice['device']}")
    status, accepted = call("POST", f"/friends/challenges/{invite['id']}/accept", {"device_id": bob["device"]})
    check("accept works once Alice is back", status == 200 and accepted["status"] == "accepted", accepted)
    _s, alice_view = call("GET", f"/social?device_id={alice['device']}")
    check("Alice sees her invite accepted", [c["status"] for c in alice_view["challenges_out"]] == ["accepted"], alice_view["challenges_out"])

    give_jokers(alice["id"])
    _s, pass_state = call("GET", f"/pass?device_id={alice['device']}")
    check("jokers in pass state", pass_state.get("jokers") == {"joker_5050": 1, "joker_time": 2}, pass_state.get("jokers"))

    a, b = await asyncio.gather(play_friend(alice, invite["id"], True), play_friend(bob, invite["id"], False))
    check("friend duel found, friendly flag", a["found"] and a["found"]["friendly"] and b["found"]["opponent_id"] == alice["id"], a["found"])
    check("Alice's stock sent at pairing", a["found"]["jokers"] == {"joker_5050": 1, "joker_time": 2}, a["found"]["jokers"])
    results = {(j["joker"], j["index"]): j for j in a["jokers"]}
    fifty = results.get(("joker_5050", 0), {})
    check("50/50 removes two wrong answers", fifty.get("ok") and len(fifty.get("removed", [])) == 2, fifty)
    check("time joker grants the bonus", results.get(("joker_time", 0), {}).get("ok") and a["bonus"] == 5.0, (results.get(("joker_time", 0)), a["bonus"]))
    check("second 50/50 in a match refused", results.get(("joker_5050", 1), {}).get("ok") is False, results.get(("joker_5050", 1)))
    check("Bob is told about both jokers", b["opponent_jokers"] == 2, b["opponent_jokers"])
    over = a["over"]
    check("match_over is friendly, no trophies, no pass XP",
          over["type"] == "match_over" and over["friendly"] and over["trophy_delta"] == 0 and over["pass_xp"] == 0, over)
    _s, pass_state = call("GET", f"/pass?device_id={alice['device']}")
    check("jokers spent server-side", pass_state.get("jokers") == {"joker_5050": 0, "joker_time": 1}, pass_state.get("jokers"))
    _s, alice_view = call("GET", f"/social?device_id={alice['device']}")
    check("played invite leaves the lists", alice_view["challenges_out"] == [], alice_view["challenges_out"])

    ## A played invite cannot be joined again.
    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({"type": "join_friend", "player_id": bob["id"], "challenge_id": invite["id"]}))
        message = json.loads(await asyncio.wait_for(ws.recv(), timeout=10))
    check("used invite refused on the socket", message.get("reason") == "invite_invalid", message)

    status, _r = call("POST", "/friends/remove", {"device_id": bob["device"], "player_id": alice["id"]})
    _s, alice_view = call("GET", f"/social?device_id={alice['device']}")
    check("remove friend works both ways", status == 200 and alice_view["friends"] == [], alice_view["friends"])

    _s, quest_a = call("POST", "/pass/quest", {"device_id": alice["device"], "quest_id": "q0", "day": "2000-01-01"})
    check("quest with an out-of-range day still pays (falls back to UTC day)", quest_a["pass_xp"] > 0, quest_a)

    print("\n" + ("ALL PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))


asyncio.run(main())
