"""Checks trophy matchmaking and the minimal anti-cheat of /ws/live.
Needs the stack running (docker compose up) and `pip install websockets`.
Usage: python tools/test_live_trophies.py"""
import asyncio
import json
import sys
from pathlib import Path
import subprocess
import time
import urllib.request
import uuid

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import bots  # noqa: E402
import trophies  # noqa: E402

API = "http://localhost:8000"
WS = "ws://localhost:8000/ws/live"
CATEGORY = "sport"
failures = []


def check(label: str, ok: bool, detail="") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(label)


def psql(sql: str) -> str:
    out = subprocess.run(
        ["docker", "exec", "quizz-backend-postgres-1", "sh", "-c",
         f'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -c "{sql}"'],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def new_player(trophies: int | None = None) -> str:
    body = json.dumps({"device_id": f"test-{uuid.uuid4()}", "display_name": "Bot"}).encode()
    req = urllib.request.Request(f"{API}/players", body, {"Content-Type": "application/json"})
    player_id = json.load(urllib.request.urlopen(req))["id"]
    if trophies is not None:
        psql(f"UPDATE players SET trophies = {trophies}, trophies_seeded = true WHERE id = '{player_id}'")
    return player_id


def db_player(player_id: str) -> tuple[int, int]:
    cups, flags = psql(f"SELECT trophies, cheat_flags FROM players WHERE id = '{player_id}'").split("|")
    return int(cups), int(flags)


def db_streaks(player_id: str) -> tuple[int, int]:
    win, loss = psql(f"SELECT versus_win_streak, versus_loss_streak FROM players WHERE id = '{player_id}'").split("|")
    return int(win), int(loss)


def check_settle_rules() -> None:
    """Same cases as the client's TrophySystem / settle_versus_trophies."""
    r = trophies.settle(100, 2, 0, 100, 500, 400)
    check("3rd win in a row: +10 streak bonus", r["streak_bonus"] == 10 and r["win_streak"] == 3 and r["delta"] == r["match_delta"] + 10, r)
    r = trophies.settle(100, 4, 0, 100, 500, 400)
    check("5th win in a row: +25", r["streak_bonus"] == 25, r)
    r = trophies.settle(100, 9, 0, 100, 500, 400)
    check("10th win in a row: +50", r["streak_bonus"] == 50, r)
    r = trophies.settle(100, 5, 0, 100, 500, 400)
    check("6th win: no bonus (exact milestones only)", r["streak_bonus"] == 0, r)
    r = trophies.settle(100, 0, 4, 100, 400, 500)
    check("5th loss in a row: +10 consolation", r["loss_consolation"] == 10 and r["loss_streak"] == 5 and r["delta"] == r["match_delta"] + 10, r)
    r = trophies.settle(100, 3, 2, 100, 400, 400)
    check("draw: 0 and both streaks reset", r["delta"] == 0 and r["win_streak"] == 0 and r["loss_streak"] == 0, r)
    r = trophies.settle(10, 0, 0, 10, 0, 900)
    check("never below 0 trophies", r["trophies"] == 0, r)


async def join(player_id: str, claimed: int | None, trophy_range: int | None = 50):
    ws = await websockets.connect(WS)
    msg = {"type": "join_queue", "player_id": player_id, "category": CATEGORY, "locale": "fr"}
    if claimed is not None:
        msg["trophies"] = claimed
    if trophy_range is not None:
        msg["trophy_range"] = trophy_range
    await ws.send(json.dumps(msg))
    return ws


async def recv_type(ws, wanted: str, timeout: float):
    deadline = time.monotonic() + timeout
    while True:
        msg = json.loads(await asyncio.wait_for(ws.recv(), deadline - time.monotonic()))
        if msg["type"] == wanted:
            return msg


async def play_out(ws, choice, cheat_early: bool = False) -> dict:
    """Answers every question (choice None = never answers); with cheat_early, also
    pre-sends the next answer during the reveal. Records how many answers each side got counted."""
    first_points = None
    counted = {"me": 0, "opponent": 0}
    while True:
        msg = json.loads(await asyncio.wait_for(ws.recv(), 30))
        if msg["type"] == "question":
            if choice is None:
                continue
            if not cheat_early or msg["index"] == 0:
                await asyncio.sleep(1.0)
                await ws.send(json.dumps({"type": "answer", "index": msg["index"], "selected_index": choice}))
        elif msg["type"] == "reveal":
            counted["me"] += msg["your_result"]["selected_index"] >= 0
            counted["opponent"] += msg["opponent_result"]["selected_index"] >= 0
            if first_points is None and msg["index"] == 1:
                first_points = msg["your_result"]
            if cheat_early:
                await ws.send(json.dumps({"type": "answer", "index": msg["index"] + 1, "selected_index": msg["correct_index"]}))
        elif msg["type"] in ("match_over", "match_aborted"):
            msg["_q1"] = first_points
            msg["_counted"] = counted
            return msg


async def expect_no_match(ws, seconds: float) -> bool:
    try:
        await recv_type(ws, "match_found", seconds)
        return False
    except asyncio.TimeoutError:
        return True


async def main() -> None:
    check_settle_rules()

    # 1. Close trophies pair inside ±50 and see each other's server trophies.
    a, b = new_player(100), new_player(120)
    for pid in (a, b):
        psql(f"UPDATE players SET versus_win_streak = 2, versus_loss_streak = 4 WHERE id = '{pid}'")
    wa, wb = await join(a, 100), await join(b, 120)
    fa, fb = await recv_type(wa, "match_found", 5), await recv_type(wb, "match_found", 5)
    check("100 vs 120 matched in ±50", True)
    check("match_found carries opponent_trophies", fa["opponent_trophies"] == 120 and fb["opponent_trophies"] == 100,
          f"{fa['opponent_trophies']}/{fb['opponent_trophies']}")
    over_a, over_b = await asyncio.gather(play_out(wa, 0), play_out(wb, 1))
    await wa.close(); await wb.close()
    check("match_over repeats opponent_trophies", over_a["opponent_trophies"] == 120, over_a)
    for pid, start, over in ((a, 100, over_a), (b, 120, over_b)):
        stored, _ = db_player(pid)
        check(f"server stored trophies {start}{over['trophy_delta']:+d}", stored == over["trophies"] == max(0, start + over["trophy_delta"]),
              f"db={stored} msg={over['trophies']}")
        parts = over["trophy_match_delta"] + over["trophy_streak_bonus"] + over["trophy_loss_consolation"]
        win, loss = db_streaks(pid)
        if over["your_score"] > over["opponent_score"]:
            ok = over["trophy_streak_bonus"] == 10 and (win, loss) == (3, 0)
        elif over["your_score"] < over["opponent_score"]:
            ok = over["trophy_loss_consolation"] == 10 and (win, loss) == (0, 5)
        else:
            ok = (win, loss) == (0, 0)
        check("streak bonus applied and streaks stored", ok and parts == over["trophy_delta"], f"{over} streaks={win}/{loss}")

    # 2. Far apart: no match until one side widens enough.
    c, d = new_player(100), new_player(400)
    wc, wd = await join(c, 100), await join(d, 400)
    check("100 vs 400 not matched at ±50", await expect_no_match(wc, 1.5))
    await wc.send(json.dumps({"type": "widen_search", "trophies": 100, "trophy_range": 400}))
    check("still no match while the other side is at ±50", await expect_no_match(wc, 1.0))
    await wd.send(json.dumps({"type": "widen_search", "trophies": 400, "trophy_range": 400}))
    fc = await recv_type(wc, "match_found", 5)
    check("matched once both windows reach ±400", fc["opponent_trophies"] == 400)
    await wc.close(); await wd.close()
    await asyncio.sleep(0.5)

    # 3. First ranked join imports claimed trophies, capped.
    e = new_player()
    we = await join(e, 99_999, 100_000)
    await asyncio.sleep(0.5)
    check("first claim capped at seed cap (1500)", db_player(e)[0] == 1500, db_player(e))
    await we.close()
    await asyncio.sleep(0.5)

    # 4. Later claims are ignored for matchmaking and flagged when far too high.
    f, g = new_player(300), new_player(5000)
    wf = await join(f, 5000)
    wg = await join(g, 5000)
    check("inflated claim (300 -> 5000) cannot reach a 5000 player", await expect_no_match(wf, 1.5))
    check("inflated claim flagged", db_player(f)[1] >= 1, db_player(f))
    await wf.close(); await wg.close()
    await asyncio.sleep(0.5)

    # 5. Same account twice at once is refused.
    h = new_player(0)
    wh1 = await join(h, 0)
    wh2 = await join(h, 0)
    try:
        await asyncio.wait_for(wh2.recv(), 3)
        check("second session of the same account refused", False)
    except websockets.ConnectionClosed as closed:
        check("second session of the same account refused", closed.code == 4009, closed.code)
    await wh1.close()
    await asyncio.sleep(0.5)

    # 6. Garbage answers don't crash the match; answers sent ahead of the question don't score as instant.
    i, j = new_player(0), new_player(0)
    wi, wj = await join(i, 0), await join(j, 0)
    await recv_type(wi, "match_found", 5); await recv_type(wj, "match_found", 5)
    await wj.send(json.dumps({"type": "answer", "index": "x", "selected_index": "abc"}))
    over_i, over_j = await asyncio.gather(play_out(wi, 0, cheat_early=True), play_out(wj, 2))
    check("match survives garbage answers", over_j["type"] == "match_over")
    q1 = over_i["_q1"]
    check("pre-sent answer not counted", q1 is not None and q1["selected_index"] == -1, q1)
    await wi.close(); await wj.close()

    # 7. Bad player ids are rejected, not crashing the server.
    wk = await websockets.connect(WS)
    await wk.send(json.dumps({"type": "join_queue", "player_id": "not-a-uuid", "category": CATEGORY}))
    try:
        await asyncio.wait_for(wk.recv(), 3)
        check("invalid player_id rejected", False)
    except websockets.ConnectionClosed as closed:
        check("invalid player_id rejected", closed.code == 4004, closed.code)

    # 8. Alone in the queue: a hidden bot of about the same level takes the seat after the delay.
    m = new_player(1000)
    started = time.monotonic()
    wm = await join(m, 1000)
    fm = await recv_type(wm, "match_found", bots.BOT_AFTER_SECONDS + 5)
    waited = time.monotonic() - started
    check(f"bot seated after ~{bots.BOT_AFTER_SECONDS:.0f} s", bots.BOT_AFTER_SECONDS - 1 <= waited <= bots.BOT_AFTER_SECONDS + 3, f"{waited:.1f} s")
    check("bot looks like a normal player", fm["opponent_name"] in bots.PSEUDOS and "is_bot" not in json.dumps(fm)
          and abs(fm["opponent_trophies"] - 1000) <= bots.TROPHY_JITTER, fm)
    over_m = await play_out(wm, 0)
    await wm.close()
    expected = bots.scaled_delta(trophies.calculate_delta(1000, fm["opponent_trophies"], over_m["your_score"], over_m["opponent_score"]))
    check("bot match settles half the match delta", over_m["trophy_match_delta"] == expected, f"{over_m} expected {expected}")
    check("bot never stored", psql(f"SELECT count(*) FROM players WHERE id = '{fm['opponent_id']}'") == "0"
          and psql(f"SELECT count(*) FROM matches WHERE player_id = '{m}'") == "1")
    check("bot answers on its own", over_m["_counted"]["opponent"] >= 5, over_m["_counted"])

    # 8b. A silent first player must not swallow the other player's answers (same deadline, parallel collection).
    n1, n2 = new_player(0), new_player(0)
    wn1 = await join(n1, 0)
    await asyncio.sleep(0.3)
    wn2 = await join(n2, 0)
    await recv_type(wn1, "match_found", 5); await recv_type(wn2, "match_found", 5)
    _over1, over2 = await asyncio.gather(play_out(wn1, None), play_out(wn2, 0))
    await wn1.close(); await wn2.close()
    check("second player's answers count when the first stays silent", over2["_counted"]["me"] == 7, over2["_counted"])

    # 9. Trophy leaderboard: real players (server trophies) mixed with hidden filler bots.
    def board(limit=100):
        return json.load(urllib.request.urlopen(f"{API}/leaderboard?category=all&limit={limit}"))

    top = new_player(99_000)
    rows = board()
    bot_count = int(psql("SELECT count(*) FROM leaderboard_bots"))
    check("leaderboard padded by bots", bot_count >= 80 and len(rows) >= min(100, bot_count), f"{len(rows)} rows, {bot_count} bots")
    ## Earlier runs leave their own 99 000 player behind: ours must be among the tied leaders.
    leaders = [r["player_id"] for r in rows if r["score"] == rows[0]["score"]]
    check("real player ranked by server trophies", rows[0]["score"] == 99_000 and top in leaders, rows[0])
    check("bots look like real rows", all(set(r) == {"rank", "player_id", "display_name", "score", "cosmetics"} for r in rows))
    check("sorted by trophies", all(rows[i]["score"] >= rows[i + 1]["score"] for i in range(len(rows) - 1)))
    check("board stable between requests", [r["player_id"] for r in board()] == [r["player_id"] for r in rows])
    before = {r["player_id"]: r["score"] for r in rows}
    psql("UPDATE leaderboard_bots SET updated_on = CURRENT_DATE - 1")
    after = {r["player_id"]: r["score"] for r in board()}
    moved = sum(1 for pid in before if pid in after and after[pid] != before[pid])
    check("bots drift once a day", moved > 10 and psql("SELECT count(*) FROM leaderboard_bots WHERE updated_on < CURRENT_DATE") == "0", moved)
    newcomer = new_player()
    check("players who never played ranked are hidden", all(r["player_id"] != newcomer for r in board()))

    print("\n" + ("ALL PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))


asyncio.run(main())
