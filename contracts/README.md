# Draft shared scan contract

**Status: design draft, version 0.1.0. Neither backend prototype conforms yet.**
The schema and fixtures define a starting point for discussion and adapters;
passing fixture validation is not a claim of platform conformance.

The draft [scan schema](draft/scan.schema.json) defines one result per interface.
Examples in [draft/fixtures](draft/fixtures/) are entirely synthetic, including
documentation-only locally administered BSSIDs.

## Envelope and measurements

- `contract_version` identifies this format and its documented behavior.
- `backend` identifies platform, implementation and independently released version.
- `interface` identifies the device within its platform; IDs are not globally
  interchangeable, and driver can be unknown.
- `capabilities` describes implementation support, not whether an AP happened to
  expose a measurement in this scan. A supported field may still be `null`.
- `scan` distinguishes a completed request, an explicit cached read and failure,
  with UTC timestamps and a structured error on failure.
- `observations` retains each observed BSSID; it never adds saved-only placeholders
  or merges by SSID. Identifiers unavailable through privacy controls are `null`.

Keep native `rssi_dbm`, `noise_dbm` and/or `strength_percent` in their named units.
Do not derive dBm from a quality percentage, substitute zero for an unknown
measurement, or rescale against the strongest observation in the current scan.
Consumer-side display/interpolation mappings must be fixed within a survey.
Having signal data is not a guarantee of calibration across hardware/platforms.

`ssid` is display text, with `""` representing a known empty/hidden SSID. `null`
means unavailable. `ssid_bytes_base64` preserves raw bytes where available; do
not reconstruct them from lossy display text. `bssid` uses lowercase colon-separated
octets or `null` when unavailable. `connected` can be unknown (`null`).

## Freshness and errors

Request completion does not prove that every returned observation is new.
`freshness` is `fresh`, `cached` or `unknown` relative to the current scan request.
`last_seen_age_ms` is an elapsed age, not an absolute boot-time timestamp.
`last_seen_resolution_ms` makes source precision explicit; milliseconds in the
field name do not imply millisecond measurement accuracy. A cached read has no
new request against which to claim freshness.

A failed fresh request produces `status: "failed"`, an error and an empty
observation list. It must not become a successful cached result. Core error
codes distinguish permission denial, scan timeout, an unavailable interface,
unsupported operations and other backend errors. Platform-native diagnostic
details can be included in the error message without exposing credentials.

The schema constrains shape, ranges and the failure envelope. The validation
script also checks fixtures against advertised capabilities and cached-mode
freshness. Future backend conformance tests must exercise actual request/wait,
permissions, timing and native-field mapping with controlled backend inputs.

## Compatibility and next decisions

The existing Linux `schema_version: 1` and macOS network arrays are prototype
formats and are not equivalent to this contract. Version 0.1.0 is deliberately
unstable while adapters and consumers settle the design. Stabilize semantics
before advertising contract 1.0.0.

Open decisions include interface enumeration envelopes, watch/stream events,
cancellation, security representation and the survey/session format. Security
and platform-specific extensions are omitted from this first shared scan draft
rather than pretending the existing backend encodings are equivalent.
