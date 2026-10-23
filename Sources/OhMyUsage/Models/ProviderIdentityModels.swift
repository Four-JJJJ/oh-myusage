import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }
}

enum ResourceMode: String, CaseIterable, Identifiable, Codable {
    case background3Minutes = "background3m"
    case background5Minutes = "background5m"
    case background10Minutes = "background10m"
    case background15Minutes = "background15m"

    var id: String { rawValue }

    var intervalSeconds: Int {
        switch self {
        case .background3Minutes:
            return 3 * 60
        case .background5Minutes:
            return 5 * 60
        case .background10Minutes:
            return 10 * 60
        case .background15Minutes:
            return 15 * 60
        }
    }

    /// Maps a persisted raw value (including the 2.5.x aliases) to a mode.
    /// Returns nil when the value matches no known case, which lets callers
    /// distinguish "recognized, decode it" from "unknown, fall back + diagnose".
    static func value(forPersistedRawValue rawValue: String) -> ResourceMode? {
        switch rawValue {
        case background3Minutes.rawValue, "responsive":
            return .background3Minutes
        case background5Minutes.rawValue, "balanced":
            return .background5Minutes
        case background10Minutes.rawValue:
            return .background10Minutes
        case background15Minutes.rawValue, "lowPower":
            return .background15Minutes
        default:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self.value(forPersistedRawValue: rawValue) ?? .background5Minutes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StatusBarDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case iconPercent
    case barNamePercent

    var id: String { rawValue }
}

enum StatusBarAppearanceMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case followWallpaper
    case dark
    case light

    var id: String { rawValue }
}
