# Security and privacy

Marinus is experimental and has no supported stable release yet.

Report vulnerabilities privately through
[GitHub private vulnerability reporting](https://github.com/kws/marinus/security/advisories/new).
If that channel is unavailable, open an issue asking for a private contact
without disclosing exploit details, credentials or sensitive captures.

Wi-Fi identifiers, survey positions and floor plans can be sensitive. Keep raw
captures local and use synthetic data in reports and test fixtures. The current
scanning prototypes operate locally; they do not upload results or change Wi-Fi
connections. The inherited macOS `password` command accesses the Keychain only
when explicitly invoked and prints the result to the caller; avoid capturing
that output in logs or bug reports.

Use normal platform authorization. The Linux diagnostic sudo option invokes
only a fixed NetworkManager scan request; it is not a general privileged helper
or an installed permission policy. Changes to authentication, IPC, signing or
privilege boundaries require particular care and relevant verification.
