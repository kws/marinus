# Initial roadmap

This is an ordered development starting point, not a release schedule.

1. **Agree the shared contract and behavior.** Review the draft, settle interface
   identity, capabilities, raw SSID handling, timestamps, freshness and errors.
   Add cross-backend conformance cases alongside the schema fixtures.
2. **Adapt macOS and Linux.** Expose the same object through library entry points
   and a common CLI, preserving each backend's original measurements. Expand the
   macOS prototype's default-interface support and distinguish unknown radio
   fields. Keep native/legacy output available only as an explicit compatibility
   option if useful.
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
   sign/notarize macOS distribution builds, and add Windows packaging. Audit
   bundled dependencies and retained notices before publishing binaries.
