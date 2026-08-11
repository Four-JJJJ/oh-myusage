import Foundation
import OhMyUsageProviders

enum KimiAuthMode: String, Codable, CaseIterable {
    case manual
    case auto
}

struct KimiProviderConfig: Codable, Equatable {
    var authMode: KimiAuthMode
    var manualTokenAccount: String
    var autoCookieEnabled: Bool
    var browserOrder: [KimiBrowserKind]
}
