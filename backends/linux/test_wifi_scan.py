import base64
import unittest
import io
import json
import tempfile
import os
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path
from unittest.mock import patch

from wifi_scan import normalize_ap, wait_for_scan, collect, envelope, main, NetworkManager, WIRELESS, AP


def access_point(ssid=b"Office", bssid="AA:BB:CC:DD:EE:01", strength=70, seen=10):
    return {"Ssid": ssid, "HwAddress": bssid, "Strength": strength,
            "Frequency": 5180, "LastSeen": seen}


class SurveyContractTests(unittest.TestCase):
    def test_raw_percentages_are_preserved_without_inventing_dbm(self):
        rows = [normalize_ap(access_point(strength=n), False, 12000) for n in (0, 30, 100)]
        self.assertEqual([row["strength_percent"] for row in rows], [0, 30, 100])
        self.assertTrue(all(row["rssi_dbm"] is None and row["noise_dbm"] is None
                            and row["channel_width_mhz"] is None for row in rows))

    def test_duplicate_ssids_hidden_ssids_and_non_utf8_bytes_survive(self):
        raw = [access_point(), access_point(bssid="AA:BB:CC:DD:EE:02"),
               access_point(ssid=b""), access_point(ssid=b"\xffOffice")]
        rows = [normalize_ap(ap, False, 12000) for ap in raw]
        self.assertEqual(len(rows), 4)
        self.assertEqual(rows[0]["ssid"], rows[1]["ssid"])
        self.assertNotEqual(rows[0]["bssid"], rows[1]["bssid"])
        self.assertEqual(rows[2]["ssid"], "")
        self.assertEqual(base64.b64decode(rows[3]["ssid_bytes_base64"]), b"\xffOffice")

    def test_advertised_width_is_optional_and_never_inferred_from_frequency(self):
        for width in (20, 40, 80, 160, 320):
            with self.subTest(width=width):
                ap = dict(access_point(), Bandwidth=width)
                self.assertEqual(normalize_ap(ap, False, 12000)["channel_width_mhz"], width)
        for ap in (access_point(), dict(access_point(), Bandwidth=0), dict(access_point(), Bandwidth=-1)):
            self.assertIsNone(normalize_ap(ap, False, 12000)["channel_width_mhz"])

    def test_cache_age_and_unknown_age_are_explicit(self):
        self.assertEqual(normalize_ap(access_point(), False, 12000, 11000)["freshness"], "cached")
        self.assertEqual(normalize_ap(access_point(), False, 12000)["last_seen_age_ms"], 2000)
        self.assertIsNone(normalize_ap(access_point(seen=-1), False, 12000)["last_seen_age_ms"])
        self.assertEqual(normalize_ap(access_point(seen=11), False, 12000, 11250)["freshness"], "unknown")
        self.assertEqual(normalize_ap(access_point(seen=12), False, 12000, 11250)["freshness"], "fresh")

    def test_old_background_completion_does_not_satisfy_a_new_request(self):
        with patch("wifi_scan.time.sleep"), patch("wifi_scan.time.monotonic", return_value=0):
            values = iter([1000, 1100, 2500])
            self.assertEqual(wait_for_scan(lambda: next(values), 1000, 2000, 1), 2500)

    def test_unchanged_last_scan_times_out(self):
        with patch("wifi_scan.time.monotonic", side_effect=[0, 1]):
            with self.assertRaises(TimeoutError):
                wait_for_scan(lambda: 1000, 1000, 2000, 0.1)

    def test_future_timestamps_and_masked_bssids_are_unknown(self):
        row = normalize_ap(access_point(seen=20, bssid="00:00:00:00:00:00"), True, 12000, 11000)
        self.assertIsNone(row["last_seen_age_ms"])
        self.assertEqual(row["freshness"], "unknown")
        self.assertIsNone(row["bssid"])
        self.assertIsNone(row["connected"])

    def test_fresh_failure_is_empty_and_never_retries_cached(self):
        nm = FakeManager()
        nm.failure = TimeoutError("Synthetic timeout")
        value = collect(nm)
        self.assertEqual(value["scan"]["error"]["code"], "scan_timeout")
        self.assertEqual(value["observations"], [])
        self.assertEqual(nm.calls, [("wlan0", False)])
        emit_fixture("linux-generated-timeout", value)

    def test_ambiguous_devices_do_not_scan(self):
        nm = FakeManager()
        nm.device_list.append(("/two", {"Interface": "wlan1", "State": 100}))
        self.assertEqual(collect(nm)["scan"]["error"]["code"], "interface_unavailable")
        self.assertEqual(nm.calls, [])

    def test_watch_writes_json_lines_and_preserves_existing_captures(self):
        nm = FakeManager()
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            path = Path(directory) / "scan.jsonl"
            with patch("wifi_scan.time.sleep"):
                self.assertEqual(main(["watch", "--json", "--count", "2", "--output", str(path)], lambda: nm), 0)
            values = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual(len(values), 2)
            self.assertEqual(nm.calls, [("wlan0", False), ("wlan0", False)])
            self.assertEqual(main(["scan", "--output", str(path)], lambda: self.fail("Scanner must not be constructed")), 1)
            self.assertEqual(len(path.read_text().splitlines()), 2)

    def test_real_collector_cached_path_does_not_request_scan(self):
        class CachedManager(NetworkManager):
            def __init__(self):
                self.dbus = type("DBus", (), {"DBusException": RuntimeError})
            def properties(self, path, name):
                if name == WIRELESS:
                    return {"LastScan": 11000, "ActiveAccessPoint": "/ap"}
                return access_point()
            def interface(self, path, name):
                return type("Wireless", (), {"GetAllAccessPoints": lambda _: ["/ap"]})()
            def request_scan(self, *args):
                raise AssertionError("Cached reads must not request a scan")
        with patch("wifi_scan.boottime_ms", return_value=12000):
            value = CachedManager().scan("/device", {"Interface": "wlan0"}, True, False, 25)
        self.assertEqual(value["contract_version"], "0.1.0")
        self.assertEqual(value["scan"]["status"], "cached")
        self.assertEqual(value["observations"][0]["strength_percent"], 70)
        self.assertNotIn("security_flags", value["observations"][0])
        self.assertTrue(value["capabilities"]["channel_width_mhz"])
        self.assertIsNone(value["observations"][0]["channel_width_mhz"])
        emit_fixture("linux-generated-cached", value)

    def test_collector_preserves_supported_and_unknown_widths_per_bssid(self):
        class WidthManager(NetworkManager):
            def __init__(self):
                self.dbus = type("DBus", (), {"DBusException": RuntimeError})
            def properties(self, path, name):
                if name == WIRELESS:
                    return {"LastScan": 11000, "ActiveAccessPoint": "/ap"}
                ap = access_point(bssid="AA:BB:CC:DD:EE:01" if path == "/ap" else "AA:BB:CC:DD:EE:02")
                return dict(ap, Bandwidth=80) if path == "/ap" else ap
            def interface(self, path, name):
                return type("Wireless", (), {"GetAllAccessPoints": lambda _: ["/ap", "/unknown"]})()
        with patch("wifi_scan.boottime_ms", return_value=12000):
            value = WidthManager().scan("/device", {"Interface": "synthetic0"}, True, False, 25)
        self.assertEqual([row["channel_width_mhz"] for row in value["observations"]], [80, None])
        self.assertEqual([row["frequency_mhz"] for row in value["observations"]], [5180, 5180])
        self.assertTrue(value["capabilities"]["channel_width_mhz"])
        emit_fixture("linux-generated-widths", value)

    def test_real_collector_waits_before_reading_fresh_access_points(self):
        calls = []
        class FreshManager(NetworkManager):
            def __init__(self):
                self.dbus = type("DBus", (), {"DBusException": RuntimeError})
                self.last_scan = 10000
            def properties(self, path, name):
                if name == WIRELESS:
                    return {"LastScan": self.last_scan, "ActiveAccessPoint": "/ap"}
                calls.append("read-ap")
                return access_point(seen=12)
            def interface(self, path, name):
                return type("Wireless", (), {"GetAllAccessPoints": lambda _: ["/ap"]})()
            def request_scan(self, *args):
                calls.append("request")
                self.last_scan = 12000
        with patch("wifi_scan.boottime_ms", side_effect=[11250, 12000]):
            value = FreshManager().scan("/device", {"Interface": "synthetic0"}, False, False, 25)
        self.assertEqual(calls, ["request", "read-ap"])
        self.assertEqual(value["observations"][0]["freshness"], "fresh")
        emit_fixture("linux-generated-completed", value)


def emit_fixture(name, value):
    directory = os.environ.get("MARINUS_LINUX_FIXTURE_DIR")
    if directory:
        path = Path(directory)
        path.mkdir(parents=True, exist_ok=True)
        (path / (name + ".json")).write_text(json.dumps(value), encoding="utf-8")


class FakeManager:
    def __init__(self):
        self.calls = []
        self.failure = None
        self.device_list = [("/device", {"Interface": "wlan0", "State": 100})]
    def devices(self):
        return self.device_list
    def scan(self, path, device, cached, with_sudo, timeout):
        self.calls.append((device["Interface"], cached))
        if self.failure:
            raise self.failure
        row = normalize_ap(access_point(), False, 12000, None if cached else 11000)
        row.pop("security_flags")
        return envelope(device["Interface"], "2026-10-09T00:00:00.000Z", "cached" if cached else "completed", [row])


if __name__ == "__main__":
    unittest.main()
