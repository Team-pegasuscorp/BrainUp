"""Friends: search, requests, friend list with presence, and friend duel invites.

Presence is "seen recently": every /social poll (the app polls while it is open)
refreshes players.last_seen_at. A duel invite can only be accepted while the
challenger is online, then both phones join the private room on /ws/live
(see live_match.handle_live_socket, join message "join_friend")."""
from datetime import datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.engine import Connection

ONLINE_SECONDS = 45
## Seen within this window but not right now: shown as "away".
AWAY_SECONDS = 15 * 60
## A category needs this many answered questions before it can be someone's best.
BEST_CATEGORY_MIN_ANSWERS = 10
CHALLENGE_HOURS = 4
## An accepted invite must be joined quickly by both phones.
ACCEPTED_JOIN_SECONDS = 120
MAX_FRIENDS = 200
SEARCH_LIMIT = 20
MODES = ("classic", "survival", "time_attack")


class SocialError(Exception):
    """Refused action; `reason` is a short code the client maps to a message."""

    def __init__(self, reason: str, status: int = 409):
        super().__init__(reason)
        self.reason = reason
        self.status = status


def touch(conn: Connection, player_id: str, busy: bool = False) -> None:
    conn.execute(
        text("""UPDATE players SET last_seen_at = now(),
                busy_until = CASE WHEN :busy THEN now() + make_interval(secs => :s) ELSE NULL END
                WHERE id = :id"""),
        {"id": player_id, "busy": busy, "s": ONLINE_SECONDS},
    )


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _summary(row) -> dict:
    seen = row["last_seen_at"]
    age = (_now() - seen).total_seconds() if seen is not None else None
    online = age is not None and age <= ONLINE_SECONDS
    return {
        "id": str(row["id"]),
        "name": row["display_name"],
        "level": int(row["level"]),
        "cosmetics": row["cosmetics"] or {},
        "trophies": int(row["trophies"]),
        "online": online,
        "presence": "online" if online else ("away" if age is not None and age <= AWAY_SECONDS else "offline"),
    }


_PLAYER_COLUMNS = "p.id, p.display_name, p.level, p.cosmetics, p.trophies, p.last_seen_at"


def are_friends(conn: Connection, a: str, b: str) -> bool:
    return conn.execute(
        text("SELECT 1 FROM friendships WHERE player_id = :a AND friend_id = :b"), {"a": a, "b": b}
    ).first() is not None


def _make_friends(conn: Connection, a: str, b: str) -> None:
    conn.execute(
        text("""INSERT INTO friendships (player_id, friend_id) VALUES (:a, :b), (:b, :a)
                ON CONFLICT DO NOTHING"""),
        {"a": a, "b": b},
    )
    conn.execute(
        text("DELETE FROM friend_requests WHERE (from_id = :a AND to_id = :b) OR (from_id = :b AND to_id = :a)"),
        {"a": a, "b": b},
    )


def _expire_challenges(conn: Connection) -> None:
    conn.execute(text("UPDATE friend_challenges SET status = 'expired' WHERE status = 'pending' AND expires_at < now()"))
    conn.execute(
        text("""UPDATE friend_challenges SET status = 'expired'
                WHERE status = 'accepted' AND accepted_at < now() - make_interval(secs => :s)"""),
        {"s": ACCEPTED_JOIN_SECONDS},
    )


def search(conn: Connection, me: str, query: str) -> list[dict]:
    query = query.strip()
    if len(query) < 2:
        return []
    pattern = query.lower().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
    rows = conn.execute(
        text(f"""SELECT {_PLAYER_COLUMNS},
                    EXISTS (SELECT 1 FROM friendships f WHERE f.player_id = :me AND f.friend_id = p.id) AS is_friend,
                    EXISTS (SELECT 1 FROM friend_requests r WHERE r.from_id = :me AND r.to_id = p.id) AS request_sent,
                    EXISTS (SELECT 1 FROM friend_requests r WHERE r.from_id = p.id AND r.to_id = :me) AS request_received
                 FROM players p
                 WHERE lower(p.display_name) LIKE :pattern AND p.id <> :me
                 ORDER BY lower(p.display_name) = lower(:exact) DESC, p.last_seen_at DESC
                 LIMIT :limit"""),
        {"me": me, "pattern": pattern, "exact": query, "limit": SEARCH_LIMIT},
    ).mappings().all()
    return [
        {**_summary(row), "is_friend": row["is_friend"], "request_sent": row["request_sent"],
         "request_received": row["request_received"]}
        for row in rows
    ]


def send_request(conn: Connection, me: str, target: str) -> dict:
    """Returns {"status": "sent"} or {"status": "friends"} when the target had already asked us."""
    if me == target:
        raise SocialError("self")
    if conn.execute(text("SELECT 1 FROM players WHERE id = :id"), {"id": target}).first() is None:
        raise SocialError("not_found", 404)
    if are_friends(conn, me, target):
        raise SocialError("already_friends")
    reverse = conn.execute(
        text("SELECT id FROM friend_requests WHERE from_id = :t AND to_id = :me"), {"t": target, "me": me}
    ).first()
    if reverse is not None:
        _check_room(conn, me, target)
        _make_friends(conn, me, target)
        return {"status": "friends"}
    conn.execute(
        text("INSERT INTO friend_requests (from_id, to_id) VALUES (:me, :t) ON CONFLICT DO NOTHING"),
        {"me": me, "t": target},
    )
    return {"status": "sent"}


def _check_room(conn: Connection, *players: str) -> None:
    for player in players:
        count = conn.execute(
            text("SELECT count(*) FROM friendships WHERE player_id = :p"), {"p": player}
        ).scalar_one()
        if count >= MAX_FRIENDS:
            raise SocialError("too_many_friends")


def answer_request(conn: Connection, me: str, request_id: str, accept: bool) -> None:
    """The receiver accepts or declines; the sender may also cancel (decline) its own request."""
    row = conn.execute(
        text("SELECT from_id, to_id FROM friend_requests WHERE id = :id FOR UPDATE"), {"id": request_id}
    ).first()
    if row is None:
        raise SocialError("not_found", 404)
    from_id, to_id = str(row[0]), str(row[1])
    if me not in (from_id, to_id) or (accept and me != to_id):
        raise SocialError("forbidden", 403)
    if accept:
        _check_room(conn, from_id, to_id)
        _make_friends(conn, from_id, to_id)
    else:
        conn.execute(text("DELETE FROM friend_requests WHERE id = :id"), {"id": request_id})


def remove_friend(conn: Connection, me: str, friend: str) -> None:
    conn.execute(
        text("""DELETE FROM friendships WHERE (player_id = :a AND friend_id = :b)
                OR (player_id = :b AND friend_id = :a)"""),
        {"a": me, "b": friend},
    )
    conn.execute(
        text("""UPDATE friend_challenges SET status = 'cancelled' WHERE status IN ('pending', 'accepted')
                AND ((from_id = :a AND to_id = :b) OR (from_id = :b AND to_id = :a))"""),
        {"a": me, "b": friend},
    )


def send_challenge(conn: Connection, me: str, friend: str, mode: str) -> dict:
    if mode not in MODES:
        raise SocialError("bad_mode", 422)
    if not are_friends(conn, me, friend):
        raise SocialError("not_friends", 403)
    ## One open invite per pair and direction: a new one replaces the old.
    conn.execute(
        text("""UPDATE friend_challenges SET status = 'cancelled'
                WHERE from_id = :me AND to_id = :f AND status = 'pending'"""),
        {"me": me, "f": friend},
    )
    row = conn.execute(
        text("""INSERT INTO friend_challenges (from_id, to_id, mode, expires_at)
                VALUES (:me, :f, :mode, now() + make_interval(hours => :h))
                RETURNING id, mode, status, created_at, expires_at"""),
        {"me": me, "f": friend, "mode": mode, "h": CHALLENGE_HOURS},
    ).mappings().one()
    return _challenge_dict(row)


def answer_challenge(conn: Connection, me: str, challenge_id: str, accept: bool) -> dict:
    _expire_challenges(conn)
    row = conn.execute(
        text("""SELECT c.id, c.from_id, c.to_id, c.mode, c.status, c.created_at, c.expires_at,
                       p.last_seen_at AS challenger_seen, p.busy_until AS challenger_busy_until
                FROM friend_challenges c JOIN players p ON p.id = c.from_id
                WHERE c.id = :id FOR UPDATE OF c"""),
        {"id": challenge_id},
    ).mappings().first()
    if row is None:
        raise SocialError("not_found", 404)
    from_id, to_id = str(row["from_id"]), str(row["to_id"])
    if me not in (from_id, to_id) or (accept and me != to_id):
        raise SocialError("forbidden", 403)
    if row["status"] != "pending":
        raise SocialError(row["status"])
    if not accept:
        status = "cancelled" if me == from_id else "declined"
        conn.execute(text("UPDATE friend_challenges SET status = :s WHERE id = :id"), {"s": status, "id": challenge_id})
        return {**_challenge_dict(row), "status": status}
    seen = row["challenger_seen"]
    if seen is None or (_now() - seen).total_seconds() > ONLINE_SECONDS:
        raise SocialError("challenger_offline")
    busy_until = row["challenger_busy_until"]
    if busy_until is not None and busy_until > _now():
        raise SocialError("challenger_busy")
    conn.execute(
        text("UPDATE friend_challenges SET status = 'accepted', accepted_at = now() WHERE id = :id"),
        {"id": challenge_id},
    )
    return {**_challenge_dict(row), "status": "accepted"}


def seat_for_live(conn: Connection, me: str, challenge_id: str) -> dict | None:
    """Checks a join_friend: the invite is accepted, recent, and `me` is one of its two players."""
    _expire_challenges(conn)
    row = conn.execute(
        text("SELECT from_id, to_id, mode, status FROM friend_challenges WHERE id = :id"), {"id": challenge_id}
    ).mappings().first()
    if row is None or row["status"] != "accepted" or me not in (str(row["from_id"]), str(row["to_id"])):
        return None
    return {"mode": row["mode"], "from_id": str(row["from_id"]), "to_id": str(row["to_id"])}


def set_challenge_status(conn: Connection, challenge_id: str, status: str) -> None:
    conn.execute(
        text("UPDATE friend_challenges SET status = :s WHERE id = :id AND status = 'accepted'"),
        {"s": status, "id": challenge_id},
    )


def _challenge_dict(row, id_key: str = "id") -> dict:
    return {
        "id": str(row[id_key]),
        "mode": row["mode"],
        "status": row["status"],
        "created_at": row["created_at"].isoformat(),
        "expires_in": max(int((row["expires_at"] - _now()).total_seconds()), 0),
    }


def _friend_stats(conn: Connection, ids: list[str]) -> dict:
    """Ranked duel stats for the friend cards: wins, best category (accuracy), last match."""
    if not ids:
        return {}
    stats = {player_id: {"wins": 0} for player_id in ids}
    for row in conn.execute(
        text("""SELECT player_id, category, sum(correct_count) AS correct, sum(total_count) AS total,
                       count(*) FILTER (WHERE won) AS wins
                FROM matches WHERE player_id = ANY(CAST(:ids AS uuid[]))
                GROUP BY player_id, category"""),
        {"ids": ids},
    ).mappings():
        entry = stats[str(row["player_id"])]
        entry["wins"] += int(row["wins"])
        total = int(row["total"] or 0)
        if total < BEST_CATEGORY_MIN_ANSWERS:
            continue
        accuracy = round(100.0 * int(row["correct"] or 0) / total, 1)
        if accuracy > entry.get("best_accuracy", -1.0):
            entry["best_category_id"] = row["category"]
            entry["best_accuracy"] = accuracy
    for row in conn.execute(
        text("""SELECT DISTINCT ON (player_id) player_id, category, won FROM matches
                WHERE player_id = ANY(CAST(:ids AS uuid[])) ORDER BY player_id, played_at DESC"""),
        {"ids": ids},
    ).mappings():
        stats[str(row["player_id"])].update(last_category_id=row["category"], last_won=row["won"])
    return stats


def overview(conn: Connection, me: str, busy: bool = False) -> dict:
    """Everything the Social tab shows. Also counts as a presence ping (`busy`: in a game)."""
    touch(conn, me, busy)
    _expire_challenges(conn)
    friends = conn.execute(
        text(f"""SELECT {_PLAYER_COLUMNS} FROM friendships f JOIN players p ON p.id = f.friend_id
                 WHERE f.player_id = :me ORDER BY p.last_seen_at DESC"""),
        {"me": me},
    ).mappings().all()
    requests_in = conn.execute(
        text(f"""SELECT r.id AS request_id, {_PLAYER_COLUMNS} FROM friend_requests r
                 JOIN players p ON p.id = r.from_id WHERE r.to_id = :me ORDER BY r.created_at DESC"""),
        {"me": me},
    ).mappings().all()
    requests_out = conn.execute(
        text(f"""SELECT r.id AS request_id, {_PLAYER_COLUMNS} FROM friend_requests r
                 JOIN players p ON p.id = r.to_id WHERE r.from_id = :me ORDER BY r.created_at DESC"""),
        {"me": me},
    ).mappings().all()
    challenges_in = conn.execute(
        text(f"""SELECT c.id AS challenge_id, c.mode, c.status, c.created_at, c.expires_at, {_PLAYER_COLUMNS}
                 FROM friend_challenges c JOIN players p ON p.id = c.from_id
                 WHERE c.to_id = :me AND c.status IN ('pending', 'accepted') ORDER BY c.created_at DESC"""),
        {"me": me},
    ).mappings().all()
    challenges_out = conn.execute(
        text(f"""SELECT c.id AS challenge_id, c.mode, c.status, c.created_at, c.expires_at, {_PLAYER_COLUMNS}
                 FROM friend_challenges c JOIN players p ON p.id = c.to_id
                 WHERE c.from_id = :me AND c.status IN ('pending', 'accepted') ORDER BY c.created_at DESC"""),
        {"me": me},
    ).mappings().all()
    stats = _friend_stats(conn, [str(row["id"]) for row in friends])
    return {
        "friends": [{**_summary(row), **stats.get(str(row["id"]), {})} for row in friends],
        "requests_in": [{"id": str(row["request_id"]), "player": _summary(row)} for row in requests_in],
        "requests_out": [{"id": str(row["request_id"]), "player": _summary(row)} for row in requests_out],
        "challenges_in": [{**_challenge_dict(row, "challenge_id"), "player": _summary(row)} for row in challenges_in],
        "challenges_out": [{**_challenge_dict(row, "challenge_id"), "player": _summary(row)} for row in challenges_out],
    }
