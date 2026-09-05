import Foundation
import os

/// Debug-only structured logging for diagnosing timing- and interaction-dependent
/// UI bugs (scroll anchoring, swipe-gesture state, animation timing) in the
/// Simulator. See docs/live-simulator-testing-plan.md.
///
/// Never compiled into Release builds. View a live session with:
///   log stream --predicate 'subsystem == "org.antoninus.birdcount"' --level debug
enum DiagnosticsLog {
    enum Category: String {
        case scroll
        case gesture
        case sync
        case animation
    }

    #if DEBUG
    private static let subsystem = "org.antoninus.birdcount"
    private static var loggers: [Category: Logger] = [:]

    private static func logger(for category: Category) -> Logger {
        if let existing = loggers[category] { return existing }
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = logger
        return logger
    }

    static func log(_ category: Category, _ message: @autoclosure () -> String) {
        let resolved = message()
        logger(for: category).debug("\(resolved, privacy: .public)")
    }
    #else
    static func log(_ category: Category, _ message: @autoclosure () -> String) {}
    #endif
}
