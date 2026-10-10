#!/usr/bin/env python3
"""Validate draft scan fixtures and captures; shape alone cannot prove live scan behavior."""

import base64
import argparse
from datetime import datetime
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


def validate(value, validators, label):
    validators["interfaces" if "interfaces" in value else "scan"].validate(value)
    if "interfaces" in value:
        ids = [item["id"] for item in value["interfaces"]]
        if len(ids) != len(set(ids)):
            raise ValueError(f"{label}: duplicate interface IDs")
        return
    capabilities = value["capabilities"]
    scan = value["scan"]
    if scan["completed_at"] is not None:
        started = datetime.fromisoformat(scan["started_at"].replace("Z", "+00:00"))
        completed = datetime.fromisoformat(scan["completed_at"].replace("Z", "+00:00"))
        if completed < started:
            raise ValueError(f"{label}: completion precedes start")
    for observation in value["observations"]:
        for field in ("rssi_dbm", "strength_percent", "noise_dbm", "channel_width_mhz"):
            if not capabilities[field] and observation[field] is not None:
                raise ValueError(f"{label}: unsupported measurement {field}")
        if scan["status"] == "cached" and observation["freshness"] == "fresh":
            raise ValueError(f"{label}: cached read cannot claim request freshness")
        raw = observation["ssid_bytes_base64"]
        if raw is not None and len(base64.b64decode(raw, validate=True)) > 32:
            raise ValueError(f"{label}: SSID exceeds 32 bytes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="JSON/JSONL files or directories of JSON results")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    draft = root / "contracts/draft"
    validators = {}
    for kind in ("scan", "interfaces"):
        schema = json.loads((draft / f"{kind}.schema.json").read_text())
        Draft202012Validator.check_schema(schema)
        validators[kind] = Draft202012Validator(schema, format_checker=FormatChecker())
    paths = args.paths or [draft / "fixtures"]
    fixtures = sorted(file for path in paths for file in (path.glob("*.json") if path.is_dir() else [path]))
    if not fixtures:
        raise ValueError("No draft fixtures found")
    count = 0
    for fixture in fixtures:
        text = fixture.read_text(encoding="utf-8-sig")
        values = [json.loads(line) for line in text.splitlines() if line.strip()] if fixture.suffix == ".jsonl" else [json.loads(text)]
        for index, value in enumerate(values, 1):
            validate(value, validators, f"{fixture.name}:{index}")
            count += 1
        print(f"PASS {fixture.name} ({len(values)} results)")
    if not count:
        raise ValueError("No scan results found")
    print(f"Validated {count} draft backend results; schema checks alone do not establish live scan behavior.")


if __name__ == "__main__":
    main()
