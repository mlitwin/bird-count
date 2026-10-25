import XCTest

/// Regression net for "species list rests a few points short of the bottom"
/// (docs/live-sim-bug-findings.md #1). Self-contained: generates its own
/// fixture and sets Dynamic Type and the signed-in user via launch arguments,
/// so it needs no Simulator setup and no real user data.
///
/// The fixture mirrors a real device session that reproduced the bug 6/6
/// (28pt short) before the sticky-bottom fix: two observers, so rows get the
/// synced-users icon, which at extra-large text makes a name wrap — a row
/// measured taller than the LazyVStack's estimate after the list was
/// positioned. Run with `make test-scroll`.
final class ScrollRegressionTests: XCTestCase {
    var app: XCUIApplication!

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("scroll-regression-fixture.json")
        try ScrollRegressionFixture.json(now: Date()).write(to: fixture)
        app = XCUIApplication()
        app.launchArguments += [
            "-LiveSimDataset", fixture.path,
            "-Settings_loginEmail", ScrollRegressionFixture.me,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL",
        ]
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
        sleep(2)
    }

    /// Launch: the list must settle exactly at the bottom once rows are measured.
    @MainActor
    func testLaunchSettlesAtBottom() {
        XCTAssertEqual(app.scrollGap, 0, accuracy: scrollBottomTolerance)
    }

    /// The device report: type a filter, swipe-add the row. Clearing the filter
    /// rebuilds the list; a row then measures taller than estimated.
    @MainActor
    func testFilterThenSwipeAddLandsAtBottom() {
        for key in ["B", "P"] { app.buttons[key].tap() }
        let row = app.staticTexts["Black Phoebe"]
        XCTAssertTrue(row.waitForExistence(timeout: 5) && row.isHittable)
        row.quickAddSwipe()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(app.scrollGap, 0, accuracy: scrollBottomTolerance)
    }

    /// No filter (trigger path), starting scrolled up: the add must bring the
    /// list all the way to the bottom.
    @MainActor
    func testSwipeAddFromScrolledUpLandsAtBottom() {
        let start = app.speciesListPoint(0.1)
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)),
                    withVelocity: 400, thenHoldForDuration: 0.4)
        XCTAssertGreaterThan(app.scrollGap, 100, "Precondition: scrolled up")
        app.speciesListPoint(x: 0.15, 0.5).press(
            forDuration: 0, thenDragTo: app.speciesListPoint(x: 0.55, 0.5),
            withVelocity: 4000, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(app.scrollGap, 0, accuracy: scrollBottomTolerance)
    }
}

/// Anonymized shape of the device session: species order, counts, add/undo
/// pairs, and which of two observers made each record. Times are spread over
/// "today so far" at generation time, preserving order.
enum ScrollRegressionFixture {
    static let me = "me@example.com"
    static let friend = "friend@example.com"

    private struct Row {
        let taxonId: String
        let count: Int
        let observer: String
        let parent: Int?
        let located: Bool
        init(_ taxonId: String, _ count: Int, _ observer: String, parent: Int?, located: Bool) {
            self.taxonId = taxonId; self.count = count; self.observer = observer
            self.parent = parent; self.located = located
        }
    }

    private static let rows: [Row] = [
        .init("yerwar", 1, me, parent: nil, located: false),
        .init("houfin", 1, me, parent: nil, located: false),
        .init("wesgul", 1, friend, parent: nil, located: true),
        .init("houfin", 1, friend, parent: nil, located: true),
        .init("annhum", 1, me, parent: nil, located: false),
        .init("annhum", 1, friend, parent: nil, located: true),
        .init("yerwar", 1, friend, parent: nil, located: true),
        .init("chbchi", 1, me, parent: nil, located: true),
        .init("blkpho", 1, friend, parent: nil, located: false),
        .init("amecro", 1, me, parent: nil, located: true),
        .init("chbchi", 1, friend, parent: nil, located: true),
        .init("amecro", 1, friend, parent: nil, located: true),
        .init("rocpig", 1, me, parent: nil, located: false),
        .init("lesgol", 1, friend, parent: nil, located: true),
        .init("comrav", 2, me, parent: nil, located: false),
        .init("towwar", 1, me, parent: nil, located: false),
        .init("amecro", 1, me, parent: nil, located: true),
        .init("rocpig", 1, me, parent: nil, located: true),
        .init("rocpig", -1, me, parent: 17, located: true),
        .init("rocpig", 1, me, parent: nil, located: true),
        .init("rocpig", -1, me, parent: 19, located: true),
        .init("lesgol", 1, me, parent: nil, located: true),
        .init("lesgol", -1, me, parent: 21, located: true),
        .init("rocpig", 1, me, parent: nil, located: true),
        .init("rocpig", -1, me, parent: 23, located: true),
        .init("rocpig", 1, me, parent: nil, located: true),
        .init("rocpig", -1, me, parent: 25, located: true),
        .init("comrav", 1, friend, parent: nil, located: true),
        .init("rocpig", 1, me, parent: nil, located: true),
        .init("rocpig", -1, me, parent: 28, located: true),
        .init("daejun", 1, me, parent: nil, located: true),
        .init("daejun", -1, me, parent: 30, located: true),
        .init("rocpig", 1, me, parent: nil, located: true),
        .init("rocpig", -1, me, parent: 32, located: true),
    ]

    static func json(now: Date) throws -> Data {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(startOfDay)
        let iso = ISO8601DateFormatter()  // whole seconds: the app decodes with .iso8601
        let ids = rows.map { _ in UUID().uuidString }
        let records: [[String: Any]] = rows.enumerated().map { i, row in
            let t = startOfDay.addingTimeInterval(elapsed * Double(i + 1) / Double(rows.count + 2))
            var r: [String: Any] = [
                "id": ids[i], "taxonId": row.taxonId, "count": row.count,
                "begin": iso.string(from: t), "end": iso.string(from: t),
                "observer": row.observer, "status": "completed",
            ]
            if let p = row.parent { r["parentId"] = ids[p] }
            if row.located {
                // Public place (Golden Gate Park), not a real observation site.
                r["location"] = ["latitude": 37.7694, "longitude": -122.4862,
                                 "horizontalAccuracy": 10.0, "timestamp": iso.string(from: t)]
            }
            return r
        }
        return try JSONSerialization.data(withJSONObject: records)
    }
}
