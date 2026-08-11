import Foundation

/// Provider-side port for service/account token persistence.
/// Parallel to Infrastructure ``CredentialStoring`` so Providers never depend on Infrastructure.
public protocol TokenCredentialStoring: Sendable {
    func readToken(service: String, account: String) -> String?

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool

    @discardableResult
    func deleteToken(service: String, account: String) -> Bool
}

public enum TokenCredentialStoreServiceNames {
    public static let defaultServiceName = "oh-myusage"
    public static let legacyServiceName = "OhMyUsage"
}
