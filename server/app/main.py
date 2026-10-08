import secrets
from datetime import date, datetime, timezone
from uuid import UUID

from fastapi import FastAPI, HTTPException, Query, WebSocket
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

import battle_pass
import bots
import friends
import leaderboard_bots
from db import engine
from live_match import handle_live_socket
from scoring import calculate_points
from schemas import (
    Challenge,
    ChallengeCreate,
    ChallengeJoin,
    ChallengeResult,
    DailyChallenge,
    DailyLeaderboard,
    DailyResult,
    DailyResultSubmit,
    DeviceOnly,
    FriendChallengeCreate,
    FriendTarget,
    LeaderboardEntry,
    Match,
    MatchSubmit,
    PassClaim,
    PassPremium,
    PassQuest,
    Player,
    PlayerRegister,
)

## Daily challenge rotation: one category a day, "general" mixes them all. The game keeps a
## copy (scripts/profile/daily_challenge.gd) as its offline fallback: change both together.
DAILY_CATEGORIES = ["sport", "cinema", "history", "geography", "science", "music", "television", "general"]
DAILY_ROTATION_START = date(2026, 10, 7)
## Before the 8-category rotation started, the challenge only cycled through these three.
LEGACY_DAILY_CATEGORIES = ["sport", "cinema", "history"]
DAILY_QUESTION_COUNT = 7
QUESTION_TIME_SECONDS = 10.0
# Best possible daily score: every answer instant, combo growing each question.
MAX_DAILY_SCORE = sum(
    calculate_points(0.0, QUESTION_TIME_SECONDS, combo)
    for combo in range(1, DAILY_QUESTION_COUNT + 1)
)
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CHALLENGE_COLUMNS = (
    "id, code, category, challenger_id, opponent_id, "
    "challenger_score, challenger_correct_count, "
    "opponent_score, opponent_correct_count, status, created_at"
)


def _generate_code(length: int = 6) -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(length))

app = FastAPI(title="Quizz backend")


@app.get("/health")
def health():
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok"}


@app.websocket("/ws/live")
async def live_endpoint(websocket: WebSocket):
    await handle_live_socket(websocket)


@app.post("/players", response_model=Player)
def register_player(payload: PlayerRegister):
    with engine.begin() as conn:
        row = conn.execute(
            text(
                """
                INSERT INTO players (device_id, display_name, cosmetics, level)
                VALUES (:device_id, :display_name, COALESCE(CAST(:cosmetics AS jsonb), '{}'::jsonb),
                    COALESCE(:level, 1))
                ON CONFLICT (device_id)
                DO UPDATE SET display_name = EXCLUDED.display_name,
                    cosmetics = COALESCE(CAST(:cosmetics AS jsonb), players.cosmetics),
                    level = COALESCE(:level, players.level), last_seen_at = now()
                RETURNING id, device_id, display_name, created_at, cosmetics
                """
            ),
            {
                "device_id": payload.device_id,
                "display_name": payload.display_name,
                "cosmetics": payload.cosmetics.model_dump_json() if payload.cosmetics else None,
                "level": payload.level,
            },
        ).mappings().one()
    return row


@app.post("/matches", response_model=Match)
def submit_match(payload: MatchSubmit):
    try:
        with engine.begin() as conn:
            row = conn.execute(
                text(
                    """
                    INSERT INTO matches
                        (player_id, category, score, correct_count, total_count, max_combo, won)
                    VALUES
                        (:player_id, :category, :score, :correct_count, :total_count, :max_combo, :won)
                    RETURNING id, player_id, category, score, correct_count, total_count, max_combo, won, played_at
                    """
                ),
                payload.model_dump(),
            ).mappings().one()
    except IntegrityError:
        raise HTTPException(status_code=404, detail="player not found")
    return row


@app.get("/leaderboard", response_model=list[LeaderboardEntry])
def leaderboard(category: str = "all", limit: int = Query(50, ge=1, le=100)):
    if category == "all":
        return _trophy_leaderboard(limit)
    where_clause = "WHERE m.category = :category"
    query = f"""
        SELECT p.id AS player_id, p.display_name, p.cosmetics, MAX(m.score) AS score
        FROM matches m
        JOIN players p ON p.id = m.player_id
        {where_clause}
        GROUP BY p.id, p.display_name, p.cosmetics
        ORDER BY score DESC, p.display_name ASC
        LIMIT :limit
    """
    with engine.connect() as conn:
        rows = conn.execute(text(query), {"limit": limit, "category": category}).mappings().all()
    return [{"rank": index + 1, **row} for index, row in enumerate(rows)]


def _trophy_leaderboard(limit: int) -> list[dict]:
    """Main board: ranked by the server's trophies (see trophies.py), padded with hidden
    filler bots. `score` carries the trophies, which the client shows with 🏆."""
    with engine.begin() as conn:
        leaderboard_bots.ensure(conn)
        rows = conn.execute(
            text(
                """
                SELECT player_id, display_name, score, cosmetics, is_bot FROM (
                    SELECT id AS player_id, display_name, trophies AS score, cosmetics, false AS is_bot
                    FROM players WHERE trophies_seeded OR trophies > 0
                    UNION ALL
                    SELECT id, display_name, trophies, NULL::jsonb, true FROM leaderboard_bots
                ) board
                ORDER BY score DESC, display_name ASC
                LIMIT :limit
                """
            ),
            {"limit": limit},
        ).mappings().all()
    board = []
    for index, row in enumerate(rows):
        entry = dict(row)
        ## Filler bots get a stable random look so they pass as real players.
        if entry.pop("is_bot"):
            entry["cosmetics"] = bots.cosmetics_for(str(entry["player_id"]))
        board.append({"rank": index + 1, **entry})
    return board


def _today_daily():
    """Today's shared challenge, always on the UTC calendar day."""
    today = datetime.now(timezone.utc).date()
    return today, daily_category(today)


def daily_category(day: date) -> str:
    if day < DAILY_ROTATION_START:
        return LEGACY_DAILY_CATEGORIES[day.toordinal() % len(LEGACY_DAILY_CATEGORIES)]
    return DAILY_CATEGORIES[(day - DAILY_ROTATION_START).days % len(DAILY_CATEGORIES)]


@app.get("/daily-challenge", response_model=DailyChallenge)
def daily_challenge():
    today, category_id = _today_daily()
    return {"date": today.isoformat(), "category_id": category_id, "seed": today.isoformat()}


# Rank = score, then more correct answers, then whoever finished first.
DAILY_RANKED = """
    SELECT r.player_id, p.display_name, p.cosmetics, r.score, r.correct_count,
           ROW_NUMBER() OVER (
               ORDER BY r.score DESC, r.correct_count DESC, r.played_at ASC
           ) AS rank
    FROM daily_results r
    JOIN players p ON p.id = r.player_id
    WHERE r.day = :day
"""


@app.post("/daily-challenge/result", response_model=DailyResult)
def submit_daily_result(payload: DailyResultSubmit):
    today, category_id = _today_daily()
    # The server knows today's category and the scoring rules, so it can refuse
    # results that are impossible instead of trusting the client blindly.
    if (
        payload.total_count != DAILY_QUESTION_COUNT
        or payload.correct_count > payload.total_count
        or payload.max_combo > payload.correct_count
        or payload.score > MAX_DAILY_SCORE
        or (payload.correct_count == 0 and payload.score > 0)
    ):
        raise HTTPException(status_code=422, detail="implausible daily result")

    try:
        with engine.begin() as conn:
            inserted = conn.execute(
                text(
                    """
                    INSERT INTO daily_results
                        (player_id, day, category, score, correct_count, total_count, max_combo)
                    VALUES
                        (:player_id, :day, :category, :score, :correct_count, :total_count, :max_combo)
                    ON CONFLICT (player_id, day) DO NOTHING
                    RETURNING id
                    """
                ),
                {**payload.model_dump(), "day": today, "category": category_id},
            ).first()
            ## Only the first result of the day pays pass XP.
            pass_xp = battle_pass.record_daily(conn, str(payload.player_id)) if inserted is not None else 0
            row = conn.execute(
                text(f"SELECT * FROM ({DAILY_RANKED}) ranked WHERE player_id = :player_id"),
                {"day": today, "player_id": payload.player_id},
            ).mappings().one()
    except IntegrityError:
        raise HTTPException(status_code=404, detail="player not found")

    return {
        "date": today.isoformat(),
        "category_id": category_id,
        "score": row["score"],
        "correct_count": row["correct_count"],
        "total_count": payload.total_count,
        "rank": row["rank"],
        "already_played": inserted is None,
        "pass_xp": pass_xp,
    }


# --- Battle pass ---------------------------------------------------------------
# Writes are keyed by device_id (like registration), so nobody can claim for another player.

def _player_for_device(conn, device_id: str) -> str:
    row = conn.execute(text("SELECT id FROM players WHERE device_id = :d"), {"d": device_id}).first()
    if row is None:
        raise HTTPException(status_code=404, detail="player not found")
    return str(row[0])


@app.get("/pass")
def pass_state(device_id: str = Query(min_length=1, max_length=128)):
    with engine.begin() as conn:
        return battle_pass.state(conn, _player_for_device(conn, device_id))


@app.post("/pass/claim")
def pass_claim(payload: PassClaim):
    with engine.begin() as conn:
        player_id = _player_for_device(conn, payload.device_id)
        try:
            reward = battle_pass.claim_reward(conn, player_id, payload.tier, payload.track)
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error))
    return {"tier": payload.tier, "track": payload.track, "reward": reward}


@app.post("/pass/quest")
def pass_quest(payload: PassQuest):
    with engine.begin() as conn:
        player_id = _player_for_device(conn, payload.device_id)
        gained = battle_pass.claim_quest(conn, player_id, payload.quest_id, payload.day)
    return {"pass_xp": gained}


@app.post("/pass/premium")
def pass_premium(payload: PassPremium):
    with engine.begin() as conn:
        player_id = _player_for_device(conn, payload.device_id)
        if not battle_pass.unlock_premium(conn, player_id, payload.receipt):
            raise HTTPException(status_code=402, detail="purchase not verified")
        return battle_pass.state(conn, player_id)


@app.get("/daily-challenge/leaderboard", response_model=DailyLeaderboard)
def daily_leaderboard(player_id: UUID | None = None, limit: int = Query(50, ge=1, le=100)):
    today, category_id = _today_daily()
    with engine.connect() as conn:
        entries = conn.execute(
            text(f"SELECT * FROM ({DAILY_RANKED}) ranked ORDER BY rank LIMIT :limit"),
            {"day": today, "limit": limit},
        ).mappings().all()
        total = conn.execute(
            text("SELECT COUNT(*) FROM daily_results WHERE day = :day"), {"day": today}
        ).scalar_one()
        player_rank = None
        if player_id is not None:
            mine = conn.execute(
                text(f"SELECT rank FROM ({DAILY_RANKED}) ranked WHERE player_id = :player_id"),
                {"day": today, "player_id": player_id},
            ).first()
            player_rank = mine[0] if mine else None
    return {
        "date": today.isoformat(),
        "category_id": category_id,
        "total_players": total,
        "player_rank": player_rank,
        "entries": [dict(entry) for entry in entries],
    }


@app.post("/challenges", response_model=Challenge)
def create_challenge(payload: ChallengeCreate):
    with engine.connect() as conn:
        exists = conn.execute(
            text("SELECT 1 FROM players WHERE id = :id"), {"id": str(payload.challenger_id)}
        ).first()
    if exists is None:
        raise HTTPException(status_code=404, detail="challenger not found")

    for _ in range(5):
        code = _generate_code()
        try:
            with engine.begin() as conn:
                row = conn.execute(
                    text(
                        f"""
                        INSERT INTO challenges (code, category, challenger_id)
                        VALUES (:code, :category, :challenger_id)
                        RETURNING {CHALLENGE_COLUMNS}
                        """
                    ),
                    {
                        "code": code,
                        "category": payload.category,
                        "challenger_id": str(payload.challenger_id),
                    },
                ).mappings().one()
            return row
        except IntegrityError:
            continue
    raise HTTPException(status_code=500, detail="could not generate a unique challenge code")


@app.post("/challenges/{code}/join", response_model=Challenge)
def join_challenge(code: str, payload: ChallengeJoin):
    with engine.begin() as conn:
        challenge = conn.execute(
            text(f"SELECT {CHALLENGE_COLUMNS} FROM challenges WHERE code = :code"),
            {"code": code},
        ).mappings().first()
        if challenge is None:
            raise HTTPException(status_code=404, detail="challenge not found")
        if challenge["status"] != "pending":
            raise HTTPException(status_code=409, detail="challenge is not open to join")
        if str(challenge["challenger_id"]) == str(payload.player_id):
            raise HTTPException(status_code=400, detail="cannot join your own challenge")

        row = conn.execute(
            text(
                f"""
                UPDATE challenges
                SET opponent_id = :opponent_id, status = 'accepted'
                WHERE code = :code
                RETURNING {CHALLENGE_COLUMNS}
                """
            ),
            {"opponent_id": str(payload.player_id), "code": code},
        ).mappings().one()
    return row


@app.post("/challenges/{code}/result", response_model=Challenge)
def submit_challenge_result(code: str, payload: ChallengeResult):
    with engine.begin() as conn:
        challenge = conn.execute(
            text(f"SELECT {CHALLENGE_COLUMNS} FROM challenges WHERE code = :code"),
            {"code": code},
        ).mappings().first()
        if challenge is None:
            raise HTTPException(status_code=404, detail="challenge not found")
        if challenge["status"] not in ("accepted", "completed"):
            raise HTTPException(status_code=400, detail="challenge not yet accepted by an opponent")

        player_id = str(payload.player_id)
        if player_id == str(challenge["challenger_id"]):
            side = "challenger"
        elif challenge["opponent_id"] is not None and player_id == str(challenge["opponent_id"]):
            side = "opponent"
        else:
            raise HTTPException(status_code=403, detail="player is not part of this challenge")

        row = conn.execute(
            text(
                f"""
                UPDATE challenges
                SET {side}_score = :score,
                    {side}_correct_count = :correct_count,
                    status = CASE
                        WHEN (challenger_score IS NOT NULL OR :side = 'challenger')
                         AND (opponent_score IS NOT NULL OR :side = 'opponent')
                        THEN 'completed'
                        ELSE status
                    END
                WHERE code = :code
                RETURNING {CHALLENGE_COLUMNS}
                """
            ),
            {
                "score": payload.score,
                "correct_count": payload.correct_count,
                "code": code,
                "side": side,
            },
        ).mappings().one()
    return row


@app.get("/challenges/{code}", response_model=Challenge)
def get_challenge(code: str):
    with engine.connect() as conn:
        row = conn.execute(
            text(f"SELECT {CHALLENGE_COLUMNS} FROM challenges WHERE code = :code"),
            {"code": code},
        ).mappings().first()
    if row is None:
        raise HTTPException(status_code=404, detail="challenge not found")
    return row


# --- Friends ------------------------------------------------------------------

def _social(action):
    """Runs a friends action in one transaction and maps its refusals to HTTP errors."""
    try:
        with engine.begin() as conn:
            return action(conn)
    except friends.SocialError as error:
        raise HTTPException(status_code=error.status, detail=error.reason)


@app.get("/social")
def social_overview(device_id: str = Query(min_length=1, max_length=128), busy: bool = False):
    return _social(lambda conn: friends.overview(conn, _player_for_device(conn, device_id), busy))


@app.get("/players/search")
def search_players(device_id: str = Query(min_length=1, max_length=128), q: str = Query("", max_length=40)):
    return _social(lambda conn: friends.search(conn, _player_for_device(conn, device_id), q))


@app.post("/friends/requests")
def send_friend_request(payload: FriendTarget):
    return _social(lambda conn: friends.send_request(
        conn, _player_for_device(conn, payload.device_id), str(payload.player_id)))


@app.post("/friends/requests/{request_id}/accept")
def accept_friend_request(request_id: UUID, payload: DeviceOnly):
    return _social(lambda conn: friends.answer_request(
        conn, _player_for_device(conn, payload.device_id), str(request_id), True) or {"status": "friends"})


@app.post("/friends/requests/{request_id}/decline")
def decline_friend_request(request_id: UUID, payload: DeviceOnly):
    return _social(lambda conn: friends.answer_request(
        conn, _player_for_device(conn, payload.device_id), str(request_id), False) or {"status": "declined"})


@app.post("/friends/remove")
def remove_friend(payload: FriendTarget):
    return _social(lambda conn: friends.remove_friend(
        conn, _player_for_device(conn, payload.device_id), str(payload.player_id)) or {"status": "removed"})


@app.post("/friends/challenges")
def send_friend_challenge(payload: FriendChallengeCreate):
    return _social(lambda conn: friends.send_challenge(
        conn, _player_for_device(conn, payload.device_id), str(payload.friend_id), payload.mode))


@app.post("/friends/challenges/{challenge_id}/accept")
def accept_friend_challenge(challenge_id: UUID, payload: DeviceOnly):
    return _social(lambda conn: friends.answer_challenge(
        conn, _player_for_device(conn, payload.device_id), str(challenge_id), True))


@app.post("/friends/challenges/{challenge_id}/decline")
def decline_friend_challenge(challenge_id: UUID, payload: DeviceOnly):
    return _social(lambda conn: friends.answer_challenge(
        conn, _player_for_device(conn, payload.device_id), str(challenge_id), False))
