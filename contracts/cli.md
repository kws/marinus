# Backend CLI protocol 0.1.0 (draft)

All three backends implement the same survey commands. Executable discovery and
permission handling remain platform-specific; the desktop bridge knows the
packaged backend path and invokes it without a shell.

```text
marinus interfaces --json
marinus scan --interface ID --json [--cached] [--timeout SECONDS] [--output FILE]
marinus watch --interface ID --json [--timeout SECONDS] [--interval SECONDS]
              [--count N] [--output FILE]
```

`interfaces --json` returns one [enumeration envelope](draft/interfaces.schema.json),
including an empty list when no adapter exists. It does not request a radio scan.
IDs are macOS interface names, Linux device names, or Windows adapter GUIDs.
An omitted scan interface selects the only available adapter; multiple adapters
require an explicit choice. Watch retains the initial adapter throughout capture.

Scan returns one [scan envelope](draft/scan.schema.json). Watch returns one compact
JSON object per line and stops on the first failed scan. The interval is a pause
after completion, defaulting to five seconds. Timeout values are seconds; macOS
also accepts its original duration syntax. Platform scan deadlines default to
90 seconds on macOS (including privacy authorization), 25 on Linux and 15 on
Windows. Permission denial and timeout are failures, with empty observations;
there is no automatic cache fallback. `--cached` applies only to scan.

Standard output contains JSON only when `--json` is used. Diagnostic text belongs
on standard error. Without `--json`, commands show human-readable results.
`--output` always writes JSON/JSON Lines, opens a new file before initiating a
scan, and preserves existing files. Exit codes: 0 success, 1 backend/file failure,
2 invalid arguments, 130 user cancellation. Ctrl+C ends capture. Cancellation
stops waiting/collecting; an accepted OS radio request may still finish.

The macOS scan's former array/SSID-summary format is available through
`scan --legacy [--bssids] [--json]`. The diagnostic `info` and explicit Keychain
`password` commands retain their previous behavior. The shared survey commands
never read saved profiles or passwords. The Linux prototype's earlier JSON shape
is replaced; its `--interfaces` spelling remains as an enumeration alias.

This remains a development contract. Synthetic conformance tests and generated
schema checks cover adapter mappings and controlled request behavior; they do
not establish permission behavior or radio accuracy on every installed platform.
