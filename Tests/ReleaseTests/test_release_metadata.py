import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MetadataTests(unittest.TestCase):
    def test_unsigned_beta_includes_source_without_claiming_notarization(self):
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "VibeNotch-UNSIGNED-BETA.dmg"
            dmg.write_bytes(b"fixture")
            dmg.with_name(dmg.stem + "-source.tar.gz").write_bytes(b"source")
            subprocess.run(["python3", str(ROOT / "scripts/release-metadata.py"), str(dmg), "--version", "0.4.0-beta.1", "--preview", "false", "--unsigned-beta", "true"], cwd=ROOT, check=True)
            metadata = json.loads(dmg.with_suffix('.json').read_text())
            self.assertEqual(metadata['channel'], 'unsigned-beta')
            self.assertFalse(metadata['notarized'])
            self.assertFalse(metadata['public_signing_checks_passed'])
            self.assertTrue(metadata['full_xctest_passed_by_release_script'])
            self.assertEqual(len(metadata['artifacts']), 2)

    def test_preview_never_claims_signing_or_full_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            dmg = Path(directory) / "VibeNotch-LOCAL-PREVIEW.dmg"
            dmg.write_bytes(b"fixture")
            subprocess.run(["python3", str(ROOT / "scripts/release-metadata.py"), str(dmg), "--version", "0.4.0-beta.1", "--preview", "true"], cwd=ROOT, check=True)
            metadata = json.loads(dmg.with_suffix('.json').read_text())
            self.assertEqual(metadata['channel'], 'local-preview')
            self.assertFalse(metadata['notarized'])
            self.assertFalse(metadata['full_xctest_passed_by_release_script'])
            self.assertTrue(dmg.with_suffix('.sha256').read_text().startswith(metadata['artifacts'][0]['sha256']))
