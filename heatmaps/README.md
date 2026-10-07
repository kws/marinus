# Survey and heatmap core

Planned; the repository does not yet generate heatmaps.

This is the intended home for shared survey/session data, sample positions,
floor-plan scaling, interpolation, uncertainty and rendering/export. Platform
wrappers should call this core with the same scan objects rather than each
implementing its own heatmap logic.

Useful relative coverage is the goal. Preserve the native signal unit, use a
fixed mapping across a survey, keep individual BSSIDs and treat stale/missing
measurements explicitly. Cross-platform results need not be numerically
identical to describe useful coverage patterns.

See [architecture](../docs/architecture.md) and [roadmap](../docs/roadmap.md).
