# Linux NetworkManager prototype

The Python collector talks directly to NetworkManager over system D-Bus and
implements the [shared draft contract](../../contracts/README.md). Each scan
selects one interface; choose explicitly when several devices are available.
`watch --json` emits one result per line and retains its selected device.

The library entry points are `NetworkManager.devices()` and `NetworkManager.scan()`.
`collect()` adds selection and structured failure handling; the CLI uses it.

## Run

Requires Linux, Python 3.10+, NetworkManager and the distribution's Python `dbus`
module. From the repository root:

```sh
python3 backends/linux/wifi_scan.py interfaces --json
python3 backends/linux/wifi_scan.py scan --interface wlan0 --json
python3 backends/linux/wifi_scan.py scan --cached --json
```

Replace `wlan0` with a reported interface name. Without `--interface`, the only available
Wi-Fi device is selected. Several devices require an explicit choice. Scanning does not connect, disconnect, change profiles
or read passwords.

Fresh requests use NetworkManager's existing permissions. Desktop and SSH
sessions can have different PolicyKit authorization. If cached reads work but
fresh requests are denied, that is an authorization result, not evidence that
the adapter cannot scan. An administrator can decide an appropriate policy for
unattended users; this repository does not install a policy override.

For diagnosis on a machine with existing passwordless sudo:

```sh
python3 backends/linux/wifi_scan.py --scan-with-sudo
```

That explicitly runs only a fixed `RequestScan` call through
`sudo -n /usr/bin/gdbus`; the collector stays unprivileged. It does not modify
PolicyKit or install software.

## Observation semantics

- `strength_percent` preserves NetworkManager's native 0..100 value; it is not
  normalized against the strongest AP in each scan.
- Every BSSID is retained, including shared and hidden/unknown SSIDs. Raw SSID
  bytes are preserved as Base64.
- Unsupported dBm/noise/width measurements are `null`; no dBm is invented from
  a percentage.
- Age uses Linux CLOCK_BOOTTIME. NetworkManager's `LastSeen` has one-second
  resolution even though the calculated age is expressed in milliseconds.
- A fresh request waits for `LastScan` to advance beyond the previous completion
  and reach the request timestamp. Request acceptance is not scan completion.
- Completed scans can retain cached entries. Observation `freshness` distinguishes
  newer, older and unknown/same-second readings. Known cached observations should
  not become new survey measurements.
- `--cached` is explicit. Failed fresh requests return structured errors and
  exit 1 rather than silently falling back to cached data.

## Earlier feasibility checks

On 7 October 2026, two scan rounds completed on Pop!_OS 22.04 with NetworkManager
1.36.6 and kernel 6.12.10:

| Driver | BSSIDs in each round | Strength ranges | Approximate scan duration |
| --- | --- | --- | --- |
| `b43` | 8 / 6 | 34–97% / 34–97% | 1 second |
| `rtw_8821cu` | 6 / 6 | 45–82% / 44–84% | 12 seconds |

The Realtek adapter reported both 2.4 GHz and 5 GHz observations and multiple
BSSIDs sharing an SSID. The Broadcom adapter retained some cached observations
after each request. Unprivileged cached reads worked in the SSH session; fresh
requests required the explicit diagnostic sudo path. No network policy changes
or package installations were needed.

This was stationary collection, not a walk-around survey or heatmap validation.

## Tests and references

```sh
python3 -m unittest discover -s backends/linux -v
```

Synthetic tests cover units, BSSID/SSID byte preservation, age/freshness, scan
completion, timeout, interface selection and capture-file preservation. They run without Linux or the D-Bus binding.

NetworkManager documentation:
[access-point properties](https://networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager.AccessPoint.html)
and [scan requests/completion](https://networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager.Device.Wireless.html).
