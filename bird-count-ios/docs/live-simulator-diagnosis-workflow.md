# Live Simulator Diagnosis Workflow

Companion to [`live-simulator-testing-plan.md`](live-simulator-testing-plan.md)
steps 4–5. This is the manual, repeatable procedure for using the hydrated
Simulator + `DiagnosticsLog` to root-cause a timing- or interaction-dependent
UI bug. It is not automated: XCUITest's own synchronization (it waits for the
app to go "idle" before/after each action) tends to absorb exactly the races
this tooling exists to catch, so driving the repro by hand — real touches,
real frame timing — is the point, not a gap to fix.

## 0. Prerequisites

- `data/live-sim-dataset.json` present (see the plan's dataset-lifecycle
  section for how to (re)generate it).
- A Simulator device booted (`make sim-live` boots one if needed).

## 1. Vary timing deliberately (plan step 4)

Simulator CPU/animation speed is not representative of a device and drifts
run-to-run. Rather than treat that as noise, use it as a diagnostic knob —
races that only show up "sometimes" often show up "always" at 0.1× speed:

- **Slow Animations**: Simulator menu bar → Device → Slow Animations (⌘T also
  toggles it). Drops UIKit/SwiftUI animation playback to ~1/10 speed —
  the single highest-signal knob for catching an intermediate-state bug on
  camera, since it turns a 1-frame glitch into something visible for seconds.
- **Debug → Slow Animations** is the same toggle; Simulator also exposes
  **Hardware → Restart** to reset to a clean CPU/thermal state if a session
  has been running long and timing has drifted from thermal throttling.
- **Instruments (Core Animation template)**: attach via Xcode ▸ Open
  Developer Tool ▸ Instruments for frame-by-frame hitch analysis when
  `log stream` timestamps alone aren't enough to tell which frame a state
  transition landed on.
- **Programmatic timing control**: intentionally not built speculatively.
  If a specific bug's diagnosis reveals a need to freeze/step a clock (e.g.
  the deferred `Task { @MainActor in ... }` scroll correction in
  `BottomAnchoredScrollView`), add a narrowly-scoped injectable clock there
  when that need is concrete — see `Not done` items below for where this
  first came up.

## 2. Reproduce with logging + recording (plan step 5)

1. `make sim-live DATASET=data/live-sim-dataset.json` — builds, installs, and
   launches the real (no-mock) app hydrated with the fixture.
2. In a second terminal, start the log stream filtered to the category you're
   chasing (`scroll`, `gesture`, `animation`, `sync` — see `DiagnosticsLog.Category`):
   ```
   xcrun simctl spawn booted log stream \
     --predicate 'subsystem == "org.antoninus.birdcount"' \
     --level debug --style compact
   ```
3. In a third terminal (or right before step 2 if you want the video to
   include app launch), start a screen recording:
   ```
   xcrun simctl io booted recordVideo diagnosis-$(date +%s).mov
   ```
   Stop it with Ctrl-C when done.
4. Reproduce the interaction by hand, with Slow Animations on if the bug is
   timing-sensitive:
   - Scroll bug: filter to a short list, scroll partway, clear the filter
     while scrolling, quick-add a species via right-swipe.
   - Swipe-stuck bug: left-swipe a row to reveal Undo/Details, then
     immediately (mid-animation) tap elsewhere or start another swipe before
     the reveal settles.
   - Highlight bug: add a new observation and watch the count-badge
     highlight color in the recording; this one is a visual-only check (no
     log signal expected — see the step-6 findings below).
5. Stop the log stream and recording. Correlate: the log stream's timestamps
   and the recording's timestamp overlay (Simulator recordings are wall-clock)
   let you find the exact log line active when the visual glitch appears in
   the video.

## 3. Write up findings

One doc per bug, in `bird-count-ios/docs/`, following the precedent and level
of detail in `scroll-to-bottom.md`: the problem, the log/video evidence,
attempts and why each failed, and the true root cause once found — *before*
attempting a fix. See `live-sim-bug-findings.md` for the current pass on the
three known issues from the original testing doc.
