#!/usr/bin/env python3
"""Deliver a question reply to its loaded Codex thread over the local control socket."""
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import struct
import sys
import time
import uuid


class CodexConnection:
    # The daemon uses WebSocket JSON-RPC over a Unix socket, with no TCP listener.
    def __init__(self, path):
        info = os.stat(path)
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("Codex socket must be private and owned by this user")
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(5)
        try:
            self.socket.connect(str(path))
            self.reader = self.socket.makefile("rb")
            key = base64.b64encode(os.urandom(16)).decode()
            self.socket.sendall((
                "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
                "Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                f"Sec-WebSocket-Key: {key}\r\n\r\n"
            ).encode())
            status = self.reader.readline(8192)
            headers = {}
            for _ in range(64):
                line = self.reader.readline(8192)
                if line == b"\r\n":
                    break
                name, value = line.decode().split(":", 1)
                headers[name.lower()] = value.strip()
            expected = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
            ).digest()).decode()
            if status.split()[1:2] != [b"101"] or headers.get("sec-websocket-accept") != expected:
                raise ValueError("Codex WebSocket handshake failed")
        except Exception:
            self.close()
            raise

    def close(self):
        if hasattr(self, "reader"):
            self.reader.close()
        self.socket.close()

    def send(self, value, opcode=1):
        data = json.dumps(value).encode() if opcode == 1 else value
        length = len(data)
        header = bytes([0x80 | opcode])
        if length < 126:
            header += bytes([0x80 | length])
        elif length < 65536:
            header += b"\xfe" + struct.pack("!H", length)
        else:
            header += b"\xff" + struct.pack("!Q", length)
        mask = os.urandom(4)
        self.socket.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def read_exact(self, size):
        data = self.reader.read(size)
        if len(data) != size:
            raise ConnectionError("Codex closed the connection before acknowledging the answer")
        return data

    def receive(self):
        message = bytearray()
        while True:
            first, second = self.read_exact(2)
            opcode, length = first & 15, second & 127
            if second & 128:
                raise ValueError("Unexpected masked server frame")
            if length == 126:
                length = struct.unpack("!H", self.read_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self.read_exact(8))[0]
            if len(message) + length > 8_000_000:
                raise ValueError("Codex response too large")
            data = self.read_exact(length)
            if opcode == 8:
                raise ConnectionError("Codex closed the connection")
            if opcode == 9:
                self.send(data, opcode=10)
                continue
            if opcode == 10:
                continue
            if opcode not in (0, 1):
                raise ValueError("Expected a Codex JSON response")
            message.extend(data)
            if first & 128:
                return json.loads(message)

    def request(self, request_id, method, params):
        self.send({"id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + 5
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Codex did not acknowledge the answer")
            self.socket.settimeout(remaining)
            reply = self.receive()
            if reply.get("id") != request_id:
                continue
            if "error" in reply:
                raise ValueError(reply["error"].get("message", "Codex rejected the answer"))
            if "result" not in reply:
                raise ValueError("Missing Codex acknowledgment")
            return reply["result"]


def deliver(request, path=None):
    thread, text = request["threadId"], request["text"]
    if not isinstance(thread, str) or not thread or not isinstance(text, str) or not text.strip():
        raise ValueError("Missing thread or answer")
    root = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    connection = CodexConnection(path or root / "app-server-control/app-server-control.sock")
    try:
        connection.request(1, "initialize", {
            "clientInfo": {"name": "vibenotch", "version": "1.0"},
        })
        connection.send({"method": "initialized"})
        # Omitted settings preserve the CLI's model, permissions, and working directory.
        connection.request(2, "turn/start", {
            "threadId": thread,
            "clientUserMessageId": str(uuid.uuid5(uuid.NAMESPACE_URL, thread + text)),
            "input": [{"type": "text", "text": text, "text_elements": []}],
        })
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        deliver(json.load(sys.stdin))
        print(json.dumps({"ok": True}))
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        sys.exit(1)
