import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class KimiSmartProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor

    private let officialProvider: KimiOfficialProvider
    private let legacyProvider: KimiProvider

    init(
        descriptor: ProviderDescriptor,
        keychain: any TokenCredentialStoring,
        browserCookieService: any KimiBrowserCookieDetecting,
        session: URLSession = .shared
    ) {
        self.descriptor = descriptor
        self.officialProvider = KimiOfficialProvider(
            descriptor: descriptor,
            session: session,
            keychain: keychain
        )
        self.legacyProvider = KimiProvider(
            descriptor: Self.makeLegacyDescriptor(from: descriptor),
            session: session,
            keychain: keychain,
            browserCookieService: browserCookieService
        )
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        do {
            return try await officialProvider.fetch(forceRefresh: forceRefresh)
        } catch let error as ProviderError {
            guard shouldFallback(from: error) else { throw error }
            do {
                return try await legacyProvider.fetch(forceRefresh: forceRefresh)
            } catch {
                throw error
            }
        } catch {
            return try await legacyProvider.fetch(forceRefresh: forceRefresh)
        }
    }

    private func shouldFallback(from error: ProviderError) -> Bool {
        switch error {
        case .missingCredential,
             .unauthorized,
             .unauthorizedDetail,
             .invalidResponse,
             .unavailable,
             .timeout,
             .commandFailed,
             .rateLimited:
            return true
        }
    }

    private static func makeLegacyDescriptor(from descriptor: ProviderDescriptor) -> ProviderDescriptor {
        let authService = descriptor.auth.keychainService ?? TokenCredentialStoreServiceNames.defaultServiceName
        let authAccount = descriptor.auth.keychainAccount ?? "kimi.com/kimi-auth-manual"
        let auth = AuthConfig(
            kind: .bearer,
            keychainService: authService,
            keychainAccount: authAccount
        )
        let kimiConfig = descriptor.kimiConfig ?? KimiProviderConfig(
            authMode: .auto,
            manualTokenAccount: authAccount,
            autoCookieEnabled: true,
            browserOrder: [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]
        )

        var legacy = descriptor
        legacy.auth = auth
        legacy.kimiConfig = kimiConfig
        legacy.baseURL = "https://www.kimi.com"
        return legacy
    }
}
