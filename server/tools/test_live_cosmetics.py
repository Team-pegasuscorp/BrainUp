"""Checks that each live player receives the other's look (avatar / frame / banner).
Needs the stack running (docker compose up) and `pip install websockets`.
Usage: python tools/test_live_cosmetics.py"""
import asyncio, json, urllib.request, uuid, websockets
API="http://localhost:8000"; WS="ws://localhost:8000/ws/live"
def reg(dev, name, cos):
    req=urllib.request.Request(API+"/players", data=json.dumps({"device_id":dev,"display_name":name,"cosmetics":cos}).encode(), headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req))["id"]
async def play(pid):
    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({"type":"join_queue","player_id":pid,"category":"sport","locale":"fr","trophies":100}))
        while True:
            m=json.loads(await ws.recv())
            if m["type"]=="match_found": return m
async def main():
    a=reg("cosm-a-"+uuid.uuid4().hex[:6],"Alpha",{"avatar":"theo","frame":"frame_royal","banner":"banner_gold"})
    b=reg("cosm-b-"+uuid.uuid4().hex[:6],"Beta",{"avatar":"maya","frame":"","banner":"banner_candy"})
    ra,rb=await asyncio.gather(play(a),play(b))
    ok = rb["opponent_cosmetics"]["banner"] == "banner_gold" and ra["opponent_cosmetics"]["avatar"] == "maya"
    print(("PASS" if ok else "FAIL") + " opponent cosmetics in match_found", ra["opponent_cosmetics"], rb["opponent_cosmetics"])
    raise SystemExit(0 if ok else 1)
asyncio.run(main())
