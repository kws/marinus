# Contributing

Marinus is at the prototype stage. Open an issue for substantial API or contract
changes so the platform backends and survey core can agree on behavior. Small
fixes and documentation improvements are welcome as pull requests.

## Local checks

Create a virtual environment and install `requirements-dev.txt`, then run
`make test` and `make check`. Each backend also has its own instructions.
CI runs synthetic tests; live scans, permission dialogs and signing identities
need separate hardware checks when a change affects them. Describe those checks
and their limits in your pull request.

For Windows changes, install the .NET 10 SDK and run `make test-windows` on
macOS/Linux, or the Windows backend's PowerShell test script. These tests use
synthetic native observations and validate generated JSON against the draft
contract. They can run on a machine without a Wi-Fi adapter.

## Data and dependencies

Use synthetic fixtures. SSIDs, BSSIDs, coordinates and floor plans may identify
people or places; do not commit real captures without the owner's deliberate
permission. Never include credentials, Keychain values or signing secrets.

Preserve original signal units, unknown values and individual BSSIDs. A schema
change should include its semantics, versioning impact and fixture updates.
Do not introduce a new runtime dependency without explaining its purpose,
platform support, packaging and license implications.

Contributions are accepted under the project's MIT license. Retain third-party
notices, and record provenance for imported code. Be respectful and constructive
in issues, reviews and discussions.
