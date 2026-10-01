import asyncio
import json
import sys

import websockets

URL = "ws://localhost:8000/ws/live"


async def main() -> None:
    player_id, category = sys.argv[1], sys.argv[2]
    async with websockets.connect(URL) as ws:
        await ws.send(json.dumps({
            "type": "join_queue",
            "player_id": player_id,
            "category": category,
            "locale": "fr",
        }))
        while True:
            raw = await ws.recv()
            msg = json.loads(raw)
            print(f"[opponent] {msg['type']}: {msg}")
            if msg["type"] == "question":
                await ws.send(json.dumps({
                    "type": "answer",
                    "index": msg["index"],
                    "selected_index": 1,
                }))
            elif msg["type"] in ("match_over", "match_aborted"):
                break


asyncio.run(main())
