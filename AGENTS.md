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
