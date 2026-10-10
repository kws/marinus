#!/usr/bin/env python3
"""Survey observations from NetworkManager D-Bus; no connection changes."""

import argparse
import base64
from datetime import datetime, timezone
import json
import math
import os
import re
import subprocess
import sys
import time

NM = "org.freedesktop.NetworkManager"
DEVICE = NM + ".Device"
WIRELESS = DEVICE + ".Wireless"
AP = NM + ".AccessPoint"
PROPERTIES = "org.freedesktop.DBus.Properties"


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def boottime_ms():
    return int(time.clock_gettime(time.CLOCK_BOOTTIME) * 1000)


def normalize_ap(properties, active, now_ms, scan_started_ms=None):
    """Keep native percentages and unknown fields; never merge by SSID."""
    raw_ssid = bytes(properties.get("Ssid", []))
    strength = int(properties["Strength"])
    if not 0 <= strength <= 100:
        raise ValueError("NetworkManager returned signal strength outside 0..100")
    seen_seconds = int(properties.get("LastSeen", -1))
    age = None if seen_seconds < 0 or seen_seconds * 1000 > now_ms else now_ms - seen_seconds * 1000
    # LastSeen only has one-second precision. Same-second observations cannot
    # be distinguished from a reading just before the request.
    if age is None or scan_started_ms is None:
        freshness = "unknown"
    elif seen_seconds < scan_started_ms // 1000:
        freshness = "cached"
    elif seen_seconds > scan_started_ms // 1000:
        freshness = "fresh"
    else:
        freshness = "unknown"
    width = int(properties.get("Bandwidth", 0))
    return {
        "ssid": raw_ssid.decode("utf-8", errors="replace"),
        "ssid_bytes_base64": base64.b64encode(raw_ssid).decode("ascii"),
        "bssid": valid_bssid(str(properties.get("HwAddress", ""))),
        "strength_percent": strength,
        "rssi_dbm": None,
        "noise_dbm": None,
        "frequency_mhz": int(properties["Frequency"]) or None,
        # NetworkManager 1.46+ exposes the AP's advertised operating bandwidth.
        # Older daemons omit it; zero means unknown rather than a 20 MHz default.
        "channel_width_mhz": width if width > 0 else None,
        "connected": bool(active) if valid_bssid(str(properties.get("HwAddress", ""))) else None,
        "last_seen_age_ms": age,
        "freshness": freshness,
        "security_flags": {
            "privacy": bool(int(properties.get("Flags", 0)) & 1),
            "wpa": int(properties.get("WpaFlags", 0)),
            "rsn": int(properties.get("RsnFlags", 0)),
        },
    }


def wait_for_scan(read_last_scan, previous, requested_ms, timeout):
    deadline = time.monotonic() + timeout
    while True:
        latest = int(read_last_scan())
        if latest > previous and latest >= requested_ms:
            return latest
        if time.monotonic() >= deadline:
            raise TimeoutError("NetworkManager did not report a completed scan before the deadline")
        time.sleep(0.2)


class NetworkManager:
    def __init__(self):
        # Distro dependency, imported lazily so contract tests can run on macOS.
        import dbus

        self.dbus = dbus
        self.bus = dbus.SystemBus()
        self.manager = self.interface("/org/freedesktop/NetworkManager", NM)

    def interface(self, path, name):
        return self.dbus.Interface(self.bus.get_object(NM, path), name)

    def properties(self, path, name):
        return self.interface(path, PROPERTIES).GetAll(name)

    def devices(self):
        result = []
        for path in self.manager.GetDevices():
            props = self.properties(path, DEVICE)
            if int(props["DeviceType"]) == 2:
                result.append((str(path), props))
        return sorted(result, key=lambda item: str(item[1]["Interface"]))

    def request_scan(self, path, with_sudo, timeout):
        if with_sudo:
            # Elevate only this fixed scan request, not the collector process.
            subprocess.run(
                ["sudo", "-n", "/usr/bin/gdbus", "call", "--system", "--dest", NM,
                 "--object-path", path, "--method", WIRELESS + ".RequestScan", "{}"],
                check=True, capture_output=True, text=True, timeout=timeout,
            )
        else:
            self.interface(path, WIRELESS).RequestScan(
                self.dbus.Dictionary({}, signature="sv"), timeout=timeout,
            )

    def scan(self, path, device, cached, with_sudo, timeout):
        started_at = utc_now()
        wireless = self.properties(path, WIRELESS)
        previous = int(wireless.get("LastScan", -1))
        requested_ms = None
        if not cached:
            requested_ms = boottime_ms()
            request_start = time.monotonic()
            self.request_scan(path, with_sudo, timeout)
            remaining = max(0, timeout - (time.monotonic() - request_start))
            wait_for_scan(
                lambda: self.properties(path, WIRELESS).get("LastScan", -1),
                previous, requested_ms, remaining,
            )
        wireless = self.properties(path, WIRELESS)
        active = str(wireless.get("ActiveAccessPoint", "/"))
        observations = []
        disappeared = 0
        for ap_path in self.interface(path, WIRELESS).GetAllAccessPoints():
            try:
                props = self.properties(ap_path, AP)
            except self.dbus.DBusException as error:
                if error.get_dbus_name() in (
                    "org.freedesktop.DBus.Error.UnknownObject",
                    "org.freedesktop.DBus.Error.UnknownMethod",
                ):
                    disappeared += 1
                    continue
                raise
            observations.append(normalize_ap(props, str(ap_path) == active, boottime_ms(), requested_ms))
        observations.sort(key=lambda row: (-row["strength_percent"], (row["bssid"] or "")))
        for row in observations:
            row.pop("security_flags", None)
        return envelope(str(device["Interface"]), started_at,
                        "cached" if cached else "completed", observations,
                        driver=str(device.get("Driver", "")) or None)


BACKEND = {"platform": "linux", "name": "networkmanager-dbus", "backend_version": "0.1.0"}
CAPABILITIES = {"strength_percent": True, "rssi_dbm": False, "noise_dbm": False,
                "channel_width_mhz": True, "last_seen_resolution_ms": 1000}


def valid_bssid(text):
    text = text.lower()
    return text if re.fullmatch(r"[0-9a-f]{2}(:[0-9a-f]{2}){5}", text) and text not in (
        "00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff") else None


def error_detail(error):
    name = error.get_dbus_name() if hasattr(error, "get_dbus_name") else ""
    if isinstance(error, (TimeoutError, subprocess.TimeoutExpired)) or name.endswith(("NoReply", "Timeout")):
        code = "scan_timeout"
    elif any(part in name for part in ("PermissionDenied", "NotAuthorized", "AccessDenied")):
        code = "permission_denied"
    elif isinstance(error, LookupError):
        code = "interface_unavailable"
    else:
        code = "backend_error"
    detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
    return {"code": code, "message": detail or type(error).__name__}


def envelope(interface, started, status, observations=None, driver=None, error=None):
    return {"contract_version": "0.1.0", "backend": dict(BACKEND),
            "interface": {"id": interface or "auto", "driver": driver},
            "capabilities": dict(CAPABILITIES),
            "scan": {"status": status, "started_at": started,
                     "completed_at": None if status == "failed" else utc_now(), "error": error},
            "observations": [] if status == "failed" else (observations or [])}


def collect(nm, interface=None, cached=False, timeout=25, with_sudo=False):
    started = utc_now()
    selected = interface
    try:
        devices = nm.devices()
        if interface:
            devices = [(path, dev) for path, dev in devices if str(dev["Interface"]) == interface]
        if len(devices) != 1:
            raise LookupError("Select --interface when several Wi-Fi devices exist; no matching device is otherwise available")
        path, device = devices[0]
        selected = str(device["Interface"])
        return nm.scan(path, device, cached, with_sudo, timeout)
    except Exception as error:
        return envelope(selected, started, "failed", error=error_detail(error))


def interface_envelope(nm):
    return {"contract_version": "0.1.0", "backend": dict(BACKEND), "error": None,
            "interfaces": [{"id": str(dev["Interface"]), "name": str(dev["Interface"]),
                            "driver": str(dev.get("Driver", "")) or None, "state": str(int(dev["State"]))}
                           for _, dev in nm.devices()]}


def write_table(result):
    if result["scan"]["error"]:
        error = result["scan"]["error"]
        print(f"{error['code']}: {error['message']}")
        return
    print("SSID\tBSSID\tSIGNAL %\tMHz\tFRESHNESS")
    for row in result["observations"]:
        ssid = "(unavailable)" if row["ssid"] is None else row["ssid"] or "(hidden)"
        safe = "".join(char if char.isprintable() else "?" for char in ssid)
        print(f"{safe}\t{row['bssid'] or '?'}\t{row['strength_percent']}\t{row['frequency_mhz'] or '?'}\t{row['freshness']}")


def main(argv=None, factory=NetworkManager):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("scan", "interfaces", "watch"), default="scan")
    parser.add_argument("--interface", help="Wi-Fi device name; required when several devices exist")
    parser.add_argument("--interfaces", action="store_true", help=argparse.SUPPRESS)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--cached", action="store_true", help="Explicit cache read (scan only)")
    mode.add_argument("--scan-with-sudo", action="store_true", help="Diagnostic fixed RequestScan via existing sudo")
    parser.add_argument("--json", action="store_true", help="Emit shared contract JSON; watch emits JSON Lines")
    parser.add_argument("--timeout", type=float, default=25, help="Scan deadline in seconds")
    parser.add_argument("--interval", type=float, default=5, help="Pause after each watch scan")
    parser.add_argument("--count", type=int, help="Number of watch scans")
    parser.add_argument("--output", help="Save JSON to a new file; existing files are preserved")
    args = parser.parse_args(argv)
    if args.interfaces:
        args.command = "interfaces"
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 300:
        parser.error("--timeout needs 0..300 seconds (excluding zero)")
    if not math.isfinite(args.interval) or not 1 <= args.interval <= 86400:
        parser.error("--interval needs 1..86400 seconds")
    if args.count is not None and (args.count < 1 or args.command != "watch"):
        parser.error("--count needs a positive integer and watch")
    if args.cached and args.command != "scan":
        parser.error("--cached requires scan")
    if args.command == "interfaces" and (args.output or args.interface or args.scan_with_sudo):
        parser.error("interfaces supports only --json")
    output = None
    try:
        # Open before constructing the scanner, so collisions cause no radio access.
        if args.output:
            from pathlib import Path
            Path(args.output).resolve().parent.mkdir(parents=True, exist_ok=True)
            fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            output = os.fdopen(fd, "w", encoding="utf-8")
        try:
            nm = factory()
        except Exception as error:
            if args.command == "interfaces":
                value = {"contract_version": "0.1.0", "backend": dict(BACKEND), "interfaces": [], "error": error_detail(error)}
            else:
                value = envelope(args.interface, utc_now(), "failed", error=error_detail(error))
            text = json.dumps(value)
            print(text)
            if output:
                output.write(text + "\n")
            return 1
        if args.command == "interfaces":
            try:
                value = interface_envelope(nm)
            except Exception as error:
                value = {"contract_version": "0.1.0", "backend": dict(BACKEND), "interfaces": [], "error": error_detail(error)}
            if args.json:
                print(json.dumps(value))
            elif value["error"]:
                print(value["error"]["message"], file=sys.stderr)
            else:
                for item in value["interfaces"]:
                    print(item["id"])
            return 1 if value["error"] else 0
        selected = args.interface
        index = 0
        while True:
            value = collect(nm, selected, args.cached, args.timeout, args.scan_with_sudo)
            text = json.dumps(value, ensure_ascii=True)
            if output:
                output.write(text + "\n")
                output.flush()
            if args.json:
                print(text, flush=True)
            else:
                write_table(value)
            if value["scan"]["status"] == "failed":
                return 1
            selected = value["interface"]["id"]
            index += 1
            if args.command != "watch" or (args.count is not None and index >= args.count):
                return 0
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    finally:
        if output:
            output.close()


if __name__ == "__main__":
    sys.exit(main())
