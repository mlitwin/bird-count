import XCTest

/// Shared helpers for scroll-position UI tests. Reads the DEBUG-only
/// `debug.scrollGap` probe exposed by BottomAnchoredScrollView:
/// 0 = at the true bottom, positive = short of it (points).
extension XCUIApplication {
    var scrollGap: Double {
        let probe = otherElements["debug.scrollGap"]
        guard probe.waitForExistence(timeout: 10) else { return .nan }
        return Double(probe.value as? String ?? "") ?? .nan
    }

    /// Point inside the species list: `t` 0 = list top, 1 = list bottom.
    /// Window-relative because `scrollViews.firstMatch`'s frame doesn't match
    /// the species list (drags landed on the header).
    func speciesListPoint(x: CGFloat = 0.5, _ t: CGFloat) -> XCUICoordinate {
        let listTop: CGFloat = 0.19, listBottom: CGFloat = 0.66
        return windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: x, dy: listTop + (listBottom - listTop) * t))
    }
}

extension XCUIElement {
    /// Right swipe from the element's leading edge, past the quick-add threshold.
    func quickAddSwipe(velocity: CGFloat = 4000, pressDuration: TimeInterval = 0) {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: pressDuration, thenDragTo: start.withOffset(CGVector(dx: 160, dy: 0)),
                    withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: 0)
    }
}

/// Points-of-tolerance for "at the bottom" (the probe is exact; this only
/// absorbs sub-pixel rounding).
let scrollBottomTolerance: Double = 0.5
