import Foundation

/// Low-level service/account credential persistence.
/// Higher-level provider-scoped access uses ``UsageCredentialStore``.
public protocol CredentialStoring: Sendable {
    func readToken(service: String, account: String) -> String?

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool

    @discardableResult
    func deleteToken(service: String, account: String) -> Bool
}

public enum CredentialStoreServiceNames {
    public static let defaultServiceName = "oh-myusage"
    public static let legacyServiceName = "OhMyUsage"
    public static let historicalLegacyServiceNames = [
        "OhMyUsage",
        "AI Plan Monitor",
        "AIPlanMonitor"
    ]

    public static func isLegacyServiceName(_ service: String) -> Bool {
        let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        return historicalLegacyServiceNames.contains(trimmed)
    }
}
