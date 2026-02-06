#!/usr/bin/env python3
"""
Minimal WebSocket echo server for testing the unPiNetworking WebSocket client.

Usage:
    pip3 install websockets
    python3 echo_server.py

Then connect from the iOS Simulator to ws://localhost:8765
"""

import asyncio
import json
from datetime import datetime

import websockets


async def handler(websocket):
    client = websocket.remote_address
    print(f"[+] Client connected: {client}")

    try:
        async for raw in websocket:
            print(f"<-- Received: {raw}")

            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                msg = {"text": raw}

            response = {
                "text": msg.get("text", ""),
                "sender": "server",
                "timestamp": datetime.now().isoformat(),
            }

            await websocket.send(json.dumps(response))
            print(f"--> Sent:     {json.dumps(response)}")

    except websockets.exceptions.ConnectionClosed:
        print(f"[-] Client disconnected: {client}")


async def main():
    print("WebSocket echo server starting on ws://localhost:8765")
    print("Press Ctrl+C to stop\n")

    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
