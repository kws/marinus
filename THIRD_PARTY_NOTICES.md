# Third-party notices

Marinus includes code and command/output behavior derived from these MIT-licensed
projects. Preserve this file, the root LICENSE and the license texts below when
redistributing the relevant source or binaries. The macOS packaging script
includes all of them in the app's Resources directory.

## macwifi

- Project: <https://github.com/jaisonerick/macwifi>
- Copyright (c) 2026 Jaison Reis
- License: MIT; complete original text: [licenses/macwifi.MIT.txt](licenses/macwifi.MIT.txt)
- Use: CoreWLAN scanning and macOS application/authorization foundations, imported
  through the Swift fork described in [provenance](docs/provenance.md).

## macwifi-cli

- Project: <https://github.com/jaisonerick/macwifi-cli>
- Copyright (c) 2026 Jaison Erick Reis
- License: MIT; complete original text: [licenses/macwifi-cli.MIT.txt](licenses/macwifi-cli.MIT.txt)
- Use: inherited command names, help/output conventions and related behavior
  implemented in the Swift prototype.

## Runtime dependencies

The macOS backend uses Apple's system frameworks. The Linux backend uses the
distribution-provided Python D-Bus binding and the installed NetworkManager
service. Those runtime dependencies are provided by the host system. Development
validation uses `jsonschema`, installed separately via `requirements-dev.txt`.

The Windows backend uses .NET 10 and the system-provided Native WLAN API. A
self-contained Windows distribution includes the .NET runtime. Its publish
target copies the runtime package's original `LICENSE.TXT` and complete
`THIRD-PARTY-NOTICES.TXT` into `licenses/dotnet/`, alongside Marinus's license and
the retained upstream notices. Framework-dependent builds use the host's .NET
installation instead. Keep these distribution files with the executable.
