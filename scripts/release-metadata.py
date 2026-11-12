#!/usr/bin/env python3
"""Write checksums and a factual local artifact manifest after final stapling."""
import argparse
import hashlib
import json
import pathlib
import subprocess


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dmg", type=pathlib.Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--preview", choices=["true", "false"], required=True)
    parser.add_argument("--unsigned-beta", choices=["true", "false"], default="false")
    args = parser.parse_args()
    preview = args.preview == "true"
    unsigned = args.unsigned_beta == "true"
    if unsigned and (preview or "-beta." not in args.version):
        parser.error("Unsigned distribution requires a beta version and cannot be a local preview")
    signed = not preview and not unsigned
    files = [args.dmg]
    source = args.dmg.with_name(args.dmg.stem + "-source.tar.gz")
    if not preview:
        files.append(source)
    manifest = {
        "version": args.version,
        "channel": "local-preview" if preview else "unsigned-beta" if unsigned else "beta" if "-beta." in args.version else "stable",
        "public_signing_checks_passed": signed,
        "signing": "Developer ID Application" if signed else "ad-hoc",
        "notarized": signed,
        "full_xctest_passed_by_release_script": not preview,
        "minimum_macos": "14.0",
        "architecture": "arm64",
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "source_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip()),
        "artifacts": [{"file": f.name, "bytes": f.stat().st_size, "sha256": digest(f)} for f in files],
    }
    output = args.dmg.with_suffix(".json")
    output.write_text(json.dumps(manifest, indent=2) + "\n")
    files.append(output)
    args.dmg.with_suffix(".sha256").write_text("".join(f"{digest(f)}  {f.name}\n" for f in files))


if __name__ == "__main__":
    main()
