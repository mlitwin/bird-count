import Foundation
import Observation

@Observable final class SettingsStore {
    // Static key helper to avoid self usage before init completes
    private static let keyPrefix = "Settings_"
    private static func key(_ k: String) -> String { keyPrefix + k }

    // Initialization guard to suppress persistence & normalization until fully loaded
    private var initializing = true

    // User-adjustable settings with default values
    var enableAbbreviationSearch: Bool = true { didSet { persistIfReady() } }
    var enableHaptics: Bool = true { didSet { persistIfReady() } }
    var darkModeOverride: DarkModeOverride = .system { didSet { persistIfReady() } }
    // Checklist related
    var selectedChecklistId: String? = nil { didSet { persistIfReady() } }
    var minCommonness: Int = 0 { didSet { normalizeRanges(changed: .min) } }
    var maxCommonness: Int = 3 { didSet { normalizeRanges(changed: .max) } }

    enum DarkModeOverride: String, CaseIterable, Identifiable, Codable { case system, light, dark; var id: String { rawValue } }

    init() {
        let defaults = UserDefaults.standard
        if let v = defaults.object(forKey: Self.key("enableAbbreviationSearch")) as? Bool { enableAbbreviationSearch = v }
        if let v = defaults.object(forKey: Self.key("enableHaptics")) as? Bool { enableHaptics = v }
        if let raw = defaults.string(forKey: Self.key("darkModeOverride")), let m = DarkModeOverride(rawValue: raw) { darkModeOverride = m }
        if let raw = defaults.string(forKey: Self.key("selectedChecklistId")), !raw.isEmpty { selectedChecklistId = raw }
        if defaults.object(forKey: Self.key("minCommonness")) != nil { minCommonness = defaults.integer(forKey: Self.key("minCommonness")) }
        if defaults.object(forKey: Self.key("maxCommonness")) != nil { maxCommonness = defaults.integer(forKey: Self.key("maxCommonness")) }
        normalizeRanges(changed: nil)
        initializing = false
    }

    // MARK: - Range Normalization
    private enum RangeChanged { case min, max }
    private func normalizeRanges(changed: RangeChanged?) {
        // Clamp independently without using inout to avoid re-entrant crashes
        let clampedMin = min(max(minCommonness, 0), 3)
        let clampedMax = min(max(maxCommonness, 0), 3)
        if clampedMin != minCommonness { minCommonness = clampedMin; return } // will re-enter once with safe value
        if clampedMax != maxCommonness { maxCommonness = clampedMax; return }
        // Enforce ordering
        if minCommonness > maxCommonness {
            if changed == .min { maxCommonness = minCommonness; return }
            else { minCommonness = maxCommonness; return }
        }
        persistIfReady()
    }

    // MARK: - Persistence
    private func persistIfReady() { if !initializing { persist() } }
    private func persist() {
        let d = UserDefaults.standard
        d.set(enableAbbreviationSearch, forKey: Self.key("enableAbbreviationSearch"))
        d.set(enableHaptics, forKey: Self.key("enableHaptics"))
        d.set(darkModeOverride.rawValue, forKey: Self.key("darkModeOverride"))
        d.set(selectedChecklistId ?? "", forKey: Self.key("selectedChecklistId"))
        d.set(minCommonness, forKey: Self.key("minCommonness"))
        d.set(maxCommonness, forKey: Self.key("maxCommonness"))
    }
}
