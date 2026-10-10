# Initial roadmap

This is an ordered development starting point, not a release schedule. The
common survey CLI and initial desktop explorer are now implemented. Installer
foundations are described in [packaging](packaging.md); signed distribution and
installed-platform validation remain outstanding.

1. **Agree the shared contract and behavior.** Review the draft, settle interface
   identity, capabilities, raw SSID handling, timestamps, freshness and errors.
   Add cross-backend conformance cases alongside the schema fixtures.
2. **Validate the adapted macOS and Linux backends.** The common survey CLI now
   preserves each backend's original measurements, selects interfaces explicitly
   and distinguishes unknown radio fields. macOS keeps legacy output as an
   explicit compatibility option. Verify the new protocol on installed hardware.
3. **Expand Windows validation and add a replay backend.** The initial Windows
   library/CLI waits for scan notifications, returns the draft contract and
   exports repeated measurements. Verify consent, multiple interfaces, hidden
   SSIDs and timeout behavior on more hardware. Replay synthetic or user-supplied
   captures for development and deterministic downstream tests.
4. **Build the shared survey/heatmap core.** Define the survey/session format,
   sample coordinates and floor-plan scale; implement interpolation, consistent
   strength scales, uncertainty and exports. Heatmaps belong in Marinus itself.
5. **Validate useful surveys.** Walk a real space with each supported backend,
   compare coverage patterns and record adapter-specific limits. The existing
   Linux checks are stationary scans, not a completed heatmap validation.
6. **Package releases.** Document administrator-controlled Linux authorization,
   sign/notarize macOS distribution builds, and validate the Windows installers. Audit
   bundled dependencies and retained notices before publishing binaries.
