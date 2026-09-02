import OhMyUsageDomain
import XCTest
import OhMyUsageProviders
@testable import OhMyUsage

final class ProviderFactoryTests: XCTestCase {
    func testFactoryMapsRepresentativeProviderTypes() {
        let factory = ProviderFactory(keychain: makeTestKeychain())
        let cases: [(provider: ProviderDescriptor, expectedType: UsageProvider.Type)] = [
            (.defaultOfficialCodex(), CodexProvider.self),
            (.defaultOfficialClaude(), ClaudeProvider.self),
            (.defaultOfficialGemini(), GeminiProvider.self),
            (.defaultOfficialCopilot(), CopilotProvider.self),
            (.defaultOfficialMicrosoftCopilot(), MicrosoftCopilotProvider.self),
            (.defaultOfficialZai(), ZaiProvider.self),
            (.defaultOfficialZaiBalance(), ZaiProvider.self),
            (.defaultOfficialAmp(), AmpProvider.self),
            (.defaultOfficialCursor(), CursorProvider.self),
            (.defaultOfficialJetBrains(), JetBrainsProvider.self),
            (.defaultOfficialKiro(), KiroProvider.self),
            (.defaultOfficialWindsurf(), WindsurfProvider.self),
            (.defaultOfficialTrae(), TraeProvider.self),
            (.defaultOfficialOpenRouterCredits(), OpenRouterProvider.self),
            (.defaultOfficialOpenRouterAPI(), OpenRouterProvider.self),
            (.defaultOfficialOllamaCloud(), OllamaCloudProvider.self),
            (.defaultOfficialOpenCodeGo(), OpenCodeGoProvider.self),
            (.relayProvider(type: .relay), RelayProvider.self),
            (.relayProvider(type: .open), RelayProvider.self),
            (.relayProvider(type: .dragon), RelayProvider.self),
            (.defaultOfficialKimi(), KimiSmartProvider.self),
            (.defaultOfficialKimiBalance(), MoonshotBalanceProvider.self),
            (.defaultOfficialGrok(), GrokProvider.self),
            (.defaultOfficialQwen(), QwenProvider.self),
            (.defaultOfficialQwenBalance(), QwenProvider.self)
        ]

        XCTAssertEqual(cases.map(\.provider.type), ProviderType.allCases)
        for item in cases {
            XCTAssertTrue(
                type(of: factory.makeProvider(for: item.provider)) == item.expectedType,
                "\(item.provider.type) should map to \(item.expectedType)"
            )
        }
    }

    func testGeminiProviderUsesSharedCredentialBroker() throws {
        // doc 8.4：Gemini OAuth refresh 成功后的新 token 必须持久化到 vault——
        // 若注册表漏接 keychain，刷新结果会被丢弃并放大 refresh 请求量。
        let keychain = makeTestKeychain()
        let broker = CredentialBroker(keychain: keychain)
        let factory = ProviderFactory(keychain: keychain, credentialBroker: broker)

        let provider = try XCTUnwrap(factory.makeProvider(for: .defaultOfficialGemini()) as? GeminiProvider)
        let injected = try XCTUnwrap(provider.keychain)
        XCTAssertTrue((injected as AnyObject) === broker)
    }

    func testTraeProviderUsesInjectedBrowserCredentialService() throws {
        let browserCredentialService = BrowserCredentialService(
            bearerCandidatesOverride: { _ in [] },
            cacheTTL: 0
        )
        let factory = ProviderFactory(
            keychain: makeTestKeychain(),
            browserCredentialService: browserCredentialService
        )

        let provider = try XCTUnwrap(factory.makeProvider(for: ProviderDescriptor.defaultOfficialTrae()) as? TraeProvider)
        let injected = try XCTUnwrap(provider.browserCredentialService as? BrowserCredentialService)
        XCTAssertTrue(injected === browserCredentialService)
    }

    func testDefaultRegistryRegistersEveryProviderType() {
        let registry = ProviderFactoryRegistry()

        XCTAssertEqual(registry.registeredProviderTypes, Set(ProviderType.allCases))
    }

    func testFactoryCanExposeProviderFetchingAdapter() async throws {
        let descriptor = ProviderDescriptor(
            id: "test-provider",
            name: "Test Provider",
            type: .gemini,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 3, notifyOnAuthError: true),
            auth: .none
        )
        let factory = ProviderFactory(
            keychain: makeTestKeychain(),
            registry: ProviderFactoryRegistry(makers: Dictionary(
                uniqueKeysWithValues: ProviderType.allCases.map { type in
                    (type, { descriptor, _ in
                        StubUsageProvider(
                            descriptor: descriptor,
                            snapshot: UsageSnapshot(
                                source: descriptor.id,
                                status: .ok,
                                remaining: 30,
                                used: 70,
                                limit: 100,
                                unit: "tokens",
                                updatedAt: Date(timeIntervalSince1970: 123),
                                note: "ok"
                            )
                        )
                    } as ProviderFactoryRegistry.Maker)
                }
            ))
        )

        let fetcher = factory.makeProviderFetcher(for: descriptor)
        let snapshot = try await fetcher.fetchUsageSnapshot(forceRefresh: true)

        XCTAssertEqual(fetcher.providerID.rawValue, "test-provider")
        XCTAssertEqual(snapshot.used, 70)
        XCTAssertEqual(snapshot.limit, 100)
        XCTAssertEqual(snapshot.capturedAtUnixSeconds, 123)
    }
}

private extension ProviderDescriptor {
    static func relayProvider(type: ProviderType) -> ProviderDescriptor {
        ProviderDescriptor(
            id: "\(type.rawValue)-test",
            name: "\(type.rawValue) test",
            type: type,
            enabled: true,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 3, notifyOnAuthError: true),
            auth: .none,
            baseURL: "https://relay.example.com"
        )
    }
}

private struct StubUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot

    func fetch() async throws -> UsageSnapshot {
        snapshot
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        snapshot
    }
}
