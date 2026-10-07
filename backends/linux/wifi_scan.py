#!/usr/bin/env python3
"""Survey observations from NetworkManager D-Bus; no connection changes."""

import argparse
import base64
from datetime import datetime, timezone
import json
import math
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
    age = None if seen_seconds < 0 else max(0, now_ms - seen_seconds * 1000)
    # LastSeen only has one-second precision. Same-second observations cannot
    # be distinguished from a reading just before the request.
    if seen_seconds < 0 or scan_started_ms is None:
        freshness = "unknown"
    elif seen_seconds < scan_started_ms // 1000:
        freshness = "cached"
    elif seen_seconds > scan_started_ms // 1000:
        freshness = "fresh"
    else:
        freshness = "unknown"
    width = int(properties.get("Bandwidth", 0)) or None
    return {
        "ssid": raw_ssid.decode("utf-8", errors="replace"),
        "ssid_bytes_base64": base64.b64encode(raw_ssid).decode("ascii"),
        "bssid": str(properties["HwAddress"]).lower(),
        "strength_percent": strength,
        "rssi_dbm": None,
        "noise_dbm": None,
        "frequency_mhz": int(properties["Frequency"]) or None,
        "channel_width_mhz": width,
        "connected": bool(active),
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
        observations.sort(key=lambda row: (-row["strength_percent"], row["bssid"]))
        last_scan = int(wireless.get("LastScan", -1))
        return {
            "schema_version": 1,
            "platform": "linux",
            "backend": "networkmanager-dbus",
            "interface_id": str(device["Interface"]),
            "driver": str(device.get("Driver", "")),
            "scan": {
                "status": "cached" if cached else "completed",
                "started_at": started_at,
                "completed_at": utc_now(),
                "last_scan_age_ms": None if last_scan < 0 else max(0, boottime_ms() - last_scan),
                "last_scan_boottime_ms": None if last_scan < 0 else last_scan,
                "scan_request_boottime_ms": requested_ms,
                "privileged_request": bool(with_sudo and not cached),
                "disappeared_access_points": disappeared,
            },
            "capabilities": {
                "strength_percent": True,
                "rssi_dbm": False,
                "noise_dbm": False,
                "channel_width_mhz": any(row["channel_width_mhz"] is not None for row in observations),
                "last_seen_resolution_ms": 1000,
            },
            "observations": observations,
        }


def error_object(error, interface):
    if isinstance(error, TimeoutError) or isinstance(error, subprocess.TimeoutExpired):
        code = "scan_timeout"
    elif hasattr(error, "get_dbus_name") and "PermissionDenied" in error.get_dbus_name():
        code = "permission_denied"
    elif isinstance(error, subprocess.CalledProcessError):
        code = "privileged_scan_failed"
    else:
        code = "backend_error"
    detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
    return {"schema_version": 1, "platform": "linux", "interface_id": interface,
            "error": {"code": code, "message": detail}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interface", help="Wi-Fi device name; defaults to every Wi-Fi device")
    parser.add_argument("--interfaces", action="store_true", help="List Wi-Fi devices without scanning")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--cached", action="store_true", help="Read the cache explicitly; do not request a scan")
    mode.add_argument("--scan-with-sudo", action="store_true", help="Use existing passwordless sudo only for RequestScan")
    parser.add_argument("--timeout", type=float, default=25, help="Scan deadline in seconds per interface")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be finite and positive")
    try:
        nm = NetworkManager()
        devices = nm.devices()
        if args.interfaces:
            print(json.dumps({"schema_version": 1, "platform": "linux", "interfaces": [
                {"interface_id": str(dev["Interface"]), "driver": str(dev.get("Driver", "")),
                 "state": int(dev["State"])} for _, dev in devices
            ]}))
            return 0
        if args.interface:
            devices = [(path, dev) for path, dev in devices if str(dev["Interface"]) == args.interface]
        if not devices:
            raise ValueError("No matching Wi-Fi interface found")
    except Exception as error:
        print(json.dumps(error_object(error, args.interface)))
        return 2
    failed = False
    for path, device in devices:
        try:
            output = nm.scan(path, device, args.cached, args.scan_with_sudo, args.timeout)
        except Exception as error:
            failed = True
            output = error_object(error, str(device["Interface"]))
        print(json.dumps(output, ensure_ascii=True), flush=True)
    return 2 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
