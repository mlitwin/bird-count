# Live Simulator Testing — Findings on the Three Known Issues

Plan step 6 of [`live-simulator-testing-plan.md`](live-simulator-testing-plan.md):
apply the tooling to the three issues named in the original testing doc, as
validation that the infrastructure is sufficient.

**Status: code-grounded hypotheses, not yet confirmed with a live capture
session.** I was not able to drive real touch/trackpad interaction against
the Simulator from this environment (no `idb`/`cliclick`, and `xcrun simctl`
has no touch-injection command) — the manual workflow in
[`live-simulator-diagnosis-workflow.md`](live-simulator-diagnosis-workflow.md)
needs a human at the keyboard to actually reproduce and log/record these.
What follows is what the code supports, with each item marked with what a
live session should look for to confirm or rule it out. This is real
diagnostic progress — it narrows where to look and what signal confirms
it — but it is not the same as a captured repro.

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

## 2. Swipe-to-reveal stuck in an intermediate animation state, "blue focused" residue

**Confidence: medium.** Two separate mechanisms in `SpeciesRow`, either or
both could produce the reported symptoms:

**a) "Controls visible but not active":** `leftRevealOpen` is a discrete
`Bool`; `.allowsHitTesting(leftRevealOpen)` on the reveal buttons flips
**instantly** the moment `withAnimation { leftRevealOpen = shouldOpen }` is
called, but the buttons' *visual* position depends on the animated
`.offset`/`.opacity` (driven by the same `leftRevealOpen`/`leftDragOffset`
state over a `.spring(response: 0.25, dampingFraction: 0.7)`, ~250ms+). A
tap that lands in that ~250ms window is already hit-testable and will fire,
but the button is still visually sliding into place — which matches
"controls visible but not active [yet fully settled/rendered]" better than
a genuine stuck state. This is a hit-testing/animation-timing mismatch, not
a state machine that fails to reach its terminal state.

**b) "Stuck blue focused state":** nothing in this codebase sets up
`.hoverEffect`, `.focusable`, or any pointer-interaction handling on these
`Button`s (grepped `BirdCount/Views` — no matches). SwiftUI's default
`Button` still applies a system hover/focus highlight for **indirect**
pointer input (trackpad/mouse), which is exactly how the Simulator delivers
clicks — a real device's touch has no hover phase and never triggers this.
A highlight that "is hard to clear" after an interrupted gesture is
consistent with a hover-effect state that nothing in the gesture code is
responsible for resetting, because on a real device it would never appear
in the first place. This may not be a bug in the app at all, in the same
family as issue 3 below.

**To confirm live:** the `.gesture` log lines already added
(`"drag ended: translation=... leftRevealOpen=..."`,
`"leftRevealOpen -> ..."`) show whether the state machine actually reaches
a terminal value. If the log always shows a clean `true`/`false` transition
but the video still shows a stuck visual, that points at (a) or (b) above —
a rendering/hover artifact rather than a state bug — and rules out a state
machine that never terminates.

## 3. Green add-highlight visible in Simulator, not easily visible on device

**Confidence: medium** (matches the plan's own working assumption). This is
`SpeciesRow`'s pulse highlight:

```swift
.background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(isPulsing ? 0.15 : 0)))
.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.8), lineWidth: isPulsing ? 2 : 0))
```

No code path renders a *different* green element on Simulator vs. device —
same `Color.green` values, same opacities, same view hierarchy. The
discrepancy is therefore almost certainly a **display characteristic**, not
application logic: the Simulator renders on the Mac's display (typically
P3, full brightness, no True Tone/ambient adaptation), while a physical
iPhone applies True Tone and ambient-light brightness adjustment that can
visibly mute a 15%-opacity green fill. Nothing here is "wrong" in the sense
this plan would fix — see the plan's own framing: confirm via a recorded
side-by-side (Simulator vs. device, same lighting, same brightness setting)
before treating this as anything other than a possible follow-up product
decision (e.g. raise the opacity for device visibility).

**To confirm live:** no log signal is expected or useful here — this is
a visual-only comparison. Record both Simulator and a real device side by
side under identical screen brightness/True-Tone settings, per the
diagnosis workflow's step 4 (video correlation), and compare.

## Summary

| # | Issue | Root-cause confidence | Live confirmation needed |
|---|---|---|---|
| 1 | Scroll ~10px short | medium-high (matches documented prior bug class) | `.scroll` log capture during repro |
| 2 | Swipe-reveal stuck / blue focus | medium (two plausible, non-exclusive mechanisms) | `.gesture` log + video correlation |
| 3 | Green highlight sim-only | medium (display characteristic, not logic) | side-by-side sim vs. device recording |

All three are left as **diagnosed, not fixed** — consistent with the plan's
scope (`Out of scope: Fixing the three example bugs`). The next step for
each is a human running the diagnosis workflow to capture the confirming
evidence above, then (if confirmed) a follow-up fix, each as its own doc in
the style of `scroll-to-bottom.md`.
