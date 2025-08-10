import Foundation
import Observation

@Observable final class SettingsStore {
    // Static key helper to avoid self usage before init completes
    private static let keyPrefix = "Settings_"
    private static func key(_ k: String) -> String { keyPrefix + k }

    // User-adjustable settings with default values
    var enableAbbreviationSearch: Bool = true { didSet { persist() } }
    var enableHaptics: Bool = true { didSet { persist() } }
    var darkModeOverride: DarkModeOverride = .system { didSet { persist() } }

    enum DarkModeOverride: String, CaseIterable, Identifiable, Codable { case system, light, dark; var id: String { rawValue } }

    init() {
        let defaults = UserDefaults.standard
        if let v = defaults.object(forKey: Self.key("enableAbbreviationSearch")) as? Bool { enableAbbreviationSearch = v }
        if let v = defaults.object(forKey: Self.key("enableHaptics")) as? Bool { enableHaptics = v }
        if let raw = defaults.string(forKey: Self.key("darkModeOverride")), let m = DarkModeOverride(rawValue: raw) { darkModeOverride = m }
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(enableAbbreviationSearch, forKey: Self.key("enableAbbreviationSearch"))
        d.set(enableHaptics, forKey: Self.key("enableHaptics"))
        d.set(darkModeOverride.rawValue, forKey: Self.key("darkModeOverride"))
    }
}
