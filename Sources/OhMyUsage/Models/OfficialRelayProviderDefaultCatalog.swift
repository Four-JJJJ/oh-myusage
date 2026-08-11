import Foundation
import OhMyUsageDomain

enum OfficialRelayProviderDefaultCatalog {
    static var allDefaultProviders: [ProviderDescriptor] {
        OfficialRelayMetadataCatalog.defaultProviderOrder.map { provider(forProviderID: $0) }
    }

    static func provider(forProviderID providerID: String) -> ProviderDescriptor {
        guard let metadata = OfficialRelayMetadataCatalog.metadata(forProviderID: providerID) else {
            preconditionFailure("Missing official relay metadata for \(providerID)")
        }
        return provider(metadata: metadata)
    }

    static func moonshot() -> ProviderDescriptor {
        provider(forProviderID: "moonshot-official")
    }

    static func miniMax() -> ProviderDescriptor {
        provider(forProviderID: "minimax-official")
    }

    static func deepSeek() -> ProviderDescriptor {
        provider(forProviderID: "deepseek-official")
    }

    static func xiaomiMIMO() -> ProviderDescriptor {
        provider(forProviderID: "xiaomi-mimo-official")
    }

    private static func provider(metadata: OfficialRelayMetadata) -> ProviderDescriptor {
        let auth = AuthConfig(
            kind: .bearer,
            keychainService: KeychainService.defaultServiceName,
            keychainAccount: metadata.keychainAccount
        )
        return ProviderDescriptor(
            id: metadata.providerID,
            name: metadata.displayName,
            family: .official,
            type: .relay,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 10, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: auth,
            baseURL: metadata.baseURL,
            relayConfig: RelayProviderDefaultCatalog.defaultConfig(
                id: metadata.providerID,
                baseURL: metadata.baseURL,
                preferredAdapterID: metadata.defaultAdapterID,
                auth: auth
            )
        )
        .normalized()
    }
}
