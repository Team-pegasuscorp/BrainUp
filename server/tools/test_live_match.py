import asyncio
import json
import sys

import websockets

URL = "ws://localhost:8000/ws/live"


async def play(player_id: str, category: str, answer_index: int, label: str) -> dict:
    async with websockets.connect(URL) as ws:
        await ws.send(json.dumps({
            "type": "join_queue",
            "player_id": player_id,
            "category": category,
            "locale": "fr",
        }))
        final = {}
        while True:
            raw = await ws.recv()
            msg = json.loads(raw)
            print(f"[{label}] {msg['type']}: {msg}")
            if msg["type"] == "question":
                await ws.send(json.dumps({
                    "type": "answer",
                    "index": msg["index"],
                    "selected_index": answer_index,
                }))
            elif msg["type"] == "match_over":
                final = msg
                break
            elif msg["type"] == "match_aborted":
                final = msg
                break
        return final


async def main() -> None:
    p1, p2 = sys.argv[1], sys.argv[2]
    results = await asyncio.gather(
        play(p1, "sport", 2, "P1"),
        play(p2, "sport", 0, "P2"),
    )
    print("RESULT P1:", results[0])
    print("RESULT P2:", results[1])


asyncio.run(main())
