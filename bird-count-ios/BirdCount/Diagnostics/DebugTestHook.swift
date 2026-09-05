#if DEBUG
import Foundation
import Observation

/// Live Simulator testing hook (see docs/live-simulator-testing-plan.md):
/// lets an external process trigger app actions without touch input, by
/// writing a taxon id to a well-known file inside the app's Documents
/// directory. This app polls for that file, consumes it, and runs the exact
/// same mutation + scroll-trigger + pulse path as a real quick-add tap — so
/// the LazyVStack reorder race can be exercised deterministically (from a
/// known taxon, at a known moment) without touch-injection tooling.
///
/// A custom URL scheme (`birdcount://debug/...` via `simctl openurl`) was
/// tried first and rejected: iOS shows an "Open in BirdCount?" confirmation
/// dialog for every externally-triggered custom-scheme open, which needs a
/// touch to dismiss — defeating the point. File polling has no such gate.
///
/// Find the file's location for a booted Simulator with:
///   xcrun simctl get_app_container booted org.antoninus.birdcount.app data
/// then write to `<that path>/Documents/debug-add-request.txt` (plain text,
/// the taxon id). It's deleted once consumed.
///
/// Never compiled into Release builds.
@Observable final class DebugTestHook {
    var pendingAddTaxonId: String? = nil

    private var timer: Timer?

    private static var requestFileURL: URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("debug-add-request.txt")
    }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard let url = Self.requestFileURL,
              let taxonId = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !taxonId.isEmpty
        else { return }
        try? FileManager.default.removeItem(at: url)
        DiagnosticsLog.log(.sync, "Debug hook: consumed addObservation request for taxonId=\(taxonId)")
        pendingAddTaxonId = taxonId
    }
}
#endif
