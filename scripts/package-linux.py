#!/usr/bin/env python3
"""Build a Debian CLI package; staging also runs on macOS without dpkg."""
import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path


def stage(root, destination, version="0.1.0"):
    if destination.exists():
        raise FileExistsError(f"Preserving existing staging directory: {destination}")
    for directory in ("DEBIAN", "usr/bin", "usr/lib/marinus", "usr/share/doc/marinus"):
        (destination / directory).mkdir(parents=True, exist_ok=True)
    (destination / "DEBIAN/control").write_text(
        f"Package: marinus\nVersion: {version}\nArchitecture: all\n"
        "Maintainer: Marinus contributors\n"
        "Section: net\nPriority: optional\nDepends: python3 (>= 3.10), python3-dbus, network-manager\n"
        "Description: Wi-Fi observations for site surveys\n"
        " Preserves individual access points and native signal measurements.\n", encoding="utf-8")
    shutil.copy2(root / "backends/linux/wifi_scan.py", destination / "usr/lib/marinus/wifi_scan.py")
    launcher = destination / "usr/bin/marinus"
    launcher.write_text('#!/bin/sh\nexec /usr/bin/python3 /usr/lib/marinus/wifi_scan.py "$@"\n', encoding="utf-8")
    launcher.chmod(0o755)
    notices = destination / "usr/share/doc/marinus"
    for name in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
        shutil.copy2(root / name, notices / name)
    shutil.copytree(root / "licenses", notices / "licenses")
    shutil.copy2(root / "backends/linux/README.md", notices / "README.md")
    # Packages install no PolicyKit override or privileged collector.
    for path in destination.rglob("*"):
        if path.is_dir():
            path.chmod(0o755)
        elif path != launcher:
            path.chmod(0o644)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage-only", action="store_true")
    parser.add_argument("--output", type=Path, default=Path("backends/linux/dist"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.stage_only:
        staging = output / "marinus_0.1.0_all"
        stage(root, staging)
        print(f"Staged {staging}")
        return
    with tempfile.TemporaryDirectory(prefix="marinus-deb-") as directory:
        staging = Path(directory) / "payload"
        stage(root, staging)
        subprocess.run(["dpkg-deb", "--root-owner-group", "--build", str(staging), str(output / "marinus_0.1.0_all.deb")], check=True)
    print(f"Created {output / 'marinus_0.1.0_all.deb'}")


if __name__ == "__main__":
    main()
