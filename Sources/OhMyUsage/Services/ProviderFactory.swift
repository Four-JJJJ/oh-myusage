import Foundation
import OhMyUsageProviders

protocol ProviderFactorying {
    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider
}

extension ProviderFactorying {
    func makeProviderFetcher(for descriptor: ProviderDescriptor) -> any UsageProviderFetching {
        UsageProviderFetchingAdapter(provider: makeProvider(for: descriptor))
    }
}

final class ProviderFactory: ProviderFactorying {
    private let keychain: KeychainService
    private let credentialBroker: CredentialBroker
    private let kimiCookieService: KimiBrowserCookieService
    private let browserCookieService: BrowserCookieService
    private let browserCredentialService: BrowserCredentialService
    private let registry: ProviderFactoryRegistry

    init(
        keychain: KeychainService,
        credentialBroker: CredentialBroker? = nil,
        kimiCookieService: KimiBrowserCookieService = KimiBrowserCookieService(),
        browserCookieService: BrowserCookieService = BrowserCookieService(),
        browserCredentialService: BrowserCredentialService? = nil,
        registry: ProviderFactoryRegistry = ProviderFactoryRegistry()
    ) {
        self.keychain = keychain
        self.credentialBroker = credentialBroker ?? CredentialBroker(keychain: keychain)
        self.kimiCookieService = kimiCookieService
        self.browserCookieService = browserCookieService
        self.browserCredentialService = browserCredentialService ?? BrowserCredentialService(
            bearerService: kimiCookieService,
            cookieService: browserCookieService
        )
        self.registry = registry
    }

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        registry.makeProvider(
            for: descriptor,
            dependencies: ProviderFactoryRegistry.Dependencies(
                keychain: credentialBroker,
                kimiCookieService: kimiCookieService,
                browserCookieService: browserCookieService,
                browserCredentialService: browserCredentialService
            )
        )
    }

}
