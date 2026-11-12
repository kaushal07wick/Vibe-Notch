import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("uninstall", ROOT / "scripts/uninstall.py")
uninstall = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uninstall)


class UninstallTests(unittest.TestCase):
    def test_mixed_hooks_and_original_statusline_survive(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            config = home / ".codex/hooks.json"
            config.parent.mkdir()
            aria = {"command": "/Applications/Aria/aria-notch-hook.sh"}
            ours = {"command": "/home/.vibenotch/bin/vibenotch-hook --source codex"}
            config.write_text(json.dumps({"hooks": {"Stop": [{"matcher": "*", "hooks": [aria, ours]}]}}))
            original = {"type": "command", "command": "printf 'original'", "padding": 2}
            saved = home / ".vibenotch/bin/statusline-original.json"
            saved.parent.mkdir(parents=True)
            saved.write_text(json.dumps(original))
            claude = home / ".claude/settings.json"
            claude.parent.mkdir()
            claude.write_text(json.dumps({"statusLine": {"type": "command", "command": str(saved.parent / "statusline.sh")}}))
            uninstall.apply(uninstall.plan(home))
            self.assertEqual(json.loads(config.read_text())["hooks"]["Stop"][0]["hooks"], [aria])
            self.assertEqual(json.loads(claude.read_text())["statusLine"], original)
            self.assertTrue(list(config.parent.glob("*.bak")))
            self.assertEqual(uninstall.plan(home), [])

    def test_malformed_input_prevents_all_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            config = home / ".claude/settings.json"
            config.parent.mkdir()
            config.write_text('{broken')
            with self.assertRaises(ValueError):
                uninstall.plan(home)
            self.assertEqual(config.read_text(), '{broken')

    def test_changed_input_prevents_removal(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            config = home / ".codex/hooks.json"
            config.parent.mkdir()
            config.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [{"command": "vibenotch-hook"}]}]}}))
            changes = uninstall.plan(home)
            config.write_text('{"changed":true}')
            with self.assertRaises(RuntimeError):
                uninstall.apply(changes)
            self.assertEqual(json.loads(config.read_text()), {"changed": True})

    def test_empty_foreign_groups_are_preserved(self):
        root = {"hooks": {"Stop": [{"matcher": "*", "hooks": []}, {"hooks": [{"command": "vibenotch-hook"}]}]}}
        self.assertEqual(uninstall.remove_hooks(root), {"hooks": {"Stop": [{"matcher": "*", "hooks": []}]}})


if __name__ == "__main__":
    unittest.main()
