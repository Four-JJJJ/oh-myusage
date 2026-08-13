import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

struct ProviderFactoryRegistry {
    struct Dependencies {
        let keychain: any TokenCredentialStoring
        let kimiCookieService: any KimiBrowserCookieDetecting
        let browserCookieService: any BrowserCookieDetecting
        let browserCredentialService: any BrowserCredentialProviding
    }

    typealias Maker = (ProviderDescriptor, Dependencies) -> UsageProvider

    private let makers: [ProviderType: Maker]

    init(makers: [ProviderType: Maker] = Self.makeDefaultMakers()) {
        self.makers = makers
        precondition(
            Set(makers.keys) == Set(ProviderType.allCases),
            "ProviderFactoryRegistry must register every ProviderType"
        )
    }

    var registeredProviderTypes: Set<ProviderType> {
        Set(makers.keys)
    }

    func makeProvider(
        for descriptor: ProviderDescriptor,
        dependencies: Dependencies
    ) -> UsageProvider {
        guard let maker = makers[descriptor.type] else {
            preconditionFailure("Missing provider maker for \(descriptor.type)")
        }
        return maker(descriptor, dependencies)
    }

    private static func makeDefaultMakers() -> [ProviderType: Maker] {
        [
            .codex: { descriptor, dependencies in
                CodexProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .claude: { descriptor, dependencies in
                ClaudeProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService,
                    shell: DefaultShellCommandRunner()
                )
            },
            .gemini: { descriptor, _ in
                GeminiProvider(descriptor: descriptor, shell: DefaultShellCommandRunner())
            },
            .copilot: { descriptor, _ in
                CopilotProvider(descriptor: descriptor, shell: DefaultShellCommandRunner())
            },
            .microsoftCopilot: { descriptor, _ in
                MicrosoftCopilotProvider(descriptor: descriptor, shell: DefaultShellCommandRunner())
            },
            .zai: { descriptor, _ in
                ZaiProvider(descriptor: descriptor, localJSONReader: DefaultLocalJSONFileReader())
            },
            .amp: { descriptor, _ in
                AmpProvider(descriptor: descriptor, localJSONReader: DefaultLocalJSONFileReader())
            },
            .cursor: { descriptor, _ in
                CursorProvider(descriptor: descriptor, sqlite: DefaultSQLiteShell())
            },
            .jetbrains: { descriptor, _ in
                JetBrainsProvider(descriptor: descriptor, localJSONReader: DefaultLocalJSONFileReader())
            },
            .kiro: { descriptor, _ in
                KiroProvider(
                    descriptor: descriptor,
                    shell: DefaultShellCommandRunner(),
                    sqlite: DefaultSQLiteShell(),
                    localJSONReader: DefaultLocalJSONFileReader()
                )
            },
            .windsurf: { descriptor, _ in
                WindsurfProvider(descriptor: descriptor, sqlite: DefaultSQLiteShell())
            },
            .trae: { descriptor, dependencies in
                TraeProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCredentialService: dependencies.browserCredentialService
                )
            },
            .openrouterCredits: { descriptor, dependencies in
                OpenRouterProvider(descriptor: descriptor, keychain: dependencies.keychain)
            },
            .openrouterAPI: { descriptor, dependencies in
                OpenRouterProvider(descriptor: descriptor, keychain: dependencies.keychain)
            },
            .ollamaCloud: { descriptor, dependencies in
                OllamaCloudProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService
                )
            },
            .opencodeGo: { descriptor, dependencies in
                OpenCodeGoProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.browserCookieService,
                    sqlite: DefaultSQLiteShell()
                )
            },
            .relay: ProviderFactoryRegistry.makeRelayProvider,
            .open: ProviderFactoryRegistry.makeRelayProvider,
            .dragon: ProviderFactoryRegistry.makeRelayProvider,
            .kimi: { descriptor, dependencies in
                KimiSmartProvider(
                    descriptor: descriptor,
                    keychain: dependencies.keychain,
                    browserCookieService: dependencies.kimiCookieService
                )
            },
            .grok: { descriptor, _ in
                GrokProvider(descriptor: descriptor)
            }
        ]
    }

    private static func makeRelayProvider(
        descriptor: ProviderDescriptor,
        dependencies: Dependencies
    ) -> UsageProvider {
        RelayProvider(
            descriptor: descriptor,
            keychain: dependencies.keychain,
            browserCredentialService: dependencies.browserCredentialService
        )
    }
}
