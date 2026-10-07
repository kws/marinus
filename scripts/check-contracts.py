#!/usr/bin/env python3
"""Validate synthetic draft examples; this does not assert backend conformance."""

import base64
from datetime import datetime
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


def main():
    root = Path(__file__).resolve().parents[1]
    draft = root / "contracts/draft"
    schema = json.loads((draft / "scan.schema.json").read_text())
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    fixtures = sorted((draft / "fixtures").glob("*.json"))
    if not fixtures:
        raise ValueError("No draft fixtures found")
    for fixture in fixtures:
        value = json.loads(fixture.read_text())
        validator.validate(value)
        capabilities = value["capabilities"]
        scan = value["scan"]
        if scan["completed_at"] is not None:
            started = datetime.fromisoformat(scan["started_at"].replace("Z", "+00:00"))
            completed = datetime.fromisoformat(scan["completed_at"].replace("Z", "+00:00"))
            if completed < started:
                raise ValueError(f"{fixture.name}: completion precedes start")
        for observation in value["observations"]:
            for field in ("rssi_dbm", "strength_percent", "noise_dbm", "channel_width_mhz"):
                if not capabilities[field] and observation[field] is not None:
                    raise ValueError(f"{fixture.name}: unsupported measurement {field}")
            if scan["status"] == "cached" and observation["freshness"] == "fresh":
                raise ValueError(f"{fixture.name}: cached read cannot claim request freshness")
            raw = observation["ssid_bytes_base64"]
            if raw is not None and len(base64.b64decode(raw, validate=True)) > 32:
                raise ValueError(f"{fixture.name}: SSID exceeds 32 bytes")
        print(f"PASS {fixture.name}")
    print(f"Validated {len(fixtures)} draft fixtures; backend conformance is not yet implemented.")


if __name__ == "__main__":
    main()
