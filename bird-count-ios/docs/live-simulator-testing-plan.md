# Live Simulator Testing — Implementation Plan

Source requirements: [`docs/LiveSimulatorTesting.md`](../../docs/LiveSimulatorTesting.md).

## Implementation status

Steps 1 (hydration), 2 (build/launch convention), and 3 (logging scaffolding,
scroll + gesture + animation instrumentation) are implemented:

- `BirdCount/Diagnostics/DiagnosticsLog.swift` — the `#if DEBUG`-only logging seam.
- `ObservationStore.loadLiveSimDatasetIfRequested()` — launch-time hydration via
  `-LiveSimDataset <path>` / `LIVE_SIM_DATASET` env var, reusing `mergeDTOs`.
- `BottomAnchoredScrollView` and `SpeciesRow` instrumented with `.scroll`,
  `.gesture`, and `.animation` log calls at the points described in step 3.
- `scripts/pull-live-sim-dataset.mjs` / `scripts/shift-live-sim-dataset.mjs` —
  the export and date-shift/filter tooling from steps 1 and the dataset-lifecycle
  section below.
- `make sim-live` (`DATASET=path/to/file.json`) — builds, installs, and
  launches the real app hydrated with a dataset.

A dataset has since been pulled from prod (20,000 observations, capped via
`--max`; prod's shared partition had 200k+ and climbing, far more than a
single realistic fixture needs) and verified: `make sim-live` builds,
installs, and launches the real app with it hydrated via `mergeDTOs`, showing
real taxa with no crash. The resulting fixture
(`data/live-sim-dataset.json`, ~5.5MB) contains no observer/location data in
this pull, but committing it is still a call for the repo owner (real user
activity, even de-identified) rather than something to commit automatically —
see the dataset-lifecycle section below.

Fixing the pull also required an unplanned but necessary detour: the backend
authorizer (`bird-count-backend/api/src/authorizer.ts`) had a pre-existing bug
that rejected *all* M2M (client-credentials) tokens on both dev and prod,
because Cognito M2M tokens carry a `client_id` claim that shadowed the
scope-based M2M branch. Fixed, tested (added a regression test), and deployed
to both dev and prod (scoped `-target` apply to avoid unrelated infra drift
already pending in prod state).

Steps 4–6 are now documented:

- [`live-simulator-diagnosis-workflow.md`](live-simulator-diagnosis-workflow.md) —
  step 4 (timing-variability knobs: Slow Animations, Instruments, a
  need-driven injectable clock if one turns out to be necessary) and step 5
  (the repeatable manual reproduce → log stream → screen recording →
  correlate workflow).
- [`live-sim-bug-findings.md`](live-sim-bug-findings.md) — step 6, applying
  the tooling to the three known issues. **Caveat**: this environment has no
  way to inject real touch/trackpad input into the Simulator (no
  `idb`/`cliclick`, and `simctl` has no touch command), so these are
  code-grounded hypotheses with a specific confirming log signal named for
  each, not confirmed live captures. A human running the diagnosis workflow
  is the next step for each.

## Goal

Build testing infrastructure that runs the **real app** (no mocks) in the iOS
Simulator against a **realistic, large dataset**, with enough instrumentation
to diagnose timing- and interaction-dependent UI bugs that unit tests and
scripted UI tests can't catch — scroll-anchoring drift, stuck swipe-action
animations, and simulator-only visual artifacts (e.g. the green add-highlight).

This is infrastructure work: the three example bugs are motivation and
acceptance criteria for the tooling, not something this plan fixes directly.

## Why unit/e2e tests miss these bugs

- `TestsCore`/`Tests` exercise stores and view models with small, synthetic
  data and no real `UIScrollView`/UIKit animation timing. The scroll bug in
  `docs/scroll-to-bottom.md` was only reproducible with ~11,000 rows and real
  SwiftUI↔UIKit geometry propagation delays.
- `UITests/ScreenshotTests.swift` (XCUITest) drives the compiled app but
  currently just captures fastlane snapshots — it doesn't assert on
  intermediate animation states or timing races, and XCUITest's own
  synchronization (waiting for the app to go "idle") tends to paper over the
  exact races we need to catch.
- Simulator-vs-device rendering/timing differences (the green highlight, CPU
  speed) are invisible to CI unit tests by construction.

## Plan

### 1. Realistic dataset hydration

- One-time export script against `bird-count-backend` (using the existing
  `op run`-wrapped `make aws`/API access — see `bird-count-backend/Makefile`)
  that pulls a real observation history (a full season or more) via the
  sync/query API in `bird-count-backend/api/src`.
- Save the pulled payload as a fixture under `bird-count-ios/data/`
  (alongside the existing `checklist*.json`/`taxonomy.json` fixtures),
  e.g. `data/live-sim-dataset.json`, committed to the repo so the tooling
  doesn't depend on live prod access to run.
- Write a small date-shifting transform (Node or Swift script under
  `bird-count-ios/scripts/`) that shifts all observation timestamps forward
  so the most recent observation is "today" — preserves realistic
  distribution/clustering while keeping the app's date-range logic
  (`DateRangeStore`) exercising real "recent" paths on every run.
- Add a debug-only hydration path: on launch, if a launch argument/environment
  variable (e.g. `-LiveSimDataset <path>` or `LIVE_SIM_DATASET=1`) is set,
  `ObservationStore` loads the fixture instead of (or in addition to) normal
  persisted state, bypassing CloudKit/P2P sync entirely. Gate this behind
  `#if DEBUG` so it can never ship in a release build.

### 2. Launch/build convention for "full app, no mocks"

- Confirm the Simulator target builds the real `NetworkSyncTransport`
  path (not `MockSyncTransport`) for this testing scheme — add a dedicated
  Xcode scheme or `xcodebuild` invocation (`make sim-live` or similar) that:
  - builds `BirdCount` (not the existing test target),
  - installs to a designated Simulator device,
  - launches with the hydration launch argument from step 1.
- Keep this separate from `Tests`/`TestsCore`/`UITests` schemes so CI is
  unaffected — this is a manual/local diagnostic tool, not a CI gate.

### 3. Event/state-transition logging scaffolding

- Introduce a single lightweight logging seam (there is currently no
  `os.Logger`/logging usage anywhere in `BirdCount` — this is new, not a
  refactor of existing logging):
  - A `DiagnosticsLog` wrapper around `os.Logger` with per-subsystem
    categories (`scroll`, `gesture`, `sync`, `animation`).
  - Cheap enough to leave compiled into Debug builds permanently (guard with
    `#if DEBUG`), since these are exactly the builds this tooling targets.
- Instrument the known trouble spots first, since they're already partially
  understood from `docs/scroll-to-bottom.md`:
  - `BottomAnchoredScrollView`: log content-set identity changes, sentinel
    scroll triggers, and `onScrollGeometryChange` contentSize vs actual
    `UIScrollView.contentSize` (the exact divergence documented in
    scroll-to-bottom.md).
  - Swipe-to-reveal (undo/details) views: log gesture phase transitions
    (began/changed/ended/cancelled) and the view's resting/animating/focused
    state, so a "stuck intermediate state" shows up as a state machine that
    never reached its terminal state rather than a visual-only symptom.
  - Add-observation highlight: log when the highlight animation starts/ends
    and its rendered opacity/color, to correlate against screen recordings.
- Export logs via the Simulator's unified log (`log stream --predicate ...`
  filtered to the app's subsystem) so a diagnosis session is: reproduce in
  Simulator → capture log stream + screen recording → correlate timestamps.

### 4. Timing/speed variability

- Simulator CPU/animation speed differs run-to-run and from real devices.
  Add a way to deliberately vary it during diagnosis rather than treat it as
  noise:
  - Document using `xcrun simctl` + Simulator's own "Slow Animations" /
    Debug menu, and Instruments' Core Animation template, as the two knobs
    for slowing down animation timing to catch races visually.
  - For programmatic control, consider an injectable "clock"/scheduler
    seam only where a specific bug needs it (e.g. the scroll teardown/rebuild
    sequence) rather than a blanket app-wide time abstraction — keep this
    need-driven, not speculative.

### 5. Diagnosis workflow (the actual deliverable)

Document (in this repo, `bird-count-ios/docs/`) a repeatable workflow:

1. Build & launch via the step-2 scheme with the hydrated dataset.
2. Start `log stream` filtered to the relevant category (`scroll`, `gesture`,
   `animation`) alongside `xcrun simctl io booted recordVideo`.
3. Reproduce the interaction (fast scroll + add, rapid swipe, quick add-tap).
4. Correlate log timestamps against the recording to identify the exact
   frame/state where the UI diverges from the model.
5. Capture findings back into a per-bug doc (following the precedent set by
   `docs/scroll-to-bottom.md`) before attempting a fix.

### 6. Apply to the three known issues (validation, not scope)

Use the tooling above to produce a root-cause doc for each, confirming the
infrastructure is sufficient before considering this plan "done":

- Persistent scroll-offset issue (~10px short) after adding an observation —
  likely a variant/edge case of the scroll-to-bottom work already documented.
- Swipe-to-reveal undo/details stuck in an intermediate animation state with
  a stuck blue-focus visual state.
- Simulator-only green highlight on add-new-observation that's not visible
  on-device (likely a Simulator color-space/rendering artifact — confirm via
  screen recording comparison, not code, before assuming it's a real bug).

## Out of scope

- Fixing the three example bugs (tracked separately once diagnosed).
- Any change to CI-run `Tests`/`TestsCore`/`UITests` — this tooling is
  additive and manual/local-only.
- General-purpose production logging/telemetry — the `DiagnosticsLog` seam
  above is scoped to `#if DEBUG` diagnostic use.

## Dataset lifecycle and filtering

- The pulled dataset is a **committed reference fixture** under
  `bird-count-ios/data/` (as in step 1) — not regenerated per-run. Refresh is
  manual and infrequent: the export script from step 1 doubles as the refresh
  tool, re-run by hand when a new/larger dataset is needed, with the result
  committed like any other fixture update.
- Partial/incremental dataset needs (e.g. "just today's checklist" vs. "full
  season" to reproduce different scroll-length bugs) don't need a second
  hydration mechanism. Fold this into the date-shifting transform from step 1:
  the same script that shifts timestamps to "today" also accepts a range
  filter (e.g. `--since <date>` / `--days N`) and mutates/subsets the
  committed dataset accordingly before hydration. One general filter-and-shift
  step, not separate fixed and partial code paths.
