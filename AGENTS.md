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
`src/structure.jl` adds exploratory thermal and quadrant-wind evidence. Model
groups MODEL_WARM / W, MODEL_COLD / C and MODEL_LOW / L? are not confirmed
tropical/extratropical cyclone types and must not be assigned SSHWS.
Read `docs/MODEL_DETECTION.md` before changing criteria/tracking. The scenario
loader remains separate; see `scenarios/README.md` for its classification rules.
US cyclone definitions and English primary sources are recorded in
`STORM_CLASSIFICATION_US.txt`; classification rules live in `src/classification.jl`.
Nature, basin and 1-minute/10-m wind basis are separate. WPAC STY begins at
130 kt, not the SSHWS C5 threshold of 137 kt. Camera region must not change basin.
After the user's crowded-map screenshot, model mode defaults to active tracks,
small stationary markers and only the selected label/trail. Filters apply to
current-frame diagnostics; full born-track history requires an explicit choice.
An expired selection must not hide the current candidates' information. Keep
hidden filter-menu input scoped just like all other mode-specific controls.

Mode-specific widgets must use `src/ui_scope.jl` input scoping. Hiding a Makie
Menu scene alone does not prevent its invisible hit area receiving mouse input.
Close open dropdowns on mode changes and test actual pointer interactions.
Storm icon art/animation settings live in `assets/storm_tracker/style.toml`;
procedural drawing and PNG frame selection live in `src/storm_icons.jl`. Keep
these rendering settings independent of simulation state and playback speed.

Weather palettes/ranges and particle settings live in `assets/weather/style.toml`;
see `docs/WEATHER_MAPS.md`. Display wind speed in km/h without changing model u/v
(m/s). RH needs actual surface pressure (`pres`) and sigma-level temperature/q,
never substitute MSLP. Old datasets without surface pressure report missing RH.
Wind particles visualize the selected snapshot and do not advance simulation
time; keep data, missing-value handling and view input scopes independent of art.
The default shipped dataset is `datasets/earth_60d/run_0001/output.nc` (60 days,
241 frames); retain the original 10-day dataset. New live sessions support 10/30/60
days, frozen in their creation config. Read the experiment manifest before
describing run provenance; this is an idealized experiment, not observed weather.


Map overlays and hover are documented in `docs/MAP_OVERLAYS.md`. Keep model
W/C/L? separate from illustrative scenarios and do not invent forecast cones.
Vortex radii use four-quadrant tangential-wind annuli, not R34 or SSHWS. Unknown
radii stay missing; censored extents are lower bounds. Icon pixel sizes scale
relatively with radius; only geographic rings represent km. Hover reads the
selected field's original nearest grid cell and must not mutate the clock/pin.

The globe has display interpolation and dense spherical coastlines; preserve
original-cell sampling, missing values, dateline closure and polar behavior.
`Create_Simulation.bat`/`create_simulation.sh` open a form for 1–365 days,
T21/32/63/85, 8/16/24/32 layers, cadence/CPU threads/seed. See
`docs/LOCAL_SIMULATION.md`. Batch jobs use fresh ignored session folders and
only advertise fully validated output; live uses matching grid metadata.
Physics still runs CPU. OpenGL rendering and upstream CUDA capabilities must
not be described as verified project GPU compute; see `docs/GPU_STATUS.md`.


Batch progress is emitted by `src/model_progress.jl` after completed model
steps, not by an async watcher sharing a CPU-bound integration task. Keep
loading/initializing/integrating/validating distinct; 100% integration does not
certify output. Batch workers enter the latest Julia method world after runtime
includes, including when recording errors. Preserve full log backtraces and
structured error status; startup stdout/stderr must reach simulation_setup.log
before GUI imports. Local logs stay out of Git. Cancellation must work even
with broken metadata and must preserve a completed worker exiting normally.


V2 starts with one-time thermal patches; read `docs/THERMAL_EXPERIMENTS.md`.
`src/thermal_patch.jl` defines the compact input shape/limits; `thermal_model.jl`
applies a spectral perturbation to both leapfrog buffers. Checkpoint variables,
clock and worker-task RNG before mutation; errors must roll back. Commands only
apply when paused, and GUI actions require the current live endpoint. Existing
NetCDF frames are immutable pre-edit records; show pending edits and require
new physics output to observe their evolution. Do not export state by calling
run! with a zero period: this library can still advance its clock. Preview rings
show nominal input support, not the nonlocal projected field or storm extent.
Undo is one level until the next integration, not a general time rewind. Keep
one-time heating distinct from sustained forcing or an initialized cyclone.

Live commands run in order so a queued thermal edit cannot be silently skipped
by a following run request; an explicit stop cancels unstarted work.


Windows startup log fix: Create_Simulation.bat owns simulation_setup.log via
stdout/stderr redirection. launch_setup must write the inherited stderr stream,
never reopen the same file (Windows can deny the second writer). Logging failure
must not abort GUI startup or mask the original exception. Direct Julia runs log
to the terminal. Focused checks are setup_logging.jl and setup_launch.jl.


Live persistence uses `src/saved_sessions.jl` and `src/session_snapshot.jl`;
read `docs/SAVED_SESSIONS.md`. Save only a paused acknowledged endpoint with
at least one completed 6h chunk. Bundle state/RNG, relative closed history,
pending edit/one-level undo and inherited command/event journals. Restore into
a fresh workspace using matching Julia/SpeedyWeather/default CPU model; verify
hashes before deserializing. Journals are provenance, never replayed commands.
Check history against the full output grid, not native reduced nlon_max. Preserve
immutable pre-edit frames and RNG across filesystem operations. Batch NetCDF or
restart is not a saved live session. Do not claim arbitrary backend/model resume.


A/B experiments use `src/comparison*.jl`; read `docs/AB_EXPERIMENTS.md`. Fork
from one verified saved session without pending edits, preserving state/clock/RNG
for both. A has no new intervention; B optionally receives a one-time thermal
patch. A runs before B in separate live worker processes under one coordinator.
Compare only new shared 6h endpoints,
never unequal timestamps or the pre-edit initial frame. A/B share scales; B-A
has a symmetric scale and preserves missing data. Wind speed difference is not
the magnitude of vector difference; RH differences are percentage points. Input
copy/hash/model compute belong in the worker. `model_chunk.jl` owns the validated
6h integration used by both live and A/B; preserve its closed-file publication.
Results and final branch archives use relative paths for relocation. Cancel must
stop even with broken metadata and a Julia process stuck handling SIGTERM.

A/B child sessions use internal keep_open_at_limit solely to save the final
endpoint before stopping; they must never integrate beyond the frozen budget.
The default live completion/exit behavior stays unchanged. Closing/cancelling
the coordinator must stop and reap its child even if job metadata is broken.

Viewer scale/palette and A/B delta caches rely on immutable recorded data;
invalidate scales when replacing WeatherData. Reuse A/B plots on the same grid
and cached history only while its payload prefix matches; checksum verification
must still cover cached files. See docs/PERFORMANCE_FIXES.md for regression checks.
Worker cancellation shares process_control.jl (cooperative wait, TERM, bounded
KILL fallback, reap). A/B owns a STOP/EOF stdin pipe; child live workers use
devnull stdin. Give the coordinator at least 6 seconds to clean up its child,
even when a caller requests a shorter grace. Never increment a live command
sequence until its atomic file publication succeeds.


Idealized vortex initialization is in `vortex_profiles.jl`, `vortex_model.jl`,
and `vortex_panel.jl`; read `docs/IDEALIZED_VORTEX.md` before changing it. It is
an approximate coupled perturbation based on an isothermal-virtual-temperature,
flat-surface f-plane reference, not a balanced solution of the full moist
background or a confirmed TC. Keep reference and projected measurements separate.
Use zero buffers for wind-to-vorticity conversion then add the increment: upstream
curl(add=true,radius!=1) divides the existing background by radius as well.
Preserve background divergence and humidity, both leapfrog buffers, immutable
pre-edit frames, one-level undo and RNG checkpoints. Native size and measured
wind projection fit are rejection gates, not values to relax to make a case pass.
A/B metadata has optional intervention="thermal"/"vortex"; absent means thermal.
No new TC/SSHWS classification is implied by inserting the template.


Temperature fields are distinct: temp is atmospheric sigma-layer air temperature,
sst is sea surface temperature, and lst reads the uppermost st soil layer used
for land surface heat exchange. New batch/live output includes sst/st/lsm via
upstream output writers (CPU/CUDA). Mask by nonzero land/ocean fraction; mixed
coastal cells may have both components. Never substitute air temperature or a
drawn coastline for missing surface data. See docs/WEATHER_MAPS.md and
test/surface_temperatures.jl.
