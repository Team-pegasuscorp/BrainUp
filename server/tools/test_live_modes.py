"""Plays one ranked duel per mode (classic, survival, time_attack) against the stand-in
bot, and a draft between two humans. Needs the stack running (docker compose up) and
`pip install websockets`. Usage: python tools/test_live_modes.py  (~3 minutes: bots wait 20 s)"""
import asyncio
import json
import random
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


def register(name: str) -> str:
    body = json.dumps({"device_id": f"modes-{uuid.uuid4().hex[:10]}", "display_name": name}).encode()
    request = urllib.request.Request(API + "/players", data=body, headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(request))["id"]


async def play(player_id: str, mode: str, vote=None, trophies=700) -> dict:
    """Joins, votes (first choice unless `vote` is given), answers at random until match_over."""
    seen = {"questions": 0, "draft": None, "found": None, "progress": 0, "lives": [],
            "explanations": 0, "opponent_answered": 0, "opponent_ready": 0}
    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({"type": "join_queue", "player_id": player_id, "mode": mode,
                                  "locale": "fr", "trophies": trophies, "trophy_range": 100000}))
        while True:
            message = json.loads(await asyncio.wait_for(ws.recv(), timeout=120))
            kind = message["type"]
            if kind == "match_found":
                seen["found"] = message
                choices = (message.get("draft") or {}).get("choices", [])
                if choices:
                    await ws.send(json.dumps({"type": "draft_vote", "category": vote or choices[0]}))
            elif kind == "draft_result":
                seen["draft"] = message
            elif kind == "question":
                seen["questions"] += 1
                await asyncio.sleep(random.uniform(0.4, 1.2))
                await ws.send(json.dumps({"type": "answer", "index": message["index"],
                                          "selected_index": random.randrange(4)}))
            elif kind == "reveal":
                if "lives" in message["your_result"]:
                    seen["lives"].append(message["your_result"]["lives"])
                if message.get("explanation") and message.get("read_time", 0) > 0:
                    seen["explanations"] += 1
                    ## Read a moment, then tell the server we are ready.
                    await asyncio.sleep(0.5)
                    await ws.send(json.dumps({"type": "ready", "index": message["index"]}))
            elif kind == "opponent_answered":
                seen["opponent_answered"] += 1
            elif kind == "opponent_ready":
                seen["opponent_ready"] += 1
            elif kind == "opponent_progress":
                seen["progress"] += 1
            elif kind == "match_over":
                seen["over"] = message
                return seen
            elif kind == "match_aborted":
                seen["over"] = message
                return seen


async def main() -> None:
    ## Draft between two humans: same vote wins outright.
    a, b = register("DraftA"), register("DraftB")
    first = asyncio.create_task(play(a, "classic", vote="__first__"))
    await asyncio.sleep(0.3)
    second = asyncio.create_task(play(b, "classic"))
    ra, rb = await asyncio.gather(first, second)
    choices = ra["found"]["draft"]["choices"]
    check("draft offers 3 categories", len(choices) == 3, choices)
    check("both see the same drafted category", ra["draft"]["category"] == rb["draft"]["category"])
    check("an invalid vote is ignored", ra["draft"]["your_vote"] == "", ra["draft"])
    check("a lone valid vote decides", ra["draft"]["category"] == rb["draft"]["your_vote"], ra["draft"])
    check("classic plays 7 questions", ra["questions"] == 7, ra["questions"])
    check("match_over names the mode", ra["over"].get("mode") == "classic")
    check("classic reveals carry explanations", ra["explanations"] >= 5, ra["explanations"])
    check("opponent answers are announced", ra["opponent_answered"] >= 5, ra["opponent_answered"])
    check("opponent ready is announced", ra["opponent_ready"] >= 5, ra["opponent_ready"])

    ## One duel per mode against the bot, run side by side.
    ids = {mode: register(mode) for mode in ("classic", "survival", "time_attack")}
    results = await asyncio.gather(*(play(ids[mode], mode) for mode in ids))
    for mode, seen in zip(ids, results):
        over = seen["over"]
        check(f"{mode}: finished against a bot", over.get("type") == "match_over", over.get("type"))
        check(f"{mode}: category was drafted", bool(over.get("category")), over.get("category"))
        check(f"{mode}: server trophies returned", "trophies" in over and "trophy_delta" in over)
        if mode == "survival":
            lost_all = over["your_lives"] <= 0 or over["opponent_lives"] <= 0
            check("survival: stops when someone runs out of lives", lost_all or seen["questions"] >= 40,
                  f"{over['your_lives']} / {over['opponent_lives']} lives, {seen['questions']} q")
            if over["your_lives"] != over["opponent_lives"] and (over["your_lives"] <= 0) != (over["opponent_lives"] <= 0):
                check("survival: the survivor wins", over["won"] == (over["your_lives"] > 0))
        if mode == "time_attack":
            check("time_attack: more than 7 questions in 60 s", seen["questions"] > 7, seen["questions"])
            check("time_attack: opponent progress streamed", seen["progress"] > 0, seen["progress"])

    print(f"\n{len(failures)} FAILED: {failures}" if failures else "\nALL PASSED")


if __name__ == "__main__":
    asyncio.run(main())
