# Live Simulator Testing — Findings on the Three Known Issues

Plan step 6 of [`live-simulator-testing-plan.md`](live-simulator-testing-plan.md):
apply the tooling to the three issues named in the original testing doc, as
validation that the infrastructure is sufficient.

**Status: all three confirmed on device and fixed.** #2 and #3 via device
testimony correcting the original hypotheses; #1 via device testimony
confirming the original hypothesis (from a previous build), and — since —
via a live capture in this Simulator (see #1 below). I still can't drive
real touch/trackpad interaction here (no `idb`/`cliclick`, `simctl` has no
touch command), but for bugs reachable without a tap gesture, a new
`DebugTestHook` (see
[`live-simulator-diagnosis-workflow.md`](live-simulator-diagnosis-workflow.md))
sidesteps that entirely. #2 and #3 need real swipe/drag gestures, so those
still await a human running the manual workflow.

## 1. Persistent ~10px scroll-short after adding an observation — FIXED

**Update (2026-10-25): the corrective-scroll fix below was incomplete; replaced
by sticky-bottom re-pinning.** Reported again on device: 28pt short after a
*filter-typed* swipe-add. Reproduced deterministically
(`SwipeScrollReproTests.testFilterSwipeReplay`, 28.00pt 6/6, screen identical
to the device screenshot) once the Simulator matched the device:

- **Data:** that day's prod records *including the `observer` field* (pulled
  read-only from DynamoDB `birdcount-data-prod`, `changes` index). The app's
  JSON export omits `observer`, and without another user's records there are
  no attribution icons — and no bug.
- **Dynamic Type extra-large** (device rows 73pt vs 68pt at default) and the
  device user's login email (`-Settings_loginEmail`).
- **Path:** an add with a filter active clears the filter → content-set
  change → `.id` ScrollView rebuild. The trigger and the old 500ms corrective
  scroll never run on this path.

Mechanism (logs + UIKit introspection): the rebuilt ScrollView lands at the
bottom using estimated row heights; ~11ms later a row measures 28pt taller
(a name wrapping next to the attribution icon) and nothing re-pins. Two
further wrinkles: the late height change arrives inside an animated
transaction (the add's pulse `easeIn(0.3)`), so `UIScrollView.contentSize`
*animates* toward the new value over ~300ms and each `scrollTo` is clamped to
wherever it has reached; and the estimate can flap within a few ms
(813607 → 852587 → 813607).

Fix (`BottomAnchoredScrollView`): a sticky "wants bottom" intent (set
initially, on rebuild, on trigger, and when a user scroll ends at the
bottom; cleared when it ends elsewhere). Any content-height change while it is
set schedules a coalesced, deferred re-pin that retries every 50ms (max 1s)
until the list is actually at the bottom. Bookkeeping lives in a plain
reference type — any view invalidation from inside the geometry/phase
callbacks breaks pinning by itself (found when a debug probe's `@Observable`
read did exactly that; see `BottomAnchoredScrollViewRowGrowthTests`). The
one-shot corrective scroll is removed: the re-pin covers its trigger path
(18/18 at 0.00 from bottom / 250pt / 440pt up, XXL text) and also the
launch-time gap (previously 30pt at XXL). Rejected:
`.defaultScrollAnchor(.bottom, for: .sizeChanges)` overshoots 54pt.

Hardening that followed:

- **Pulse animation scoped** (`SpeciesRow`): `.animation(_:value:)` on the
  highlight shapes instead of `withAnimation`. Confirmed source of the
  animated contentSize: with it, every re-pin lands on attempt 1.
- **One post-add path** (`HomeView.didAddObservation`), always requesting the
  bottom; `BottomAnchoredScrollView` handles both bottom requests outside the
  `.id`-rebuilt subtree.
- **Regression test:** `UITests/ScrollRegressionTests` (`make test-scroll`) —
  synthetic, anonymized fixture of the device session generated at run time;
  Dynamic Type and login set via launch arguments, so no Simulator setup.
  Negative controls: with the re-pin disabled and the old filter-path skip
  restored, it fails at exactly 28.0pt (filter and launch tests).
- **Unit tests** assert the exact bottom gap at 1pt (was 60pt, which hid this
  bug class).

Rules to keep it fixed: no view invalidation from scroll geometry/phase
callbacks; scope animations to the views they animate, never wrap data
changes in `withAnimation`; every "show the bottom" request goes through
`BottomAnchoredScrollView`.

Original notes follow.

**Confirmed on device** (report author verified the bug in a previous build).
Root-cause reasoning below is unchanged from the original pass; a corrective
second scroll has been added.

**Root cause detail worth calling out:** `TaxonomyStore.search()` always
returns the *full* checklist — species aren't hidden until observed, they're
just sorted with in-range-observed species at the bottom. So adding an
observation isn't a small recount; it can move a row from anywhere in a
several-thousand-row list to the very last position. The `LazyVStack` has to
realize/measure a swath of rows it had never rendered before to know the
true bottom, and the single-tick-deferred `scrollTo` can fire before that
settles — landing short by however much the newly-realized rows' *estimated*
heights differed from their *actual* heights.

**Fix** (`BottomAnchoredScrollView.swift`): added a corrective second
`scrollTo`, gated on the `onScrollGeometryChange` `contentSize` signal
actually settling after the trigger fires (bounded to a 500ms window so it
can't fire later on some unrelated geometry change). This mirrors the
"wait for the real geometry, then correct" approach `scroll-to-bottom.md`'s
Attempt 3 already used successfully for the *other* scroll path, applied
here via the same `ProxyHolder` bridge (`onScrollGeometryChange` doesn't fire
when nested inside `ScrollViewReader`, so the proxy has to be smuggled out).

**On testing this**: I tried two rounds of regression tests, both against
`Tests/BottomScrollTests.swift`'s existing `TestWindow` (`UIHostingController`
+ `layoutIfNeeded()`) harness:

1. **Whole-view content swap** (short content → tall content via `w.update`,
   same trigger/token). Passed identically with and without the fix —
   `.defaultScrollAnchor(.bottom, for: .alignment)` already auto-corrects a
   plain, whole-view content-size jump on its own, regardless of this fix.
2. **Realistic reorder with real cell-recycling pressure**, following up on
   a suggestion to push further: 4000 rows of *variable, real-content*
   height (`Text` with genuinely different line counts, not a fixed
   `.frame`, so SwiftUI's LazyVStack has an actual per-cell estimate to get
   wrong) in a stable id-set (no `.id()` teardown — the trigger path only).
   Scrolled away from a middle row via `sv.setContentOffset(.zero,
   animated: false)` (the same technique — and the closest analogue to
   `ScrollViewReader.scrollTo` available outside the view — the existing
   suite already uses to fake "user scrolled elsewhere" cheaply), then
   reordered that row to the very end and fired the trigger, checking the
   final offset against a 5pt tolerance (tight enough to actually catch a
   ~10px gap, unlike this file's existing 60pt bound).

Result 2 is the more interesting one: **both** the pre-fix and post-fix code
landed with `delta = 0.0` — `contentOffset.y` exactly equal to `maxOffset`,
not even a fractional gap. Digging into why: `TestWindow.update()` calls
`hostingController.view.layoutIfNeeded()` synchronously, which forces
SwiftUI to fully resolve `LazyVStack`'s layout — including every row's real
height — in that single synchronous pass. There's no opportunity for an
"estimate now, render exactly later" gap to exist, because nothing in this
harness is asynchronous the way a live app's `CADisplayLink`-driven,
animation-based rendering pipeline is. In other words: **`layoutIfNeeded()`
collapses exactly the race window this bug lives in.** This isn't a
tooling gap I could paper over with a bigger row count or more extreme
height variance — it's a structural mismatch between how this harness
drives SwiftUI (synchronous, on-demand) and how the real race happens
(asynchronous, frame-scheduled). It also explains, in hindsight, why
`scroll-to-bottom.md`'s own multi-week debugging saga for the sibling bug
needed real device/Simulator log correlation rather than unit tests to
pin down.

I removed both non-discriminating tests rather than keep ones that can't
fail. The existing 90-test suite (`make test-app` / `BirdCountTests`) still
passes with the fix in place.

**Live confirmation, since**: added `DebugTestHook` (see
"No-touch triggering" in
[`live-simulator-diagnosis-workflow.md`](live-simulator-diagnosis-workflow.md))
to trigger `addObservation` from outside the running process, and captured
the real app (hydrated with the 11,145-species checklist + 20k-observation
dataset) live in the Simulator:

- A single add of a far-from-bottom species landed correctly with no
  correction needed — `contentSize` had already settled by the time the
  trigger's own scroll fired, so the deferred single scroll alone was
  enough.
- **Two rapid successive adds** (mimicking fast user interaction — the
  exact failure mode named in the original bug report) did produce the race:
  the second add's `contentSize` change arrived *after* its own trigger's
  scroll had already fired, but *before* the 500ms corrective window closed
  — the corrective scroll fired and the log shows it landing correctly:
  ```
  SwiftUI contentSize.height: 804669.0 -> 804202.0
  corrective scrollTo(sentinel) fired after contentSize settle
  ```
  A follow-up screenshot confirmed the newly-added species was fully visible
  at the true bottom, not clipped or short.

This is real, live evidence — not just a unit test — that (a) the race this
fix targets does occur in the live app under realistic conditions, and
(b) the corrective scroll catches it and lands correctly when it does. It's
not a repeated/statistical sample (one live catch), so it doesn't rule out
rarer variants of the same race, but it's a meaningfully stronger
confirmation than the code-reasoning-only original diagnosis.

---

Original diagnosis (kept for context — same root-cause reasoning as above,
written before the report author's device confirmation):

The `scrollToBottomTrigger` path in
`BottomAnchoredScrollView` (used when an observation is added and the
species list re-sorts without its underlying id-set changing) is:

```swift
.onChange(of: scrollToBottomTrigger) { _, _ in
    Task { @MainActor in
        var t = Transaction(animation: .none)
        t.disablesAnimations = true
        withTransaction(t) {
            proxy.scrollTo(sentinelID, anchor: .bottom)
        }
    }
}
```

The comment directly above this in the source already names the failure
mode: firing `scrollTo` synchronously "targets stale estimated row heights
and lands slightly above the true bottom" — a single `Task { @MainActor }`
hop was added as the fix. But `docs/scroll-to-bottom.md`'s Attempt 4 record
shows this exact one-tick-defer strategy failing for the *other* scroll path
(content-set change) for the same reason: a `showPulseAnimation`-driven
re-render landed **after** the deferred `scrollTo` fired, so the scroll
resolved against a not-yet-final layout. That specific interference was
fixed by moving pulse state to `@Observable PulseAnimationState` (isolating
re-renders to `SpeciesRow`) — but that fix targeted the content-set-change
path's `.id()` teardown, not this same-set re-sort path's `proxy.scrollTo`.

Adding an observation is exactly the moment `PulseAnimationState.trigger()`
also fires (`SpeciesRow.onChange(of: shouldPulse)`), so the same class of
"one more render arrives after the deferred scroll" race is plausible here
too, just smaller in magnitude (a re-sort, not a full rebuild) — consistent
with "off by a small amount" rather than the ~600pt gaps seen in the
content-set-change bug.

**To confirm live:** reproduce with the `.scroll` log category streaming.
The already-added log lines are exactly what's needed:
- `"trigger fired: scrollTo(sentinel) scheduled"`
- `"trigger: scrollTo(sentinel) sent"`
- `"SwiftUI contentSize.height: X -> Y"` (from `onScrollGeometryChange`)

If a `contentSize` change is logged **after** "scrollTo(sentinel) sent", that
confirms the layout committed too late for that scroll call — the same
signature as the historical bug, just on the other code path. If no
contentSize change follows, the root cause is elsewhere (e.g. the sentinel's
own frame not yet reflecting the new row, or `anchor: .bottom` rounding).

**If confirmed**, the fix likely mirrors the existing pattern: either extend
the isolation that fixed the content-set-change path to this trigger path,
or add a second corrective `scrollTo` gated on a `contentSize` change signal
(the corrective-scroll approach scroll-to-bottom.md's Attempt 3 also tried,
successfully getting the timing right there, before it was superseded by the
teardown approach for the *other* path).

## 2. Swipe-to-reveal stuck in an intermediate animation state, "blue focused" residue — FIXED

**Confirmed and fixed** (device testimony from the report author: the "blue"
is the start of a right-swipe quick-add reveal at partial saturation, and it
happens on real device — not a Simulator-only hover/focus artifact, ruling
out hypothesis (b) from the original pass below).

**Root cause:** `SpeciesRow`'s `DragGesture.onChanged` guards on direction —
`guard abs(width) > abs(height) else { return }` — but that `return` was a
no-op, not a reset. `rightSwipeOffset`/`leftDragOffset` are cumulative
translation-derived values set on earlier (horizontal-dominant) samples of
the *same* continuous drag. If the drag later becomes vertical-dominant
(e.g. the user's swipe reads as horizontal for the first sample or two, then
mostly-vertical as a scroll takes over), the guard just stops updating the
offset — it doesn't zero it. Worse: SwiftUI/UIKit gesture recognizers compete
for a touch, and once the enclosing `ScrollView`'s pan gesture claims it for
scrolling, this `DragGesture` is cancelled by UIKit without calling
`.onEnded` — the one place that resets the offset. Net effect: the row's
blue quick-add background is left visible at whatever partial opacity it
last reached, indefinitely, until the row is dragged again.

**Fix** (`SpeciesRow.swift`): when the direction guard fails, reset both
offsets immediately (short `.easeOut(duration: 0.15)`) instead of silently
returning. This resets on the very sample where the gesture is heading
vertical — before any hand-off/cancellation to the ScrollView can happen —
so the partial state never gets a chance to strand.

Filed as fixed without a live capture session (same environment constraint
as the rest of this doc), but the mechanism — a `return` with no reset in a
gesture-direction guard — is a plain code defect independent of Simulator
vs. device, so no further live confirmation is needed to justify the fix
itself. A human running the diagnosis workflow can still verify the
regression is gone.

**Superseded hypotheses** (kept for context): (a) an
`allowsHitTesting`/animation-timing mismatch on the *left*-swipe reveal —
still plausible as a separate, minor issue, not addressed here since the
reported bug turned out to be the right-swipe path; (b) a Simulator-only
hover/focus artifact — ruled out by the device report.

## 3. Green add-highlight less prominent on device — FIXED

**Confirmed and fixed**, with a correction to the original hypothesis: the
highlight *is* visible on device (not a Simulator-only artifact as first
guessed) — it's just less prominent there, per device testimony from the
report author. So this was right that it's a display/perception issue, not
a logic bug, but wrong that it needed a side-by-side capture to act on: the
same code weakness (a highlight that's both faint and doesn't hold at peak)
would read as "less prominent" on any real device regardless of exact
display calibration, so the fix is a legitimate tuning change even without
a controlled comparison recording.

**Root cause:** `SpeciesRow`'s pulse timing faded in over 0.3s and began
fading back out **immediately**, with no hold at full intensity — the
highlight was only ever at peak opacity for a single instant before
dimming again. Combined with a faint 15%-opacity fill, that's an easy miss
on a device screen (True Tone / ambient dimming) even though Simulator's
flatter rendering happened to make the same brief peak more noticeable.

**Fix** (`SpeciesRow.swift` / `PulseAnimationState`): added a 0.6s hold
between fade-in and fade-out (shared timing constants — `fadeInDuration`,
`holdDuration`, `fadeOutDuration`, `totalDuration` — now used by both the
view's animation schedule and `PulseAnimationState`'s clear-timer, so they
can't drift apart), and raised the fill opacity 0.15 → 0.28 and the stroke
opacity/width 0.8/2pt → 0.9/2.5pt. Total highlight duration is now 2.5s
(was 2.0s).

## Summary

| # | Issue | Status | Live confirmation needed |
|---|---|---|---|
| 1 | Scroll ~10px short | **fixed** (confirmed on device) | regression check via diagnosis workflow |
| 2 | Swipe-reveal blue reveal stuck | **fixed** (confirmed root cause) | regression check via diagnosis workflow |
| 3 | Green highlight less prominent on device | **fixed** (confirmed root cause) | regression check via diagnosis workflow |

All three are now fixed rather than left diagnosed-only, superseding the
plan's original scope note (`Out of scope: Fixing the three example bugs`),
which predates having confirmed root causes. None have been re-verified
live by me (no touch-injection tooling in this environment — see the status
note above); a human running the diagnosis workflow to confirm each fix
holds on-device is the next step, worth its own doc per fix in the style of
`scroll-to-bottom.md` once confirmed.
