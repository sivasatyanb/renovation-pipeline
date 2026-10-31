import asyncio
import base64
import json
from pathlib import Path
import requests
import websockets

ARTIFACTS_DIR = Path(r"C:\Users\sivas\.gemini\antigravity\brain\e81a0bf9-2fcf-4b7e-8bcb-2803c61fbf60")

async def send_cmd(ws, msg_id, method, params=None):
    payload = {"id": msg_id, "method": method, "params": params or {}}
    await ws.send(json.dumps(payload))
    while True:
        resp = json.loads(await ws.recv())
        if resp.get("id") == msg_id:
            return resp

async def take_screenshot(ws, msg_id, filename):
    resp = await send_cmd(ws, msg_id, "Page.captureScreenshot", {"format": "png"})
    data = base64.b64decode(resp["result"]["data"])
    out_path = ARTIFACTS_DIR / filename
    out_path.write_bytes(data)
    print(f"Saved {filename} ({len(data)} bytes, {out_path})")

async def scroll(ws, msg_id, delta_y):
    await send_cmd(ws, msg_id, "Input.dispatchMouseEvent", {
        "type": "mouseWheel",
        "x": 195,
        "y": 400,
        "deltaX": 0,
        "deltaY": delta_y,
    })
    await asyncio.sleep(0.8)

async def main():
    pages = requests.get("http://127.0.0.1:9222/json/list").json()
    page = next(p for p in pages if "RenovAI" in p.get("title", ""))
    ws_url = page["webSocketDebuggerUrl"]
    print("Connected to:", ws_url)

    async with websockets.connect(ws_url) as ws:
        msg_id = 1
        # Set 390x844 viewport
        await send_cmd(ws, msg_id, "Emulation.setDeviceMetricsOverride", {
            "width": 390,
            "height": 844,
            "deviceScaleFactor": 1,
            "mobile": True
        })
        msg_id += 1

        # 1. Screen 1: Start screen
        print("1. Capturing screen_1_start.png...")
        await send_cmd(ws, msg_id, "Page.navigate", {"url": "http://127.0.0.1:8080/?screen=start"})
        msg_id += 1
        await asyncio.sleep(2.5)
        await take_screenshot(ws, msg_id, "screen_1_start.png")
        msg_id += 1

        # 2. Screen 2: Quiz screen
        print("2. Capturing screen_2_quiz.png...")
        await send_cmd(ws, msg_id, "Page.navigate", {"url": "http://127.0.0.1:8080/?screen=quiz"})
        msg_id += 1
        await asyncio.sleep(2.5)
        await take_screenshot(ws, msg_id, "screen_2_quiz.png")
        msg_id += 1

        # 3. Screen 3: Research screen (active researching phase)
        print("3. Capturing screen_3_research.png...")
        await send_cmd(ws, msg_id, "Page.navigate", {"url": "http://127.0.0.1:8080/?screen=research"})
        msg_id += 1
        await asyncio.sleep(2.0)
        await take_screenshot(ws, msg_id, "screen_3_research.png")
        msg_id += 1

        # 4. Screen 4: Results screen showing Demo data banner, price estimate, warnings, ranked cards, verified badge, Call button
        print("4. Capturing screen_4_results.png...")
        await send_cmd(ws, msg_id, "Page.navigate", {"url": "http://127.0.0.1:8080/?screen=results"})
        msg_id += 1
        await asyncio.sleep(2.5)
        # Scroll down slightly (~180px) so the Demo data banner and top of price estimate stay visible,
        # while Contractor #1 card, Phone verified badge, and Call button are clearly visible!
        await scroll(ws, msg_id, 180)
        msg_id += 1
        await take_screenshot(ws, msg_id, "screen_4_results.png")
        msg_id += 1

        # 5. Screen 5: Details screen showing subscores, red flags, tappable source URLs, call_brief
        print("5. Capturing screen_5_details.png...")
        await send_cmd(ws, msg_id, "Page.navigate", {"url": "http://127.0.0.1:8080/?screen=details"})
        msg_id += 1
        await asyncio.sleep(2.5)
        # Scroll down to show subscores, red flags, tappable links, and call brief
        await scroll(ws, msg_id, 280)
        msg_id += 1
        await take_screenshot(ws, msg_id, "screen_5_details.png")
        msg_id += 1

    print("All 5 screenshots generated successfully!")

if __name__ == "__main__":
    asyncio.run(main())
