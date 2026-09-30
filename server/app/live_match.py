import asyncio
import random
import time
import uuid
from dataclasses import dataclass, field

from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy import text

import bots
import question_bank
import trophies
from trophies import LEGACY_RANGE
from db import engine
from question_bank import get_questions
from scoring import calculate_points

QUESTIONS_PER_MATCH = 7
MODES = ("classic", "survival", "time_attack")
## Pre-match draft: categories offered, voting time, pause on the result (client roulette).
DRAFT_CHOICES = 3
DRAFT_SECONDS = 8.0
DRAFT_REVEAL_SECONDS = 3.0
SURVIVAL_LIVES = 3
## Hard stop so two perfect players cannot play forever; points decide then.
SURVIVAL_MAX_QUESTIONS = 40
TIME_ATTACK_SECONDS = 60.0
TIME_ATTACK_WRONG_PENALTY = 5.0
TIME_ATTACK_POOL = 80
TIME_ATTACK_FEEDBACK_SECONDS = 0.8
## After a synced question: the explanation is read for a time that grows with its
## length (same numbers as the solo game); both players tapping "ready" moves on sooner.
READ_BASE_SECONDS = 3.0
READ_SECONDS_PER_CHAR = 0.035
READ_MIN_SECONDS = 4.0
READ_MAX_SECONDS = 10.0
## Same cap as the client's GameManager.MODE_COMBO_CAP for long modes.
MODE_COMBO_CAP = 10
TIME_LIMIT_SECONDS = 10.0
ANSWER_GRACE_SECONDS = 2.0
REVEAL_PAUSE_SECONDS = 1.5
## Answers faster than this after the question left the server are flagged (not rejected):
## a human cannot read four choices and tap within a network round trip.
SUSPICIOUS_ANSWER_SECONDS = 0.25
## Claimed trophies may drift above the server's value (client-only streak bonuses);
## beyond this margin the claim is flagged.
CLAIM_DRIFT_TOLERANCE = 250

# Single-process, in-memory matchmaking: fine at hobby scale, but breaks if the
# API is ever run with more than one uvicorn worker (would need e.g. Redis then).
_queues: dict[str, list["Waiting"]] = {}
_queue_lock = asyncio.Lock()
_matches: dict[str, "LiveMatch"] = {}
## Players queued or in a match: one live session per account at a time.
_active_players: set[str] = set()
_match_tasks: set[asyncio.Task] = set()


@dataclass(eq=False)
class Waiting:
    player_id: str
    display_name: str
    locale: str
    websocket: WebSocket
    future: asyncio.Future = field(repr=False)
    trophies: int = 0
    trophy_range: int = LEGACY_RANGE
    joined_at: float = 0.0
    is_bot: bool = False
    cosmetics: dict = field(default_factory=dict)
    mode: str = "classic"
    ## Legacy clients pick the category up front; "" means it is drafted after pairing.
    category: str = ""


class PlayerState:
    def __init__(self, waiting: Waiting):
        self.player_id = waiting.player_id
        self.display_name = waiting.display_name
        self.locale = waiting.locale
        self.websocket = waiting.websocket
        ## Frozen at pairing time: used for the delta and echoed in match_over.
        self.trophies = waiting.trophies
        self.is_bot = waiting.is_bot
        self.cosmetics = waiting.cosmetics
        self.score = 0
        self.correct_count = 0
        self.combo = 0
        self.max_combo = 0
        self.connected = True
        self.answered = 0
        self.lives = SURVIVAL_LIVES
        self.answers: asyncio.Queue = asyncio.Queue()
        self.votes: asyncio.Queue = asyncio.Queue()
        self.readies: asyncio.Queue = asyncio.Queue()


class LiveMatch:
    """One ranked duel: optional category draft, then the mode's rounds, then settle.
    Modes: classic (7 synced questions), survival (synced, 3 lives, last one standing)
    and time_attack (each player's own 60 s clock over the same question list)."""

    def __init__(self, match_id: str, mode: str, category: str, a: PlayerState, b: PlayerState):
        self.match_id = match_id
        self.mode = mode
        ## "" = decided by the draft once both players are seated.
        self.category = category
        self.draft_choices = [] if category else question_bank.draft_choices(DRAFT_CHOICES)
        self.players = {a.player_id: a, b.player_id: b}
        self.order = [a, b]
        self.completed = asyncio.Event()

    def opponent_of(self, player_id: str) -> PlayerState:
        for player in self.order:
            if player.player_id != player_id:
                return player
        raise KeyError(player_id)

    async def run(self) -> None:
        ## Always release both players, even if the match crashes midway.
        try:
            await self._run()
        finally:
            self.completed.set()

    async def _run(self) -> None:
        await self._broadcast_pairing()
        if not self.category:
            self.category = await self._run_draft()

        a = self.order[0]
        wanted = {"classic": QUESTIONS_PER_MATCH, "survival": SURVIVAL_MAX_QUESTIONS}.get(self.mode, TIME_ATTACK_POOL)
        questions = get_questions(self.category, a.locale, wanted)
        if len(questions) < QUESTIONS_PER_MATCH:
            await self._broadcast({"type": "match_aborted", "reason": "not_enough_questions"})
            return

        await self._broadcast({"type": "match_start", "mode": self.mode, "category": self.category})
        if self.mode == "time_attack":
            await asyncio.gather(*(self._time_attack_stream(player, questions) for player in self.order))
        else:
            for index, question in enumerate(questions):
                await self._run_question(index, question)
                if self.mode == "survival" and any(player.lives <= 0 for player in self.order):
                    break
        await self._finish()

    async def _broadcast_pairing(self) -> None:
        for player in self.order:
            opponent = self.opponent_of(player.player_id)
            await self._send(player, {
                "type": "match_found",
                "match_id": self.match_id,
                "mode": self.mode,
                "category": self.category,
                "draft": {"choices": self.draft_choices, "time_limit": DRAFT_SECONDS} if self.draft_choices else None,
                "opponent_name": opponent.display_name,
                "opponent_id": opponent.player_id,
                "opponent_trophies": opponent.trophies,
                "opponent_cosmetics": opponent.cosmetics,
                "your_trophies": player.trophies,
                "total_questions": QUESTIONS_PER_MATCH if self.mode == "classic" else 0,
                "lives": SURVIVAL_LIVES if self.mode == "survival" else 0,
                "clock": TIME_ATTACK_SECONDS if self.mode == "time_attack" else 0,
            })

    # --- Draft ---------------------------------------------------------------

    async def _run_draft(self) -> str:
        """Each player votes for one of the offered categories. Same vote: that one;
        two different votes: a coin flip between them; nobody votes: any of them."""
        deadline = time.monotonic() + DRAFT_SECONDS
        for player in self.order:
            if player.is_bot:
                _spawn(self._bot_vote(player))
        votes = await asyncio.gather(*(self._collect_vote(player, deadline) for player in self.order))
        cast = [vote for vote in votes if vote]
        if not cast:
            category = random.choice(self.draft_choices)
        else:
            category = random.choice(cast)
        for player, vote in zip(self.order, votes):
            opponent_vote = votes[1] if player is self.order[0] else votes[0]
            await self._send(player, {
                "type": "draft_result",
                "category": category,
                "your_vote": vote,
                "opponent_vote": opponent_vote,
            })
        await asyncio.sleep(DRAFT_REVEAL_SECONDS)
        return category

    async def _collect_vote(self, player: PlayerState, deadline: float) -> str:
        while player.connected or player.is_bot:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return ""
            try:
                message = await asyncio.wait_for(player.votes.get(), timeout=remaining)
            except asyncio.TimeoutError:
                return ""
            vote = str(message.get("category", ""))
            if vote in self.draft_choices:
                return vote
        return ""

    async def _bot_vote(self, bot: PlayerState) -> None:
        await asyncio.sleep(random.uniform(1.5, DRAFT_SECONDS - 2.0))
        await bot.votes.put({"category": random.choice(self.draft_choices)})

    # --- Synced rounds (classic, survival) -----------------------------------

    async def _run_question(self, index: int, question: dict) -> None:
        for player in self.order:
            _drain(player.answers)
        send_time = time.monotonic()
        for player in self.order:
            await self._send(player, {
                "type": "question",
                "index": index,
                "text": question["text"],
                "choices": question["choices"],
                "time_limit": TIME_LIMIT_SECONDS,
            })

        for player in self.order:
            if player.is_bot:
                _spawn(self._bot_answer(player, index, question, TIME_LIMIT_SECONDS))

        ## Both players are collected in parallel against the same deadline: collecting them
        ## one after the other would let a slow first player eat the second one's window.
        collected = await asyncio.gather(*(
            self._collect_answer(player, index, send_time, question) for player in self.order
        ))
        results = {player.player_id: result for player, result in zip(self.order, collected)}
        if self.mode == "survival":
            for player in self.order:
                if not results[player.player_id]["is_correct"]:
                    player.lives -= 1
                results[player.player_id]["lives"] = player.lives

        ## Survival keeps its pace when both got it right: explanations follow mistakes.
        explanation = question.get("explanation", "")
        if self.mode == "survival" and all(result["is_correct"] for result in results.values()):
            explanation = ""
        read_time = self._read_time(explanation)
        ## A "ready" may come during the colour pause below: clear old ones before.
        for player in self.order:
            _drain(player.readies)
        for player in self.order:
            opponent = self.opponent_of(player.player_id)
            await self._send(player, {
                "type": "reveal",
                "index": index,
                "correct_index": question["correct_index"],
                "your_result": results[player.player_id],
                "opponent_result": results[opponent.player_id],
                "explanation": explanation,
                "read_time": read_time,
            })

        await asyncio.sleep(REVEAL_PAUSE_SECONDS)
        if read_time > 0:
            await self._wait_ready(index, read_time)

    @staticmethod
    def _read_time(explanation: str) -> float:
        if not explanation:
            return 0.0
        seconds = READ_BASE_SECONDS + len(explanation) * READ_SECONDS_PER_CHAR
        return round(max(READ_MIN_SECONDS, min(READ_MAX_SECONDS, seconds)), 1)

    async def _wait_ready(self, index: int, read_time: float) -> None:
        """Explanation phase: ends when both players tapped "ready" or the time is up."""
        deadline = time.monotonic() + read_time
        for player in self.order:
            if player.is_bot:
                _spawn(self._bot_ready(player, index))

        async def wait_one(player: PlayerState) -> None:
            while player.connected or player.is_bot:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return
                try:
                    message = await asyncio.wait_for(player.readies.get(), timeout=remaining)
                except asyncio.TimeoutError:
                    return
                if trophies.sanitize_int(message.get("index"), -1) == index:
                    await self._send(self.opponent_of(player.player_id), {"type": "opponent_ready", "index": index})
                    return

        await asyncio.gather(*(wait_one(player) for player in self.order))

    async def _bot_ready(self, bot: PlayerState, index: int) -> None:
        await asyncio.sleep(random.uniform(2.0, 4.5))
        await bot.readies.put({"index": index})

    # --- Time attack: one clock per player ------------------------------------

    async def _time_attack_stream(self, player: PlayerState, questions: list[dict]) -> None:
        opponent = self.opponent_of(player.player_id)
        clock = TIME_ATTACK_SECONDS
        for index, question in enumerate(questions):
            if clock <= 0:
                break
            _drain(player.answers)
            send_time = time.monotonic()
            await self._send(player, {
                "type": "question",
                "index": index,
                "text": question["text"],
                "choices": question["choices"],
                "time_limit": clock,
                "clock": clock,
            })
            if player.is_bot:
                _spawn(self._bot_answer(player, index, question, min(clock, TIME_LIMIT_SECONDS)))
            result = await self._collect_answer(player, index, send_time, question, time_limit=clock)
            clock -= result["elapsed"]
            if result["selected_index"] >= 0 and not result["is_correct"]:
                clock -= TIME_ATTACK_WRONG_PENALTY
            clock = max(clock, 0.0)
            result["clock"] = round(clock, 2)
            await self._send(player, {
                "type": "reveal",
                "index": index,
                "correct_index": question["correct_index"],
                "your_result": result,
            })
            await self._send(opponent, {
                "type": "opponent_progress",
                "score": player.score,
                "correct_count": player.correct_count,
                "answered": player.answered,
                "clock": round(clock, 2),
            })
            ## The clock stands still while the answer is shown.
            await asyncio.sleep(TIME_ATTACK_FEEDBACK_SECONDS)
        await self._send(player, {"type": "player_done", "score": player.score})

    # --- Shared ---------------------------------------------------------------

    async def _collect_answer(self, player: PlayerState, index: int, send_time: float, question: dict,
                              time_limit: float = TIME_LIMIT_SECONDS) -> dict:
        selected_index = -1
        answered_at = send_time + time_limit
        deadline = send_time + time_limit + ANSWER_GRACE_SECONDS
        while player.connected or player.is_bot:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                received_at, message = await asyncio.wait_for(player.answers.get(), timeout=remaining)
            except asyncio.TimeoutError:
                break
            ## Only the first valid answer to *this* question, received after it was sent,
            ## counts: answers queued ahead of time would otherwise score as instant.
            if received_at < send_time or trophies.sanitize_int(message.get("index"), -1) != index:
                continue
            choice = trophies.sanitize_int(message.get("selected_index"), -99)
            if not 0 <= choice < len(question["choices"]):
                if not player.is_bot:
                    _flag_player(player.player_id)
                continue
            selected_index = choice
            answered_at = received_at
            if received_at - send_time < SUSPICIOUS_ANSWER_SECONDS and not player.is_bot:
                _flag_player(player.player_id)
            ## Synced modes: tell the other side "they answered" (not what), for tension.
            if self.mode != "time_attack":
                await self._send(self.opponent_of(player.player_id), {"type": "opponent_answered", "index": index})
            break

        elapsed = min(max(answered_at - send_time, 0.0), time_limit)
        is_correct = selected_index == question["correct_index"]
        player.answered += 1
        if is_correct:
            player.combo += 1
            player.max_combo = max(player.max_combo, player.combo)
            player.correct_count += 1
            ## Long modes cap the combo so a run cannot farm points.
            combo = player.combo if self.mode == "classic" else min(player.combo, MODE_COMBO_CAP)
            points = calculate_points(min(elapsed, TIME_LIMIT_SECONDS), TIME_LIMIT_SECONDS, combo)
        else:
            player.combo = 0
            points = 0
        player.score += points

        return {
            "selected_index": selected_index,
            "is_correct": is_correct,
            "points": points,
            "score": player.score,
            "elapsed": round(elapsed, 3),
        }

    async def _bot_answer(self, bot: PlayerState, index: int, question: dict, time_limit: float) -> None:
        delay, choice = bots.plan_answer(bot.trophies, question, time_limit)
        if choice < 0:
            ## A planned timeout: in time attack the clock is the limit, so answer late
            ## instead; elsewhere just let the question expire.
            if self.mode != "time_attack":
                return
            choice = random.randrange(len(question["choices"]))
        await asyncio.sleep(delay)
        await bot.answers.put((time.monotonic(), {"index": index, "selected_index": choice}))

    def _outcome(self, player: PlayerState, opponent: PlayerState) -> int:
        """1 win, -1 loss, 0 draw. Survival: whoever still has lives wins, else points."""
        if self.mode == "survival":
            alive, other_alive = player.lives > 0, opponent.lives > 0
            if alive != other_alive:
                return 1 if alive else -1
        return (player.score > opponent.score) - (player.score < opponent.score)

    async def _finish(self) -> None:
        a, b = self.order
        with engine.begin() as conn:
            for player in (a, b):
                if player.is_bot:
                    continue
                conn.execute(
                    text(
                        """
                        INSERT INTO matches
                            (player_id, category, score, correct_count, total_count, max_combo, won)
                        VALUES
                            (:player_id, :category, :score, :correct_count, :total_count, :max_combo, :won)
                        """
                    ),
                    {
                        "player_id": player.player_id,
                        "category": self.category,
                        "score": player.score,
                        "correct_count": player.correct_count,
                        "total_count": player.answered,
                        "max_combo": player.max_combo,
                        "won": self._outcome(player, self.opponent_of(player.player_id)) > 0,
                    },
                )

        settled = {}
        with engine.begin() as conn:
            for player in (a, b):
                if player.is_bot:
                    continue
                opponent = self.opponent_of(player.player_id)
                win_streak, loss_streak = conn.execute(
                    text("SELECT versus_win_streak, versus_loss_streak FROM players WHERE id = :id FOR UPDATE"),
                    {"id": player.player_id},
                ).one()
                result = trophies.settle(
                    player.trophies, win_streak, loss_streak,
                    opponent.trophies, player.score, opponent.score,
                    scale_match_delta=bots.scaled_delta if opponent.is_bot else None,
                    outcome=self._outcome(player, opponent),
                )
                settled[player.player_id] = result
                conn.execute(
                    text(
                        """
                        UPDATE players
                        SET trophies = :trophies, versus_win_streak = :win_streak,
                            versus_loss_streak = :loss_streak
                        WHERE id = :id
                        """
                    ),
                    {
                        "trophies": result["trophies"],
                        "win_streak": result["win_streak"],
                        "loss_streak": result["loss_streak"],
                        "id": player.player_id,
                    },
                )

        for player in (a, b):
            if player.is_bot:
                continue
            opponent = self.opponent_of(player.player_id)
            result = settled[player.player_id]
            outcome = self._outcome(player, opponent)
            await self._send(player, {
                "type": "match_over",
                "match_id": self.match_id,
                "mode": self.mode,
                "category": self.category,
                "your_score": player.score,
                "opponent_score": opponent.score,
                "your_correct": player.correct_count,
                "opponent_correct": opponent.correct_count,
                "your_answered": player.answered,
                "your_max_combo": player.max_combo,
                "your_lives": player.lives,
                "opponent_lives": opponent.lives,
                "won": outcome > 0,
                "draw": outcome == 0,
                "opponent_trophies": opponent.trophies,
                ## trophy_delta is the total change; the three parts match the client's breakdown.
                "trophy_delta": result["delta"],
                "trophy_match_delta": result["match_delta"],
                "trophy_streak_bonus": result["streak_bonus"],
                "trophy_loss_consolation": result["loss_consolation"],
                "trophies": result["trophies"],
                "win_streak": result["win_streak"],
                "loss_streak": result["loss_streak"],
            })
        self.completed.set()

    async def _broadcast(self, message: dict) -> None:
        for player in self.order:
            await self._send(player, message)

    async def _send(self, player: PlayerState, message: dict) -> None:
        if not player.connected or player.is_bot:
            return
        try:
            await player.websocket.send_json(message)
        except Exception:
            player.connected = False


def _spawn(coro) -> None:
    task = asyncio.create_task(coro)
    _match_tasks.add(task)
    task.add_done_callback(_match_tasks.discard)


def _drain(queue: asyncio.Queue) -> None:
    while not queue.empty():
        queue.get_nowait()


def _flag_player(player_id: str) -> None:
    with engine.begin() as conn:
        conn.execute(text("UPDATE players SET cheat_flags = cheat_flags + 1 WHERE id = :id"), {"id": player_id})


def _load_ranked_player(player_id: str, claimed_trophies) -> tuple[str, int, dict] | None:
    """Display name, the trophies the server trusts and the look for this player.
    The first ranked join imports the client's (capped) value once; afterwards the
    stored value wins and a claim far above it is flagged."""
    with engine.begin() as conn:
        row = conn.execute(
            text("SELECT display_name, trophies, trophies_seeded, cosmetics FROM players WHERE id = :id FOR UPDATE"),
            {"id": player_id},
        ).first()
        if row is None:
            return None
        display_name, stored, seeded, cosmetics = row
        cosmetics = cosmetics or {}
        if claimed_trophies is None:
            return display_name, stored, cosmetics
        if not seeded:
            ## Keep anything already earned on the server (e.g. matches played on an old client).
            stored = max(stored, trophies.seed_value(claimed_trophies))
            conn.execute(
                text("UPDATE players SET trophies = :t, trophies_seeded = true WHERE id = :id"),
                {"t": stored, "id": player_id},
            )
        elif trophies.sanitize_int(claimed_trophies) > stored + CLAIM_DRIFT_TOLERANCE:
            conn.execute(text("UPDATE players SET cheat_flags = cheat_flags + 1 WHERE id = :id"), {"id": player_id})
        return display_name, stored, cosmetics


def _pair_locked(category: str, me: Waiting) -> bool:
    """Pairs `me` (already queued) with the closest compatible player. Caller holds the lock."""
    waiting_list = _queues.get(category, [])
    best, best_gap = None, None
    for other in waiting_list:
        if other is me or other.player_id == me.player_id:
            continue
        if not trophies.compatible(me.trophies, me.trophy_range, other.trophies, other.trophy_range):
            continue
        gap = abs(me.trophies - other.trophies)
        ## Strict < keeps the earliest arrival on ties (the list is in join order).
        if best is None or gap < best_gap:
            best, best_gap = other, gap
    if best is None:
        return False

    waiting_list.remove(best)
    waiting_list.remove(me)
    first, second = sorted((best, me), key=lambda w: w.joined_at)
    _start_match(category, first, second)
    return True


def _start_match(queue_key: str, first: Waiting, second: Waiting) -> None:
    match_id = str(uuid.uuid4())
    match = LiveMatch(match_id, first.mode, first.category, PlayerState(first), PlayerState(second))
    _matches[match_id] = match
    _spawn(match.run())
    for waiting in (first, second):
        if not waiting.future.done():
            waiting.future.set_result((match_id, match))


async def _seat_bot(category: str, me: Waiting) -> None:
    """No human found in time: a bot close to the player's level takes the other seat."""
    async with _queue_lock:
        waiting_list = _queues.get(category, [])
        if me.future.done() or me not in waiting_list:
            return
        waiting_list.remove(me)
        bot_id, bot_name, bot_trophies = bots.new_identity(me.trophies)
        loop = asyncio.get_running_loop()
        bot = Waiting(
            bot_id, bot_name, me.locale, None, loop.create_future(),
            trophies=bot_trophies, joined_at=time.monotonic(), is_bot=True,
            cosmetics=bots.cosmetics_for(bot_id), mode=me.mode, category=me.category,
        )
        _start_match(category, me, bot)


async def _enqueue(category: str, me: Waiting) -> None:
    async with _queue_lock:
        _queues.setdefault(category, []).append(me)
        _pair_locked(category, me)


async def _widen(category: str, me: Waiting, requested_range) -> None:
    async with _queue_lock:
        if me.future.done() or me not in _queues.get(category, []):
            return
        ## A window only ever grows; trophies stay the server's value.
        me.trophy_range = max(me.trophy_range, trophies.snap_range(requested_range))
        _pair_locked(category, me)


async def _remove_from_queue(category: str, me: Waiting) -> None:
    async with _queue_lock:
        waiting_list = _queues.get(category, [])
        if me in waiting_list:
            waiting_list.remove(me)


async def _read_while_waiting(websocket: WebSocket, category: str, me: Waiting) -> None:
    try:
        while True:
            message = await websocket.receive_json()
            if isinstance(message, dict) and message.get("type") == "widen_search":
                await _widen(category, me, message.get("trophy_range"))
    except (WebSocketDisconnect, ValueError):
        return


async def _forward_inbound(websocket: WebSocket, player: PlayerState) -> None:
    try:
        while True:
            message = await websocket.receive_json()
            if not isinstance(message, dict):
                continue
            if message.get("type") == "answer" and player.answers.qsize() < 8:
                await player.answers.put((time.monotonic(), message))
            elif message.get("type") == "draft_vote" and player.votes.qsize() < 4:
                await player.votes.put(message)
            elif message.get("type") == "ready" and player.readies.qsize() < 4:
                await player.readies.put(message)
    except (WebSocketDisconnect, ValueError):
        player.connected = False


async def handle_live_socket(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        join_msg = await websocket.receive_json()
    except (WebSocketDisconnect, ValueError):
        return

    if not isinstance(join_msg, dict) or join_msg.get("type") != "join_queue":
        await websocket.close(code=4000)
        return

    try:
        player_id = str(uuid.UUID(str(join_msg.get("player_id", ""))))
    except ValueError:
        await websocket.close(code=4004)
        return
    ## New clients send a mode and draft the category after pairing; older ones send
    ## a category and play classic in it. The queue key keeps the two apart.
    mode = str(join_msg.get("mode", ""))
    fixed_category = "" if mode else str(join_msg.get("category", ""))[:32]
    if mode not in MODES:
        mode = "classic"
    category = f"mode:{mode}" if not fixed_category else fixed_category
    locale = str(join_msg.get("locale", "fr"))[:8]

    ranked = _load_ranked_player(player_id, join_msg.get("trophies"))
    if ranked is None:
        await websocket.close(code=4004)
        return
    display_name, server_trophies, cosmetics = ranked

    async with _queue_lock:
        if player_id in _active_players:
            already_active = True
        else:
            already_active = False
            _active_players.add(player_id)
    if already_active:
        await websocket.close(code=4009)
        return

    try:
        loop = asyncio.get_running_loop()
        waiting = Waiting(
            player_id, display_name, locale, websocket, loop.create_future(),
            trophies=server_trophies,
            trophy_range=trophies.snap_range(join_msg.get("trophy_range")),
            joined_at=time.monotonic(),
            cosmetics=cosmetics,
            mode=mode,
            category=fixed_category,
        )
        await _enqueue(category, waiting)

        reader = asyncio.create_task(_read_while_waiting(websocket, category, waiting))
        done, _pending = await asyncio.wait(
            {waiting.future, reader}, timeout=bots.BOT_AFTER_SECONDS, return_when=asyncio.FIRST_COMPLETED
        )
        if not done:
            await _seat_bot(category, waiting)
            done, _pending = await asyncio.wait({waiting.future, reader}, return_when=asyncio.FIRST_COMPLETED)
        if waiting.future not in done:
            waiting.future.cancel()
            await _remove_from_queue(category, waiting)
            return
        reader.cancel()
        match_id, match = waiting.future.result()

        player = match.players[player_id]
        forward_task = asyncio.create_task(_forward_inbound(websocket, player))
        try:
            await match.completed.wait()
        finally:
            forward_task.cancel()
            _matches.pop(match_id, None)
    finally:
        _active_players.discard(player_id)
