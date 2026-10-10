# Changelog

## Unreleased

- Use compact desktop toolbars, a dense access-point table and a fixed status
  bar. Remove in-window branding and marketing copy; keep scrolling inside the
  table with sticky column headings and system light/dark colors.
- Fit the Windows desktop startup window to the monitor work area when display
  scaling would otherwise place its frame below the taskbar. Validate the x64
  development installer and real GUI scans/exports on Windows 11.

- Unify survey scan and interface-enumeration JSON across macOS, Linux and
  Windows; add macOS/Linux repeated capture and explicit cached reads, preserving
  native units and unknown freshness. Retain macOS scans through `--legacy`.
- Add an initial Tauri desktop explorer with interface selection, scans, cache
  reads, cancellation, filtering, native JSON export and a synthetic demo.
- Add CLI installer scripts for macOS/Windows/Linux and desktop packaging with
  signing/notarization hooks, locked dependencies and retained dependency notices.
- Add a Windows Native WLAN library and CLI with fresh/cached scans, interface
  selection, native RSSI and raw identifiers, draft-contract JSON, repeated
  measurements and JSON Lines export. Add synthetic behavior/schema tests and
  a Windows CI/publishing job.
- Start Marinus with a fresh Git history and MIT licensing, retaining both
  original macwifi and macwifi-cli notices and import provenance.
- Import and rename the Swift macOS scan/diagnostic prototype and its tests.
- Import the NetworkManager Linux scan prototype and its tests.
- Add a draft shared scan contract and synthetic examples, architecture and
  roadmap, backend guides and CI checks.

There is no tagged Marinus release yet. The macOS prototype's `0.1.0` version
identifies this development baseline.
