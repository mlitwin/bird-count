import Foundation
import Observation

/// Stack-based navigation state read by AppHeaderView.
/// Each pushed view pushes an entry; popping removes it.
/// AppHeaderView always shows the top of the stack.
@Observable final class AppNavigationState {
    struct NavEntry {
        let title: String?
        let backAction: () -> Void
    }

    private(set) var stack: [NavEntry] = []

    var title: String? { stack.last?.title }
    var backAction: (() -> Void)? { stack.last?.backAction }

    func push(title: String?, backAction: @escaping () -> Void) {
        stack.append(NavEntry(title: title, backAction: backAction))
    }

    func pop() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
    }
}
