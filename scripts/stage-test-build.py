#!/usr/bin/env python3
"""Collect one platform's development installer with build details and hashes."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--component", choices=("cli", "desktop"), required=True)
    parser.add_argument("--platform", choices=(
        "linux-all", "linux-x64", "macos-arm64", "macos-x64", "windows-x64"
    ), required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    system = args.platform.split("-")[0]
    if args.component == "desktop" and args.platform == "linux-all":
        parser.error("The desktop Linux build is architecture-specific; use linux-x64.")
    if args.component == "cli" and args.platform == "linux-x64":
        parser.error("The Python CLI package uses Architecture: all; use linux-all.")
    if args.component == "cli":
        source = root / "backends" / system / "dist"
        pattern = {"linux": "*.deb", "macos": "*-development.pkg",
                   "windows": "*-development-setup.exe"}[system]
    else:
        source = root / "desktop/src-tauri/target/release/bundle"
        pattern = {"linux": "deb/*.deb", "macos": "*-development.dmg",
                   "windows": "nsis/*.exe"}[system]
    packages = sorted(source.glob(pattern))
    if len(packages) != 1 or not packages[0].is_file() or packages[0].stat().st_size == 0:
        raise RuntimeError(f"Expected one nonempty installer at {source / pattern}; found {len(packages)}.")
    destination = root / "dist/test-builds" / f"{args.component}-{args.platform}"
    destination.mkdir(parents=True, exist_ok=False)
    package = packages[0]
    shutil.copy2(package, destination / package.name)
    digest = hashlib.sha256()
    with (destination / package.name).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    checksum = digest.hexdigest()
    (destination / "SHA256SUMS").write_text(f"{checksum}  {package.name}\n", encoding="utf-8")
    version = json.loads((root / "desktop/package.json").read_text(encoding="utf-8"))["version"]
    metadata = {
        "component": args.component,
        "platform": args.platform,
        "version": version,
        "development": True,
        "signing": "ad-hoc; not notarized" if system == "macos" else "unsigned",
        "repository": os.environ.get("GITHUB_REPOSITORY"),
        "commit": os.environ.get("GITHUB_SHA"),
        "run_id": os.environ.get("GITHUB_RUN_ID"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "installer": {"file": package.name, "sha256": checksum, "bytes": package.stat().st_size},
    }
    (destination / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    shutil.copy2(root / "docs/test-builds.md", destination / "TESTING.md")
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(summary).open("a", encoding="utf-8") as stream:
            stream.write(
                f"### {args.component} test build: {args.platform}\n\n"
                f"Installer: `{package.name}`. Download the matching artifact below.\n\n"
                f"Signing: {metadata['signing']}. Includes `build-info.json`, `SHA256SUMS` and `TESTING.md`.\n"
            )
    print(f"Staged {destination}")


if __name__ == "__main__":
    main()
