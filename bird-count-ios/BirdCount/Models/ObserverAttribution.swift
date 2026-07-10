import Foundation

/// Who contributed the observations behind a row or count, for the person
/// badge next to counts.
///
/// Badge rule: the person count is the number of people involved (capped at
/// three), FILLED when the current user's observations are in the mix and
/// OUTLINE when the data is entirely from synced users.
public enum ObserverAttribution: Equatable {
    /// Only the current user's observations — no badge.
    case mine
    /// Entirely other users' observations.
    case others(count: Int)
    /// The current user's observations plus other users'.
    case mixed(othersCount: Int)

    public init(observers: Set<String>, currentObserver: String) {
        let others = observers.filter { $0 != currentObserver }
        if others.isEmpty {
            self = .mine
        } else if others.count == observers.count {
            self = .others(count: others.count)
        } else {
            self = .mixed(othersCount: others.count)
        }
    }

    /// SF Symbol for the badge; nil when no badge should show.
    public var symbolName: String? {
        switch self {
        case .mine:
            return nil
        case .others(let count):
            return count >= 3 ? "person.3" : (count == 2 ? "person.2" : "person")
        case .mixed(let othersCount):
            return othersCount >= 2 ? "person.3.fill" : "person.2.fill"
        }
    }

    public var includesCurrentUser: Bool {
        if case .mixed = self { return true }
        return false
    }
}
