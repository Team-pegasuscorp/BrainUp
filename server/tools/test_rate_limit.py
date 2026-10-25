"""Checks the request limits of app/rate_limit.py without a server: token buckets on a fake
clock, then the ASGI middleware around a dummy app (player id from query or JSON body,
sensitive routes, per-IP ceiling, 429 + Retry-After, body replayed to the app, exemptions).
Usage: python tools/test_rate_limit.py  (instant)"""
import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import rate_limit  # noqa: E402
from rate_limit import Limiter, RateLimitMiddleware  # noqa: E402

failures = []


def check(label: str, ok: bool, detail="") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(label)


class Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


# --- Buckets -------------------------------------------------------------------------

clock = Clock()
limiter = Limiter(clock)
limit = (60, 5)  # 1 token a second, burst 5
allowed = sum(1 for _ in range(8) if limiter.take(("k",), limit) == 0)
check("burst then refused", allowed == 5, f"allowed={allowed}")
wait = limiter.take(("k",), limit)
check("wait time ~1 s", 0.9 < wait <= 1.0, f"wait={wait:.2f}")
clock.now += 2.0
check("refills with time", limiter.take(("k",), limit) == 0 and limiter.take(("k",), limit) == 0)
check("other key untouched", limiter.take(("other",), limit) == 0)
clock.now += 10_000
limiter.take(("fresh",), limit)
check("idle buckets pruned", ("k",) not in limiter._buckets and ("fresh",) in limiter._buckets)


# --- Middleware ----------------------------------------------------------------------

seen_bodies = []


async def dummy_app(scope, receive, send):
    body = b""
    while True:
        message = await receive()
        body += message.get("body", b"")
        if not message.get("more_body", False):
            break
    seen_bodies.append(body)
    await send({"type": "http.response.start", "status": 200, "headers": []})
    await send({"type": "http.response.body", "body": b"{}"})


def call(mw, method, path, query="", body=None, ip="1.2.3.4"):
    raw = json.dumps(body).encode() if body is not None else b""
    scope = {"type": "http", "method": method, "path": path,
             "query_string": query.encode(), "client": (ip, 5555), "headers": []}
    sent = []
    chunks = [{"type": "http.request", "body": raw, "more_body": False}]

    async def receive():
        return chunks.pop(0) if chunks else {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    asyncio.run(mw(scope, receive, send))
    start = sent[0]
    headers = dict(start.get("headers", []))
    return start["status"], headers


def fresh(enabled=True):
    return RateLimitMiddleware(dummy_app, Limiter(Clock()), enabled=enabled)


mw = fresh()
burst = rate_limit.PLAYER_LIMIT[1]
codes = [call(mw, "GET", "/social", "device_id=A")[0] for _ in range(burst + 1)]
check("GET by device_id: burst allowed", codes[:burst] == [200] * burst)
check("GET by device_id: then 429", codes[-1] == 429)
status, headers = call(mw, "GET", "/social", "device_id=A")
check("Retry-After header", status == 429 and int(headers.get(b"retry-after", b"0")) >= 1)
check("other player unaffected", call(mw, "GET", "/social", "device_id=B")[0] == 200)

mw = fresh()
s_burst = rate_limit.SENSITIVE_LIMIT[1]
codes = [call(mw, "POST", "/shop/buy", body={"device_id": "C", "item_id": "x"})[0] for _ in range(s_burst + 1)]
check("sensitive route: lower burst", codes[:s_burst] == [200] * s_burst and codes[-1] == 429)
check("sensitive limit is per route", call(mw, "POST", "/ads/reward", body={"device_id": "C", "day": "d"})[0] == 200)
check("normal calls still fine", call(mw, "GET", "/shop", "device_id=C")[0] == 200)

seen_bodies.clear()
mw = fresh()
call(mw, "POST", "/players", body={"device_id": "D", "display_name": "Zoé"})
check("body replayed to the app", seen_bodies and json.loads(seen_bodies[0])["display_name"] == "Zoé")

mw = fresh()
ip_burst = rate_limit.IP_LIMIT[1]
codes = [call(mw, "GET", "/social", f"device_id=rot-{i}", ip="9.9.9.9")[0] for i in range(ip_burst + 1)]
check("rotating device_ids hit the IP ceiling", codes[-1] == 429 and codes[:ip_burst].count(200) == ip_burst)
check("another IP unaffected", call(mw, "GET", "/social", "device_id=rot-x", ip="8.8.8.8")[0] == 200)

mw = fresh()
codes = [call(mw, "GET", "/health")[0] for _ in range(rate_limit.IP_LIMIT[1] + 5)]
check("/health exempt", set(codes) == {200})

mw = fresh(enabled=False)
codes = [call(mw, "GET", "/social", "device_id=E")[0] for _ in range(burst * 3)]
check("RATE_LIMIT_ENABLED=0 disables", set(codes) == {200})

print()
print("ALL PASS" if not failures else f"{len(failures)} FAILURE(S): {failures}")
sys.exit(1 if failures else 0)
