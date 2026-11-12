#!/usr/bin/env python3
"""Offline release-layout validation; does not launch or approve agent actions."""
import argparse
from pathlib import Path
import plistlib
import struct
import subprocess


def verify(app):
    contents = app / 'Contents'
    metadata = plistlib.loads((contents / 'Info.plist').read_bytes())
    assert metadata['CFBundleIdentifier'] == 'com.kaushalchoudhary.vibenotch'
    source_metadata = plistlib.loads((Path(__file__).resolve().parents[1] / 'Resources/Info.plist').read_bytes())
    assert metadata['CFBundleShortVersionString'] == source_metadata['CFBundleShortVersionString']
    assert metadata['LSMinimumSystemVersion'] == '14.0'
    assert metadata['LSUIElement'] is True
    assert metadata['CFBundleIconFile'] == 'AppIcon'
    for relative in ['MacOS/VibeNotch', 'Helpers/vibenotch-hook', 'Helpers/vibenotch', 'Helpers/libvnnowplaying.dylib']:
        path = contents / relative
        data = path.read_bytes()
        magic, cpu = struct.unpack_from('<II', data)
        assert magic == 0xFEEDFACF and cpu == 0x0100000C, f'{relative}: expected thin arm64 Mach-O'
        count = struct.unpack_from('<I', data, 16)[0]
        offset, deployment = 32, None
        for _ in range(count):
            command, size = struct.unpack_from('<II', data, offset)
            if command == 0x32:  # LC_BUILD_VERSION
                platform, deployment = struct.unpack_from('<II', data, offset + 8)
                assert platform == 1, f'{relative}: expected macOS platform'
            elif command == 0x24:  # LC_VERSION_MIN_MACOSX
                deployment = struct.unpack_from('<I', data, offset + 8)[0]
            offset += size
        assert deployment is not None and deployment <= 0x000E0000, f'{relative}: minimum macOS exceeds 14.0'
    resources = contents / 'Resources'
    assert (resources / 'AppIcon.icns').stat().st_size > 1000
    assert 'SIL OPEN FONT LICENSE' in (resources / 'Licenses/DepartureMono-OFL.txt').read_text()
    for license in ['DynamicNotchKit-MIT.txt', 'VibeNotch-GPL-3.0.txt']:
        assert (resources / 'Licenses' / license).stat().st_size > 100
    for required in ['THIRD_PARTY_NOTICES.txt', 'nowplaying.pl', 'vibenotch-opencode.js', 'vibenotch-remote-hook.py', 'vibenotch-codex-reply.py']:
        assert (resources / required).is_file(), required
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print('Bundle verified: arm64 binaries, metadata, helpers, resources, licenses, and signature integrity')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    verify(parser.parse_args().app)
