import Foundation
import OhMyUsageDomain

/// Provider-scoped credential access built on top of ``CredentialStoring``.
public protocol UsageCredentialStore: Sendable {
    func credential(for providerID: UsageProviderIdentity) async throws -> String?
    func saveCredential(_ credential: String, for providerID: UsageProviderIdentity) async throws
    func removeCredential(for providerID: UsageProviderIdentity) async throws
}
