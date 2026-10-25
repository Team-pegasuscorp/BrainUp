"""Per-player and per-IP request limits (token buckets, in memory).

One uvicorn process serves the API, so a dict is enough: no Redis. A request spends one
token from its player's bucket (device_id / player_id found in the query or JSON body)
and one from its IP's bucket; an empty bucket answers 429 with Retry-After.

The IP ceiling is high on purpose: mobile carriers put many players behind one address
(CGNAT). It only stops a client that invents a new device_id on every call.

RATE_LIMIT_ENABLED=0 turns everything off (local stack and the tools/ test suites).
"""
import json
import math
import os
import time
from urllib.parse import parse_qs

## (tokens per minute, burst). The game polls /social every 5 s on that tab and every
## 15 s elsewhere: about 15 calls a minute for a normal session.
PLAYER_LIMIT = (120, 40)
## Writes that pay coins, cost a Google call or touch other players.
SENSITIVE_LIMIT = (20, 10)
IP_LIMIT = (600, 200)

SENSITIVE_ROUTES = {
    ("POST", "/players"),
    ("POST", "/players/play_games"),
    ("POST", "/shop/buy"),
    ("POST", "/shop/joker"),
    ("POST", "/ads/reward"),
    ("POST", "/pass/claim"),
    ("POST", "/pass/premium"),
    ("POST", "/jokers/use"),
    ("POST", "/friends/requests"),
    ("POST", "/friends/challenges"),
    ("POST", "/challenges"),
    ("GET", "/players/search"),
}
EXEMPT_PATHS = {"/health"}
## Bodies above this are not parsed for an id (the IP bucket still applies).
MAX_BODY_SCAN = 64 * 1024
## Forget buckets idle this long (they would be full again anyway).
IDLE_SECONDS = 600.0


class _Bucket:
    __slots__ = ("tokens", "stamp")

    def __init__(self, burst: float, now: float) -> None:
        self.tokens = burst
        self.stamp = now


class Limiter:
    def __init__(self, clock=time.monotonic) -> None:
        self._clock = clock
        self._buckets: dict[tuple, _Bucket] = {}
        self._last_prune = clock()

    def take(self, key: tuple, limit: tuple[int, int]) -> float:
        """Spends one token. Returns 0 when allowed, else the seconds to wait."""
        per_minute, burst = limit
        rate = per_minute / 60.0
        now = self._clock()
        bucket = self._buckets.get(key)
        if bucket is None:
            bucket = self._buckets[key] = _Bucket(burst, now)
        else:
            bucket.tokens = min(burst, bucket.tokens + (now - bucket.stamp) * rate)
            bucket.stamp = now
        if bucket.tokens >= 1.0:
            bucket.tokens -= 1.0
            self._maybe_prune(now)
            return 0.0
        return (1.0 - bucket.tokens) / rate

    def _maybe_prune(self, now: float) -> None:
        if now - self._last_prune < IDLE_SECONDS:
            return
        self._last_prune = now
        stale = [key for key, bucket in self._buckets.items() if now - bucket.stamp > IDLE_SECONDS]
        for key in stale:
            del self._buckets[key]


def _player_key(query: dict, body: bytes) -> str:
    for name in ("device_id", "player_id"):
        values = query.get(name)
        if values and values[0]:
            return values[0]
    if body and len(body) <= MAX_BODY_SCAN:
        try:
            parsed = json.loads(body)
        except ValueError:
            return ""
        if isinstance(parsed, dict):
            for name in ("device_id", "player_id"):
                value = parsed.get(name)
                if isinstance(value, str) and value:
                    return value
    return ""


class RateLimitMiddleware:
    """Pure ASGI: reads the body once and replays it to the app."""

    def __init__(self, app, limiter: Limiter | None = None, enabled: bool | None = None) -> None:
        self.app = app
        self.limiter = limiter or Limiter()
        if enabled is None:
            enabled = os.environ.get("RATE_LIMIT_ENABLED", "1") != "0"
        self.enabled = enabled

    async def __call__(self, scope, receive, send):
        if not self.enabled or scope["type"] != "http" or scope["path"] in EXEMPT_PATHS:
            await self.app(scope, receive, send)
            return

        body = b""
        messages = []
        if scope["method"] in ("POST", "PUT", "PATCH"):
            while True:
                message = await receive()
                messages.append(message)
                if message["type"] != "http.request":
                    break
                body += message.get("body", b"")
                if not message.get("more_body", False) or len(body) > MAX_BODY_SCAN:
                    break

        query = parse_qs(scope.get("query_string", b"").decode("latin-1"))
        client = scope.get("client")
        ip = client[0] if client else "unknown"
        route = (scope["method"], scope["path"])
        limit = SENSITIVE_LIMIT if route in SENSITIVE_ROUTES else PLAYER_LIMIT

        wait = self.limiter.take(("ip", ip), IP_LIMIT)
        player = _player_key(query, body)
        if not wait and player:
            bucket = ("sensitive", route, player) if limit is SENSITIVE_LIMIT else ("player", player)
            wait = self.limiter.take(bucket, limit)
        if wait:
            await _too_many(send, wait)
            return

        async def replay():
            if messages:
                return messages.pop(0)
            return await receive()

        await self.app(scope, replay, send)


async def _too_many(send, wait: float) -> None:
    payload = json.dumps({"detail": "rate_limited"}).encode()
    await send({
        "type": "http.response.start",
        "status": 429,
        "headers": [
            (b"content-type", b"application/json"),
            (b"content-length", str(len(payload)).encode()),
            (b"retry-after", str(max(1, math.ceil(wait))).encode()),
        ],
    })
    await send({"type": "http.response.body", "body": payload})
