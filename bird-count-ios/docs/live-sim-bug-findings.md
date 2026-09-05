# Live Simulator Testing — Findings on the Three Known Issues

Plan step 6 of [`live-simulator-testing-plan.md`](live-simulator-testing-plan.md):
apply the tooling to the three issues named in the original testing doc, as
validation that the infrastructure is sufficient.

**Status:** #2 and #3 are confirmed (via device testimony correcting the
original hypotheses) and fixed. #1 is still an open, code-grounded
hypothesis. I was not able to drive real touch/trackpad interaction against
the Simulator from this environment (no `idb`/`cliclick`, and `xcrun simctl`
has no touch-injection command) — the manual workflow in
[`live-simulator-diagnosis-workflow.md`](live-simulator-diagnosis-workflow.md)
needs a human at the keyboard to actually reproduce and log/record it.

## 1. Persistent ~10px scroll-short after adding an observation

**Confidence: medium-high.** The `scrollToBottomTrigger` path in
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
| 1 | Scroll ~10px short | diagnosed, not fixed (medium-high confidence) | `.scroll` log capture during repro |
| 2 | Swipe-reveal blue reveal stuck | **fixed** (confirmed root cause) | regression check via diagnosis workflow |
| 3 | Green highlight less prominent on device | **fixed** (confirmed root cause) | regression check via diagnosis workflow |

Issue 1 remains open — consistent with the plan's original scope note
(`Out of scope: Fixing the three example bugs`), which predates having a
confirmed root cause for 2 and 3. The next step for issue 1 is a human
running the diagnosis workflow to capture the `.scroll` log evidence
described above; for 2 and 3, a human re-running the workflow to confirm the
fixes hold on-device. Each, once confirmed, is worth its own doc in the
style of `scroll-to-bottom.md`.
