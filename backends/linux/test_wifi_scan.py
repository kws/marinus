import base64
import unittest
from unittest.mock import patch

from wifi_scan import normalize_ap, wait_for_scan


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


if __name__ == "__main__":
    unittest.main()
