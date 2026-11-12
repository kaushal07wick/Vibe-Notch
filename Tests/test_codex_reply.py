import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import socket
import struct
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location(
    "codex_reply", Path(__file__).resolve().parents[1] / "Resources/vibenotch-codex-reply.py"
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class CodexReplyTests(unittest.TestCase):
    def run_server(self, request, rejection=False, disconnect=False):
        received, errors = [], []
        with tempfile.TemporaryDirectory(dir="/tmp", prefix="vn-reply-") as directory:
            path = str(Path(directory) / "codex.sock")
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.addCleanup(server.close)
            server.bind(path)
            Path(path).chmod(0o600)
            server.listen(1)
            server.settimeout(5)

            def serve():
                try:
                    connection, _ = server.accept()
                    with connection, connection.makefile("rb") as reader:
                        connection.settimeout(5)
                        headers = {}
                        reader.readline()
                        while (line := reader.readline()) != b"\r\n":
                            name, value = line.decode().split(":", 1)
                            headers[name.lower()] = value.strip()
                        accept = base64.b64encode(hashlib.sha1((headers["sec-websocket-key"] +
                            "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
                        connection.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                            b"Connection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")

                        def read():
                            first, second = reader.read(2)
                            self.assertEqual(first, 0x81)
                            self.assertTrue(second & 128, "Client frames must be masked")
                            size = second & 127
                            if size == 126:
                                size = struct.unpack("!H", reader.read(2))[0]
                            elif size == 127:
                                size = struct.unpack("!Q", reader.read(8))[0]
                            mask, data = reader.read(4), reader.read(size)
                            value = json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
                            received.append(value)
                            return value

                        def write(value):
                            data = json.dumps(value).encode()
                            header = bytes([0x81, len(data)]) if len(data) < 126 else b"\x81\x7e" + struct.pack("!H", len(data))
                            connection.sendall(header + data)

                        self.assertEqual(read()["method"], "initialize")
                        write({"id": 1, "result": {}})
                        self.assertEqual(read()["method"], "initialized")
                        self.assertEqual(read()["method"], "turn/start")
                        if disconnect:
                            return
                        write({"method": "thread/status/changed", "params": {}})
                        write({"id": 2, "error": {"message": "thread unavailable"}} if rejection else
                              {"id": 2, "result": {"turn": {"id": "turn-test"}}})
                except Exception as error:
                    errors.append(error)

            worker = threading.Thread(target=serve, daemon=True)
            worker.start()
            try:
                bridge.deliver(request, path=path)
            finally:
                worker.join(timeout=6)
                self.assertFalse(worker.is_alive(), "Bridge must not hang")
                if errors:
                    raise errors[0]
        return received

    def test_exact_thread_and_verbatim_answer_wait_for_acknowledgment(self):
        text = '<send_user_message_question_reply>\n[{"answer":"हैलो \\"quoted\\" 🚀"}]\n</send_user_message_question_reply>'
        received = self.run_server({"threadId": "exact-session-not-shared-cwd", "text": text})
        params = received[-1]["params"]
        self.assertEqual(params["threadId"], "exact-session-not-shared-cwd")
        self.assertEqual(params["input"][0]["text"], text)
        self.assertEqual(set(params), {"threadId", "input", "clientUserMessageId"})

    def test_rejected_answer_is_failure_without_retry(self):
        with self.assertRaisesRegex(ValueError, "thread unavailable"):
            self.run_server({"threadId": "session", "text": "answer"}, rejection=True)

    def test_disconnect_is_not_success(self):
        with self.assertRaises(ConnectionError):
            self.run_server({"threadId": "session", "text": "answer"}, disconnect=True)

    def test_empty_answer_rejected_before_connecting(self):
        with self.assertRaises(ValueError):
            bridge.deliver({"threadId": "session", "text": " "}, path="/missing")


if __name__ == "__main__":
    unittest.main()
