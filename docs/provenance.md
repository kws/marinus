# Source provenance

Marinus starts with a new Git history. This record identifies reused material,
its source and the retained license notices.

## macOS import

Imported on 7 October 2026 from:

- Repository: <https://github.com/kws/macwifi>
- Branch at import: `codex/swift-cli`
- Commit: [`0daedb1da835e6d05ffd4fd8e3d03306f4d541b0`](https://github.com/kws/macwifi/commit/0daedb1da835e6d05ffd4fd8e3d03306f4d541b0)
- Original upstream: <https://github.com/jaisonerick/macwifi>
- Original command/output behavior: <https://github.com/jaisonerick/macwifi-cli>

The import consists of Swift sources, their tests, Swift package/build
configuration, app packaging and build/test/notarization scripts.

The initial Marinus changes rename the package, executable, module, worker flag,
environment variables and app to Marinus; set the app identifier to
`io.github.kws.marinus` and the development version to `0.1.0`; and package both
original MIT notices with the new project license. The scanning and inherited
diagnostic behavior otherwise remain the prototype's behavior.

[import-manifest.json](import-manifest.json) records each original path, its
destination and the original file's SHA-256 digest before these import changes.
The preserved upstream license texts are in [licenses](../licenses/).

## Linux import

The NetworkManager probe and five unit tests were authored during this project's
feasibility work and imported from the local `linux-poc` directory. Their original
digests are in the same manifest.

The Linux import consists of source and tests. The Linux guide contains an
anonymized summary of the earlier hardware test.

## Ongoing changes

Record the source, version/commit, license and affected paths when importing new
third-party material. Add its license text and update THIRD_PARTY_NOTICES.md.
