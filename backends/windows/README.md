# Windows backend

Planned; there is no Windows implementation in this repository yet.

The starting design uses the Native WLAN API:

- Enumerate Wi-Fi interfaces and report backend capabilities.
- Request a scan with `WlanScan` and wait for its completion notification.
- Read individual BSS observations with `WlanGetNetworkBssList`, retaining RSSI
  in dBm, BSSID and SSID bytes where available.
- Handle consent, permission failures, timeouts and unavailable measurements
  explicitly, following the [draft shared contract](../../contracts/README.md).

Implementation and permissions must be checked on actual Windows hardware.
See the [roadmap](../../docs/roadmap.md) before committing to a public API.
