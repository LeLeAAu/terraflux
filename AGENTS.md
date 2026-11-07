# TerraFlux project memory

Before planning or implementing product features, read:

- `note1.txt`: the user's overall simulation goals and V1–V5 roadmap.
- `UI_note.txt`: the user's Storm Tracker requirements.
- `docs/UI_BACKLOG.md`: persistent pending UI work and implementation dependencies.

The user supplied five storm-animation screenshots as visual references in the
conversation. They illustrate layout, colors, icons and animation; their storms,
labels, dates, impacts and statistics are not TerraFlux simulation data. Their
interpretation is recorded in the backlog; the image files themselves are not
stored in this repository.

Preserve the existing 2D/3D data viewer and live simulation workflow when adding
Storm Tracker. A new visual mode must share the simulation clock and underlying
state. Display unavailable quantities as missing, or hide them. Keep scenario
values labeled; never present invented classifications, ACE, ENSO, impacts or
reference climatologies as computed model results.

Keep the backlog current as work is actually implemented and validated. Proposed
implementation ordering in the backlog is a recommendation, not a new user mandate.

Storm Tracker has separate illustrative-scenario and model-candidate sources.
`src/detection.jl` detects pressure/vorticity candidates from the current data;
these are MODEL_LOW / L? and must not be classified as tropical storms or SSHWS.
Read `docs/MODEL_DETECTION.md` before changing criteria/tracking. The scenario
loader remains separate; see `scenarios/README.md` for its classification rules.
US cyclone definitions and English primary sources are recorded in
`STORM_CLASSIFICATION_US.txt`; classification rules live in `src/classification.jl`.
Nature, basin and 1-minute/10-m wind basis are separate. WPAC STY begins at
130 kt, not the SSHWS C5 threshold of 137 kt. Camera region must not change basin.

Mode-specific widgets must use `src/ui_scope.jl` input scoping. Hiding a Makie
Menu scene alone does not prevent its invisible hit area receiving mouse input.
Close open dropdowns on mode changes and test actual pointer interactions.
Storm icon art/animation settings live in `assets/storm_tracker/style.toml`;
procedural drawing and PNG frame selection live in `src/storm_icons.jl`. Keep
these rendering settings independent of simulation state and playback speed.
