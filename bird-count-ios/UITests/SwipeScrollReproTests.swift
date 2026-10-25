import XCTest

/// Exploratory repro harness for "after swipe-to-add, list rests a few
/// points short of the bottom" (needs LIVE_SIM_DATASET; skipped otherwise).
/// The self-contained regression test is ScrollRegressionTests. Drives real HID touches (speed + angle), unlike a Simulator
/// mouse drag, and reads the DEBUG-only `debug.scrollGap` probe exposed by
/// BottomAnchoredScrollView (0 = at true bottom, positive = short).
///
/// Requires LIVE_SIM_DATASET (path to a DTO fixture, e.g.
/// data/live-sim-dataset.json); skipped otherwise. REPRO_REPS sets reps per
/// case (default 3).
final class SwipeScrollReproTests: XCTestCase {
    enum Precondition: String, CaseIterable {
        case atBottom
        case nudgedUp       // ~1 row up, list at rest
        case oneScreenUp    // into unobserved species, list at rest
        case flungFar       // several flings up, into far unobserved species
    }

    struct Swipe {
        let name: String
        let dx: CGFloat
        let dy: CGFloat
        let velocity: CGFloat
        let pressDuration: TimeInterval
    }

    var app: XCUIApplication!

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = true
        guard let dataset = ProcessInfo.processInfo.environment["LIVE_SIM_DATASET"] else {
            throw XCTSkip("LIVE_SIM_DATASET not set")
        }
        app = XCUIApplication()
        app.launchArguments += ["-LiveSimDataset", dataset]
        if let email = ProcessInfo.processInfo.environment["REPRO_LOGIN_EMAIL"] {
            app.launchArguments += ["-Settings_loginEmail", email]
        }
        app.launch()
    }

    private func gap() -> Double { app.scrollGap }

    private func listPoint(x: CGFloat = 0.5, _ t: CGFloat) -> XCUICoordinate {
        app.speciesListPoint(x: x, t)
    }

    /// Slow drag with a hold at the end so no fling/deceleration follows.
    private func dragContent(_ scroll: XCUIElement, by points: CGFloat) {
        let start = listPoint(points > 0 ? 0.1 : 0.9)
        let end = start.withOffset(CGVector(dx: 0, dy: points))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 400, thenHoldForDuration: 0.4)
    }

    private func apply(_ pre: Precondition, _ scroll: XCUIElement) {
        // Always start from the bottom.
        if abs(gap()) > 0.5 {
            for _ in 0..<8 { listPoint(0.9).press(forDuration: 0.1, thenDragTo: listPoint(0.1), withVelocity: 2500, thenHoldForDuration: 0) }
            Thread.sleep(forTimeInterval: 1.0)
        }
        switch pre {
        case .atBottom: break
        case .nudgedUp: dragContent(scroll, by: 80)
        case .oneScreenUp: dragContent(scroll, by: 450)
        case .flungFar:
            for _ in 0..<6 { listPoint(0.1).press(forDuration: 0.1, thenDragTo: listPoint(0.9), withVelocity: 2500, thenHoldForDuration: 0) }
            Thread.sleep(forTimeInterval: 1.5)
        }
    }

    /// Replays the device report (filter path): dataset = device export minus
    /// the final Black Phoebe add; type a filter on the on-screen keyboard,
    /// swipe-add the row (which clears the filter → ScrollView rebuild), read
    /// the gap. Fresh launch per rep. REPRO_TAXON_NAME / REPRO_FILTER_KEYS
    /// override the row (default "Black Phoebe") and keys (default "BP").
    @MainActor
    func testFilterSwipeReplay() throws {
        let name = ProcessInfo.processInfo.environment["REPRO_TAXON_NAME"] ?? "Black Phoebe"
        let keys = Array(ProcessInfo.processInfo.environment["REPRO_FILTER_KEYS"] ?? "BP").map(String.init)
        let reps = Int(ProcessInfo.processInfo.environment["REPRO_REPS"] ?? "") ?? 3
        let swipes: [(String, CGFloat, TimeInterval)] = [("fast", 4000, 0), ("slow", 300, 0.05)]
        var report: [String] = []
        for (sname, velocity, press) in swipes {
            for rep in 0..<reps {
                app.terminate()
                app.launch()
                XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
                sleep(2)
                for k in keys { app.buttons[k].tap() }
                Thread.sleep(forTimeInterval: 1.0)
                let row = app.staticTexts[name]
                guard row.waitForExistence(timeout: 5), row.isHittable else {
                    XCTFail("\(name) not visible after filter \(keys.joined())"); continue
                }
                let before = gap()
                let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
                start.press(forDuration: press, thenDragTo: start.withOffset(CGVector(dx: 160, dy: 0)),
                            withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: 0)
                Thread.sleep(forTimeInterval: 1.5)
                let after = gap()
                let line = String(format: "REPRO filter %@ rep=%d before=%.2f after=%.2f", sname, rep, before, after)
                print(line)
                report.append(line)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "filter-\(sname)-\(rep)-gap\(after)"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
        let summary = XCTAttachment(string: report.joined(separator: "\n"))
        summary.name = "filter-summary"
        summary.lifetime = .keepAlways
        add(summary)
    }

    /// Finger-like paths: vertical curl at touch-down, late drift, hooks.
    @MainActor
    func testCurvedSwipes() throws {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 30))
        sleep(2)
        typealias S = TouchPathSynthesizer.Step
        func scaled(_ w: [S], _ k: Double) -> [S] { w.map { S(dx: $0.dx, dy: $0.dy, t: $0.t * k) } }
        let base: [(String, [S])] = [
            ("straight", [S(dx: 0, dy: 0, t: 0), S(dx: 160, dy: 0, t: 0.08)]),
            ("curl-down", [S(dx: 0, dy: 0, t: 0), S(dx: 2, dy: 12, t: 0.03), S(dx: 160, dy: 18, t: 0.11)]),
            ("curl-up", [S(dx: 0, dy: 0, t: 0), S(dx: 2, dy: -12, t: 0.03), S(dx: 160, dy: -18, t: 0.11)]),
            ("late-drift-down", [S(dx: 0, dy: 0, t: 0), S(dx: 80, dy: 3, t: 0.05), S(dx: 160, dy: 30, t: 0.10)]),
            ("late-drift-up", [S(dx: 0, dy: 0, t: 0), S(dx: 80, dy: -3, t: 0.05), S(dx: 160, dy: -30, t: 0.10)]),
            ("hook-down", [S(dx: 0, dy: 0, t: 0), S(dx: 150, dy: 0, t: 0.08), S(dx: 165, dy: 20, t: 0.11)]),
        ]
        var shapes: [(String, [S])] = []
        for (n, w) in base { shapes.append(("\(n)-fast", w)); shapes.append(("\(n)-slow", scaled(w, 5))) }

        let reps = Int(ProcessInfo.processInfo.environment["REPRO_REPS"] ?? "") ?? 3
        let rowYs: [CGFloat] = [0.3, 0.55, 0.8]
        var report: [String] = []
        for (name, waypoints) in shapes {
            for rep in 0..<reps {
                if abs(gap()) > 0.5 {
                    for _ in 0..<3 { listPoint(0.9).press(forDuration: 0.1, thenDragTo: listPoint(0.1), withVelocity: 2500, thenHoldForDuration: 0) }
                    Thread.sleep(forTimeInterval: 1.0)
                }
                let before = gap()
                let origin = listPoint(x: 0.15, rowYs[rep % rowYs.count]).screenPoint
                try TouchPathSynthesizer.perform(origin: origin, steps: TouchPathSynthesizer.interpolate(waypoints))
                Thread.sleep(forTimeInterval: 1.5)
                let after = gap()
                let line = String(format: "REPRO curved %@ rep=%d before=%.2f after=%.2f", name, rep, before, after)
                print(line)
                report.append(line)
                if abs(after) > 0.5 {
                    let shot = XCTAttachment(screenshot: app.screenshot())
                    shot.name = "curved-\(name)-\(rep)-gap\(after)"
                    shot.lifetime = .keepAlways
                    add(shot)
                }
            }
        }
        let summary = XCTAttachment(string: report.joined(separator: "\n"))
        summary.name = "curved-summary"
        summary.lifetime = .keepAlways
        add(summary)
    }

    @MainActor
    func testSwipeVariants() throws {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 30))
        sleep(2)
        print("REPRO scrollView frame=\(scroll.frame) window=\(app.windows.firstMatch.frame)")

        let swipes: [Swipe] = [
            .init(name: "slow", dx: 160, dy: 0, velocity: 300, pressDuration: 0.05),
            .init(name: "fast", dx: 160, dy: 0, velocity: 4000, pressDuration: 0.0),
            .init(name: "fast-drift-down", dx: 160, dy: 25, velocity: 4000, pressDuration: 0.0),
        ]
        let reps = Int(ProcessInfo.processInfo.environment["REPRO_REPS"] ?? "") ?? 3
        let rowYs: [CGFloat] = [0.3, 0.55, 0.8]

        var report: [String] = []
        let only = ProcessInfo.processInfo.environment["REPRO_PRE"].flatMap(Precondition.init(rawValue:))
        for pre in Precondition.allCases where only == nil || only == pre {
            for s in swipes {
                for rep in 0..<reps {
                    apply(pre, scroll)
                    let y = rowYs[rep % rowYs.count]
                    let before = gap()
                    if pre != .atBottom && before < 1 {
                        XCTFail("precondition \(pre.rawValue) did not move list (gap=\(before))")
                    }
                    let preShot = XCTAttachment(screenshot: app.screenshot())
                    preShot.name = "\(pre.rawValue)-\(s.name)-\(rep)-before\(before)"
                    preShot.lifetime = .keepAlways
                    add(preShot)
                    let start = listPoint(x: 0.15, y)
                    let end = start.withOffset(CGVector(dx: s.dx, dy: s.dy))
                    start.press(forDuration: s.pressDuration, thenDragTo: end,
                                withVelocity: XCUIGestureVelocity(s.velocity), thenHoldForDuration: 0)
                    Thread.sleep(forTimeInterval: 1.5)
                    let after = gap()
                    let line = String(format: "REPRO %@ %@ rep=%d y=%.2f before=%.2f after=%.2f",
                                      pre.rawValue, s.name, rep, y, before, after)
                    print(line)
                    report.append(line)
                    if abs(after) > 0.5 {
                        let shot = XCTAttachment(screenshot: app.screenshot())
                        shot.name = "\(pre.rawValue)-\(s.name)-\(rep)-gap\(after)"
                        shot.lifetime = .keepAlways
                        add(shot)
                    }
                }
            }
        }
        let summary = XCTAttachment(string: report.joined(separator: "\n"))
        summary.name = "repro-summary"
        summary.lifetime = .keepAlways
        add(summary)
    }
}
