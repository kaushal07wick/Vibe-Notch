#!/usr/bin/env python3
"""Exercise the bundled native hook against isolated Unix sockets, never a real agent."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import unittest

HOOK = None


class HookSmokeTests(unittest.TestCase):
    def run_hook(self, path, payload, source="claude"):
        result = subprocess.run([str(HOOK), "--source", source],
                                input=json.dumps(payload), text=True, capture_output=True,
                                env={**os.environ, "VIBENOTCH_SOCKET": path}, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def exchange(self, payload, reply, source="claude"):
        # macOS sockaddr_un paths are short; use /tmp rather than the long user TMPDIR.
        with tempfile.TemporaryDirectory(prefix="vn-smoke-", dir="/tmp") as folder:
            path = folder + "/ipc.sock"
            errors, messages = [], []
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                server.bind(path)
                server.listen(1)
                server.settimeout(8)
                def serve():
                    try:
                        with server.accept()[0] as peer:
                            peer.settimeout(8)
                            data = b""
                            while not data.endswith(b"\n"):
                                chunk = peer.recv(65536)
                                if not chunk:
                                    raise RuntimeError("Hook closed before sending a message")
                                data += chunk
                            messages.append(json.loads(data))
                            if reply is not None:
                                peer.sendall(json.dumps(reply).encode() + b"\n")
                    except Exception as error:
                        errors.append(error)
                worker = threading.Thread(target=serve, daemon=True)
                worker.start()
                try:
                    output = self.run_hook(path, payload, source)
                finally:
                    worker.join(timeout=9)
                self.assertFalse(worker.is_alive(), "Fixture server did not finish")
                self.assertFalse(errors, str(errors))
                return output, messages[0]

    @staticmethod
    def permission():
        return {"hook_event_name": "PermissionRequest", "tool_name": "Bash",
                "tool_input": {"command": "echo smoke-test"}, "session_id": "isolated-smoke"}

    def test_allow_and_deny(self):
        for decision in ("allow", "deny"):
            with self.subTest(decision=decision):
                output, message = self.exchange(self.permission(), {"decision": decision})
                self.assertEqual(output["hookSpecificOutput"]["decision"]["behavior"], decision)
                self.assertEqual(message["type"], "request")
                self.assertEqual(message["detail"], "echo smoke-test")

    def test_codex_envelope(self):
        output, message = self.exchange(self.permission(), {"decision": "allow"}, "codex")
        self.assertTrue(output["continue"])
        self.assertEqual(message["source"], "codex")

    def test_question_answer(self):
        payload = self.permission()
        payload.update(tool_name="AskUserQuestion", tool_input={"questions": [
            {"question": "Pick one", "options": [{"label": "A"}, {"label": "B"}]}]})
        output, message = self.exchange(payload, {"decision": "allow", "answers": ["B"]})
        self.assertEqual(len(message["questions"][0]["options"]), 2)
        self.assertIn("B", json.dumps(output))

    def test_absent_app_falls_back_to_agent(self):
        with tempfile.TemporaryDirectory(prefix="vn-smoke-", dir="/tmp") as folder:
            self.assertIsNone(self.run_hook(folder + "/absent.sock", self.permission()))

    def test_peer_disconnect_falls_back_to_agent(self):
        output, _ = self.exchange(self.permission(), None)
        self.assertIsNone(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hook", type=Path)
    args = parser.parse_args()
    HOOK = args.hook.resolve(strict=True)
    unittest.main(argv=[__file__], verbosity=2)
