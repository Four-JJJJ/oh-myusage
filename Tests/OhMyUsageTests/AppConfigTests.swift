import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class AppConfigTests: XCTestCase {
    func testDecodeOldConfigDefaultsToChineseLanguage() throws {
        let json = #"{"providers":[]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.language, .zhHans)
        XCTAssertNil(config.statusBarProviderID)
        XCTAssertNil(config.claudeStatusBarDisplaySlotID)
        XCTAssertFalse(config.statusBarMultiUsageEnabled)
        XCTAssertTrue(config.statusBarMultiProviderIDs.isEmpty)
        XCTAssertEqual(config.resourceMode, .background5Minutes)
        XCTAssertEqual(config.statusBarAppearanceMode, .followWallpaper)
        XCTAssertEqual(config.statusBarDisplayStyle, .iconPercent)
    }

    func testDecodeResourceModeWhenPresent() throws {
        let json = #"{"language":"zh-Hans","resourceMode":"background10m","providers":[]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.resourceMode, .background10Minutes)
    }

    func testDecodeLegacyResourceModeValues() throws {
        let json = #"{"language":"zh-Hans","resourceMode":"lowPower","providers":[]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.resourceMode, .background15Minutes)
    }

    func testDecodeSkipsInvalidProviderEntriesInsteadOfFailingWholeConfig() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"legacy-opencode-go",
              "name":"Legacy OpenCode Go",
              "family":"official",
              "type":"openCodeGo",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"bearer"}
            },
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":180,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.providers.count, 1)
        XCTAssertEqual(config.providers.first?.id, "codex-official")
        XCTAssertEqual(config.providers.first?.pollIntervalSec, 180)
    }

    func testDecodeWithDiagnosticsReportsDroppedProviderEntries() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"legacy-opencode-go",
              "name":"Legacy OpenCode Go",
              "family":"official",
              "type":"openCodeGo",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"bearer"}
            },
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":180,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#

        let decoded = try AppConfig.decodeWithDiagnostics(from: Data(json.utf8))

        XCTAssertTrue(decoded.diagnostics.hadLossyProviderDecoding)
        XCTAssertEqual(decoded.diagnostics.droppedProviderEntryCount, 1)
        XCTAssertEqual(decoded.config.providers.count, 1)
        XCTAssertEqual(decoded.config.providers.first?.id, "codex-official")
    }

    func testNormalizeRelayBaseURLStripsPathAndQuery() {
        let normalized = ProviderDescriptor.normalizeRelayBaseURL("platform.deepseek.com/usage?month=4")
        XCTAssertEqual(normalized, "https://platform.deepseek.com")
    }

    func testDefaultStatusBarProviderIsNilWhenNothingIsEnabled() {
        let config = AppConfig.default
        XCTAssertNil(config.statusBarProviderID)
    }

    func testDefaultStatusBarProviderUsesEnabledOfficialCodex() {
        let providers = [
            ProviderDescriptor.defaultOfficialCodex(),
            ProviderDescriptor.defaultOfficialClaude()
        ].map {
            var copy = $0
            copy.enabled = copy.type == .codex
            return copy
        }

        XCTAssertEqual(AppConfig.defaultStatusBarProviderID(from: providers), "codex-official")
    }

    func testDefaultProvidersIncludeNewOfficialSourcesWithStableOrder() {
        let ids = AppConfig.default.providers.map(\.id)
        XCTAssertEqual(
            ids.suffix(10),
            [
                "kimi-official",
                "moonshot-official",
                "minimax-official",
                "deepseek-official",
                "xiaomi-mimo-official",
                "trae-official",
                "openrouter-credits-official",
                "openrouter-api-official",
                "ollama-cloud-official",
                "opencode-go-official"
            ]
        )

        let trae = AppConfig.default.providers.first(where: { $0.id == "trae-official" })
        XCTAssertEqual(trae?.family, .official)
        XCTAssertEqual(trae?.type, .trae)
        XCTAssertEqual(trae?.auth.kind, .bearer)
        XCTAssertEqual(trae?.baseURL, "https://api-sg-central.trae.ai")

        let openRouterCredits = AppConfig.default.providers.first(where: { $0.id == "openrouter-credits-official" })
        XCTAssertEqual(openRouterCredits?.family, .official)
        XCTAssertEqual(openRouterCredits?.type, .openrouterCredits)
        XCTAssertEqual(openRouterCredits?.auth.kind, .bearer)
        XCTAssertEqual(openRouterCredits?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(openRouterCredits?.officialConfig?.webMode, .disabled)

        let openRouterAPI = AppConfig.default.providers.first(where: { $0.id == "openrouter-api-official" })
        XCTAssertEqual(openRouterAPI?.family, .official)
        XCTAssertEqual(openRouterAPI?.type, .openrouterAPI)
        XCTAssertEqual(openRouterAPI?.auth.kind, .bearer)
        XCTAssertEqual(openRouterAPI?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(openRouterAPI?.officialConfig?.webMode, .disabled)

        let ollama = AppConfig.default.providers.first(where: { $0.id == "ollama-cloud-official" })
        XCTAssertEqual(ollama?.family, .official)
        XCTAssertEqual(ollama?.type, .ollamaCloud)
        XCTAssertEqual(ollama?.auth.kind, AuthKind.none)
        XCTAssertEqual(ollama?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(ollama?.officialConfig?.webMode, .autoImport)

        let opencodeGo = AppConfig.default.providers.first(where: { $0.id == "opencode-go-official" })
        XCTAssertEqual(opencodeGo?.family, .official)
        XCTAssertEqual(opencodeGo?.type, .opencodeGo)
        XCTAssertEqual(opencodeGo?.auth.kind, AuthKind.none)
        XCTAssertEqual(opencodeGo?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(opencodeGo?.officialConfig?.webMode, .autoImport)
        XCTAssertEqual(opencodeGo?.officialConfig?.manualCookieAccount, "official/opencode-go/auth-cookie")

        let moonshot = AppConfig.default.providers.first(where: { $0.id == "moonshot-official" })
        XCTAssertEqual(moonshot?.family, .official)
        XCTAssertEqual(moonshot?.type, .relay)
        XCTAssertEqual(moonshot?.relayConfig?.adapterID, "moonshot")
        XCTAssertEqual(moonshot?.baseURL, "https://platform.moonshot.cn")
        XCTAssertNil(moonshot?.officialConfig)

        let minimax = AppConfig.default.providers.first(where: { $0.id == "minimax-official" })
        XCTAssertEqual(minimax?.family, .official)
        XCTAssertEqual(minimax?.type, .relay)
        XCTAssertEqual(minimax?.relayConfig?.adapterID, "minimax")
        XCTAssertEqual(minimax?.baseURL, "https://platform.minimaxi.com")
        XCTAssertNil(minimax?.officialConfig)

        let deepseek = AppConfig.default.providers.first(where: { $0.id == "deepseek-official" })
        XCTAssertEqual(deepseek?.family, .official)
        XCTAssertEqual(deepseek?.type, .relay)
        XCTAssertEqual(deepseek?.relayConfig?.adapterID, "deepseek")
        XCTAssertEqual(deepseek?.baseURL, "https://platform.deepseek.com")
        XCTAssertNil(deepseek?.officialConfig)

        let xiaomiMIMO = AppConfig.default.providers.first(where: { $0.id == "xiaomi-mimo-official" })
        XCTAssertEqual(xiaomiMIMO?.family, .official)
        XCTAssertEqual(xiaomiMIMO?.type, .relay)
        XCTAssertEqual(xiaomiMIMO?.relayConfig?.adapterID, "xiaomimimo-token-plan")
        XCTAssertEqual(xiaomiMIMO?.relayConfig?.quotaDisplayMode, .used)
        XCTAssertEqual(xiaomiMIMO?.baseURL, "https://platform.xiaomimimo.com")
        XCTAssertNil(xiaomiMIMO?.officialConfig)
    }

    func testDefaultProvidersDoNotIncludePresetThirdPartyRelays() {
        let thirdPartyRelays = AppConfig.default.providers.filter { $0.family == .thirdParty && $0.isRelay }
        XCTAssertTrue(thirdPartyRelays.isEmpty)
    }

    func testMigrationUpgradesOfficialXiaomiMIMOToTokenPlanAdapter() {
        var legacyMIMO = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        legacyMIMO.relayConfig?.adapterID = "xiaomimimo"
        legacyMIMO.relayConfig?.quotaDisplayMode = .remaining
        legacyMIMO.relayConfig?.tokenChannelEnabled = true
        legacyMIMO.enabled = true

        let config = AppConfig(language: .zhHans, providers: [legacyMIMO])
        let migrated = config.migratedWithSiteDefaults()
        let provider = try! XCTUnwrap(migrated.providers.first(where: { $0.id == "xiaomi-mimo-official" }))

        XCTAssertEqual(provider.type, .relay)
        XCTAssertEqual(provider.family, .official)
        XCTAssertEqual(provider.relayConfig?.adapterID, "xiaomimimo-token-plan")
        XCTAssertEqual(provider.relayConfig?.quotaDisplayMode, .used)
        XCTAssertEqual(provider.relayConfig?.tokenChannelEnabled, false)
        XCTAssertEqual(provider.relayConfig?.balanceChannelEnabled, true)
        XCTAssertTrue(provider.displaysUsedQuota)
    }

    func testMigrationPreservesOfficialXiaomiMIMOTokenPlanQuotaPreference() {
        var mimo = ProviderDescriptor.defaultOfficialXiaomiMIMO()
        mimo.relayConfig?.quotaDisplayMode = .remaining

        let config = AppConfig(language: .zhHans, providers: [mimo])
        let migrated = config.migratedWithSiteDefaults()
        let provider = try! XCTUnwrap(migrated.providers.first(where: { $0.id == "xiaomi-mimo-official" }))

        XCTAssertEqual(provider.relayConfig?.adapterID, "xiaomimimo-token-plan")
        XCTAssertEqual(provider.relayConfig?.quotaDisplayMode, .remaining)
        XCTAssertFalse(provider.displaysUsedQuota)
    }

    func testMigrationRepairsOfficialRelayProviderStoredWithWrongType() {
        var staleMIMO = ProviderDescriptor.defaultOfficialCodex()
        staleMIMO.id = "xiaomi-mimo-official"
        staleMIMO.name = "Xiaomi MIMO"
        staleMIMO.baseURL = "https://platform.xiaomimimo.com"
        staleMIMO.relayConfig = RelayProviderConfig(
            adapterID: "xiaomimimo",
            baseURL: "https://platform.xiaomimimo.com",
            tokenChannelEnabled: false,
            balanceChannelEnabled: true,
            balanceAuth: AuthConfig(
                kind: .bearer,
                keychainService: KeychainService.defaultServiceName,
                keychainAccount: "platform.xiaomimimo.com/session-cookie"
            ),
            quotaDisplayMode: .remaining
        )

        let config = AppConfig(language: .zhHans, providers: [staleMIMO])
        let migrated = config.migratedWithSiteDefaults()
        let provider = try! XCTUnwrap(migrated.providers.first(where: { $0.id == "xiaomi-mimo-official" }))

        XCTAssertEqual(provider.name, "Xiaomi MIMO")
        XCTAssertEqual(provider.type, .relay)
        XCTAssertNil(provider.officialConfig)
        XCTAssertEqual(provider.relayConfig?.adapterID, "xiaomimimo-token-plan")
        XCTAssertEqual(provider.relayDisplayMode, .quotaPercent)
    }

    func testDefaultProvidersIncludeMicrosoftCopilotOfficialDescriptor() {
        let microsoft = AppConfig.default.providers.first(where: { $0.id == "microsoft-copilot-official" })
        XCTAssertEqual(microsoft?.family, .official)
        XCTAssertEqual(microsoft?.type, .microsoftCopilot)
        XCTAssertEqual(microsoft?.baseURL, "https://graph.microsoft.com")
        XCTAssertEqual(microsoft?.officialConfig?.sourceMode, .auto)
        XCTAssertEqual(microsoft?.officialConfig?.webMode, .disabled)
    }

    func testDefaultOfficialClaudeUsesUsedQuotaDisplayMode() {
        XCTAssertEqual(
            ProviderDescriptor.defaultOfficialClaude().officialConfig?.quotaDisplayMode,
            .used
        )
    }

    func testDefaultOfficialTraeUsesPercentValueDisplayAndRemainingQuotaPreference() {
        let config = ProviderDescriptor.defaultOfficialConfig(type: .trae)
        XCTAssertEqual(config.traeValueDisplayMode, .percent)
        XCTAssertEqual(config.quotaDisplayMode, .remaining)
    }

    func testDecodeLegacyTraeQuotaDisplayModeMigratesToIndependentFields() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"trae-official",
              "name":"Official Trae",
              "family":"official",
              "type":"trae",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"bearer"},
              "baseURL":"https://api-sg-central.trae.ai",
              "officialConfig":{
                "sourceMode":"auto",
                "webMode":"disabled",
                "autoDiscoveryEnabled":true,
                "quotaDisplayMode":"used"
              }
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        let traeConfig = try XCTUnwrap(config.providers.first?.officialConfig)
        XCTAssertEqual(traeConfig.traeValueDisplayMode, .amount)
        XCTAssertEqual(traeConfig.quotaDisplayMode, .remaining)
    }

    func testThirdPartyDisplaysUsedQuotaFollowsRelayQuotaPreference() {
        var relayProvider = ProviderDescriptor.makeOpenRelay(
            name: "Relay Example",
            baseURL: "https://relay.example.com"
        )
        relayProvider.relayConfig?.quotaDisplayMode = .used
        relayProvider = relayProvider.normalized()
        XCTAssertTrue(relayProvider.displaysUsedQuota)

        relayProvider.relayConfig?.quotaDisplayMode = .remaining
        relayProvider = relayProvider.normalized()
        XCTAssertFalse(relayProvider.displaysUsedQuota)
    }

    func testExplicitGenericNewAPIRelayKeepsGenericAdapterForHiddenTemplateHosts() {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Manual NewAPI",
            baseURL: "https://platform.deepseek.com",
            preferredAdapterID: "generic-newapi"
        )
        .normalized()

        XCTAssertEqual(provider.family, .thirdParty)
        XCTAssertEqual(provider.relayConfig?.adapterID, "generic-newapi")
    }

    func testNormalizeXiaomimimoStripsTemplateDefaultManualOverrides() {
        var provider = ProviderDescriptor.makeOpenRelay(
            name: "Mimo",
            baseURL: "https://platform.xiaomimimo.com",
            preferredAdapterID: "xiaomimimo"
        )
        provider.relayConfig?.manualOverrides = RelayManualOverride(
            authHeader: "Cookie",
            authScheme: "",
            userID: nil,
            userIDHeader: "New-Api-User",
            requestMethod: "GET",
            requestBodyJSON: nil,
            endpointPath: "/api/v1/userProfile",
            remainingExpression: "coalesce(data.balance,data.data.balance,data.result.balance,data.user.balance,data.data.user.balance,data.account.balance,data.data.account.balance,data.result.account.balance,data.wallet.balance,data.data.wallet.balance,data.result.wallet.balance,data.walletBalance,data.data.walletBalance,data.result.walletBalance,data.accountBalance,data.data.accountBalance,data.result.accountBalance,data.availableBalance,data.data.availableBalance,data.result.availableBalance,data.available_amount,data.data.available_amount,data.result.available_amount,data.availableAmount,data.data.availableAmount,data.result.availableAmount,data.currentBalance,data.data.currentBalance,data.result.currentBalance,data.remainBalance,data.data.remainBalance,data.result.remainBalance,data.remainingBalance,data.data.remainingBalance,data.result.remainingBalance,data.amount,data.data.amount,data.result.amount,balance,availableBalance,available_amount,availableAmount,currentBalance,walletBalance,accountBalance,remainBalance,remainingBalance,amount)",
            usedExpression: "coalesce(data.monthlyUsage,data.data.monthlyUsage,data.result.monthlyUsage,data.monthlySpend,data.data.monthlySpend,data.result.monthlySpend,data.monthly_spend,data.data.monthly_spend,data.result.monthly_spend,data.used,data.data.used,data.result.used,data.consume,data.data.consume,data.result.consume,data.totalUsage,data.data.totalUsage,data.result.totalUsage,data.totalSpend,data.data.totalSpend,data.result.totalSpend,monthlyUsage,monthlySpend,monthly_spend,used,consume,totalUsage,totalSpend)",
            limitExpression: "coalesce(data.totalLimit,data.data.totalLimit,data.result.totalLimit,data.limit,data.data.limit,data.result.limit,data.totalAmount,data.data.totalAmount,data.result.totalAmount,data.total_amount,data.data.total_amount,data.result.total_amount,data.quota,data.data.quota,data.result.quota,totalLimit,limit,totalAmount,total_amount,quota)",
            successExpression: nil,
            unitExpression: "\"CNY\"",
            accountLabelExpression: nil,
            staticHeaders: ["X-Timezone": "Asia/Shanghai"]
        )

        let normalized = provider.normalized()
        XCTAssertEqual(normalized.relayConfig?.adapterID, "xiaomimimo")
        XCTAssertNil(normalized.relayConfig?.manualOverrides)
    }

    func testDecodeOfficialConfigDefaultsPlanTypeDisplayEnabled() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com",
              "officialConfig":{
                "sourceMode":"auto",
                "webMode":"autoImport",
                "manualCookieAccount":"official/codex/cookie-header",
                "autoDiscoveryEnabled":true,
                "quotaDisplayMode":"remaining"
              }
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.providers.first?.officialConfig?.showPlanTypeInMenuBar, true)
        XCTAssertEqual(config.providers.first?.officialConfig?.showExpirationTimeInMenuBar, true)
    }

    func testDecodeOfficialConfigPlanTypeDisplayWhenPresent() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com",
              "officialConfig":{
                "sourceMode":"auto",
                "webMode":"autoImport",
                "manualCookieAccount":"official/codex/cookie-header",
                "autoDiscoveryEnabled":true,
                "quotaDisplayMode":"remaining",
                "showPlanTypeInMenuBar":false,
                "showExpirationTimeInMenuBar":false
              }
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.providers.first?.officialConfig?.showPlanTypeInMenuBar, false)
        XCTAssertEqual(config.providers.first?.officialConfig?.showExpirationTimeInMenuBar, false)
    }

    func testDecodeMissingStatusBarProviderFallsBackToDefault() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.statusBarProviderID, "codex-official")
        XCTAssertNil(config.claudeStatusBarDisplaySlotID)
        XCTAssertEqual(config.statusBarMultiProviderIDs, ["codex-official"])
        XCTAssertFalse(config.statusBarMultiUsageEnabled)
        XCTAssertEqual(config.statusBarAppearanceMode, .followWallpaper)
        XCTAssertEqual(config.statusBarDisplayStyle, .iconPercent)
    }

    func testDecodeFiltersInvalidStatusBarMultiProviderIDs() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "statusBarProviderID":"codex-official",
          "statusBarMultiUsageEnabled":true,
          "statusBarMultiProviderIDs":["codex-official","ghost","codex-official","claude-official"],
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            },
            {
              "id":"claude-official",
              "name":"Official Claude",
              "family":"official",
              "type":"claude",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://claude.ai"
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.statusBarMultiUsageEnabled)
        XCTAssertEqual(config.statusBarMultiProviderIDs, ["codex-official", "claude-official"])
        XCTAssertEqual(config.statusBarAppearanceMode, .followWallpaper)
        XCTAssertEqual(config.statusBarDisplayStyle, .iconPercent)
    }

    func testDecodeFiltersHiddenMenuBarProviderFromStatusBarSelections() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "statusBarProviderID":"codex-official",
          "statusBarMultiUsageEnabled":true,
          "statusBarMultiProviderIDs":["codex-official","claude-official"],
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "showInMenuBar":false,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            },
            {
              "id":"claude-official",
              "name":"Official Claude",
              "family":"official",
              "type":"claude",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://claude.ai"
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.statusBarProviderID, "claude-official")
        XCTAssertEqual(config.statusBarMultiProviderIDs, ["claude-official"])
        XCTAssertFalse(config.providers.first(where: { $0.id == "codex-official" })?.showsInMenuBar ?? true)
    }

    func testDecodeClaudeStatusBarDisplaySlotIDWhenPresent() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "claudeStatusBarDisplaySlotID":"B",
          "providers":[
            {
              "id":"claude-official",
              "name":"Official Claude",
              "family":"official",
              "type":"claude",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://claude.ai"
            }
          ]
        }
        """#

        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.claudeStatusBarDisplaySlotID, .b)
    }

    func testDecodeStatusBarDisplayStyleWhenPresent() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "statusBarDisplayStyle":"barNamePercent",
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.statusBarDisplayStyle, .barNamePercent)
    }

    func testDecodeStatusBarAppearanceModeWhenPresent() throws {
        let json = #"""
        {
          "language":"zh-Hans",
          "statusBarAppearanceMode":"dark",
          "providers":[
            {
              "id":"codex-official",
              "name":"Official Codex",
              "family":"official",
              "type":"codex",
              "enabled":true,
              "pollIntervalSec":60,
              "threshold":{"lowRemaining":20,"maxConsecutiveFailures":2,"notifyOnAuthError":true},
              "auth":{"kind":"localCodex"},
              "baseURL":"https://chatgpt.com"
            }
          ]
        }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.statusBarAppearanceMode, .dark)
    }

    func testMigrationPromotesLegacyDefaultPollIntervalForCodexAndClaude() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.pollIntervalSec = 60
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.pollIntervalSec = 60

        let config = AppConfig(language: .zhHans, providers: [codex, claude])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "codex-official" })?.pollIntervalSec,
            120
        )
        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "claude-official" })?.pollIntervalSec,
            120
        )
    }

    func testMigrationDoesNotRewriteCustomOrNonTargetPollIntervals() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.pollIntervalSec = 90
        var claude = ProviderDescriptor.defaultOfficialClaude()
        claude.pollIntervalSec = 180
        var gemini = ProviderDescriptor.defaultOfficialGemini()
        gemini.pollIntervalSec = 60

        let config = AppConfig(language: .zhHans, providers: [codex, claude, gemini])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "codex-official" })?.pollIntervalSec,
            90
        )
        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "claude-official" })?.pollIntervalSec,
            180
        )
        XCTAssertEqual(
            migrated.providers.first(where: { $0.id == "gemini-official" })?.pollIntervalSec,
            60
        )
    }

    func testMigrationRemovesLegacyRelayExampleProvider() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: " Relay Example ",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )
        relay.id = "open-relay-example-legacy"
        relay.relayConfig?.baseURL = "relay.example.com/path?foo=bar"

        let config = AppConfig(language: .zhHans, providers: [relay])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertNil(migrated.providers.first(where: { $0.id == relay.id }))
    }

    func testMigrationRemovesLegacyRelayExampleProviderEvenWhenRenamed() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "My Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )
        relay.id = "open-relay-legacy-random"

        let config = AppConfig(language: .zhHans, providers: [relay])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertNil(migrated.providers.first(where: { $0.id == relay.id }))
    }

    func testMigrationRemovesLegacyRelayExampleProviderEvenWhenAdapterChanged() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Custom Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "deepseek"
        )
        relay.id = "open-random-relay-legacy"
        relay.relayConfig?.adapterID = "deepseek"

        let config = AppConfig(language: .zhHans, providers: [relay])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertNil(migrated.providers.first(where: { $0.id == relay.id }))
    }

    func testMigrationKeepsCustomGenericRelayProviderWhenHostIsNotRelayExample() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Custom Generic",
            baseURL: "https://api.custom-relay.dev",
            preferredAdapterID: "generic-newapi"
        )
        relay.id = "open-custom-relay-dev-1"

        let config = AppConfig(language: .zhHans, providers: [relay])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertNotNil(migrated.providers.first(where: { $0.id == relay.id }))
    }

    func testMigrationMovesHistoricalOfficialRelayConfigToOfficialProvider() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "My DeepSeek",
            baseURL: "https://platform.deepseek.com",
            preferredAdapterID: "deepseek"
        )
        relay.id = "open-old-deepseek"
        relay.enabled = true
        relay.pollIntervalSec = 180
        relay.auth = AuthConfig(
            kind: .bearer,
            keychainService: KeychainService.defaultServiceName,
            keychainAccount: "legacy/deepseek/token"
        )
        relay.relayConfig?.balanceAuth = relay.auth

        let config = AppConfig(
            language: .zhHans,
            statusBarProviderID: relay.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: [relay.id],
            providers: [relay]
        )
        let migrated = config.migratedWithSiteDefaults()
        let migratedDeepSeek = migrated.providers.first(where: { $0.id == "deepseek-official" })

        XCTAssertNil(migrated.providers.first(where: { $0.id == "open-old-deepseek" }))
        XCTAssertEqual(migratedDeepSeek?.family, .official)
        XCTAssertEqual(migratedDeepSeek?.type, .relay)
        XCTAssertEqual(migratedDeepSeek?.enabled, true)
        XCTAssertEqual(migratedDeepSeek?.pollIntervalSec, 180)
        XCTAssertEqual(migratedDeepSeek?.auth.keychainAccount, "legacy/deepseek/token")
        XCTAssertEqual(migratedDeepSeek?.relayConfig?.adapterID, "deepseek")
        XCTAssertEqual(migrated.statusBarProviderID, "deepseek-official")
        XCTAssertEqual(migrated.statusBarMultiProviderIDs, ["deepseek-official"])
    }

    func testMigrationMovesOfficialRelayDefaultsAfterKimiAndPreservesConfig() {
        let kimi = ProviderDescriptor.defaultOfficialKimi()
        let trae = ProviderDescriptor.defaultOfficialTrae()
        let openRouterCredits = ProviderDescriptor.defaultOfficialOpenRouterCredits()
        let openRouterAPI = ProviderDescriptor.defaultOfficialOpenRouterAPI()
        let ollamaCloud = ProviderDescriptor.defaultOfficialOllamaCloud()
        let openCodeGo = ProviderDescriptor.defaultOfficialOpenCodeGo()

        var moonshot = ProviderDescriptor.defaultOfficialMoonshot()
        moonshot.enabled = true
        moonshot.pollIntervalSec = 333
        moonshot.threshold.lowRemaining = 7
        moonshot.auth = AuthConfig(
            kind: .bearer,
            keychainService: KeychainService.defaultServiceName,
            keychainAccount: "custom/moonshot/token"
        )
        moonshot.relayConfig?.balanceAuth = moonshot.auth
        moonshot.showInMenuBar = false

        let config = AppConfig(
            language: .zhHans,
            providers: [
                kimi,
                trae,
                openRouterCredits,
                openRouterAPI,
                ollamaCloud,
                openCodeGo,
                moonshot,
                .defaultOfficialMiniMax(),
                .defaultOfficialDeepSeek(),
                .defaultOfficialXiaomiMIMO()
            ]
        )
        let migrated = config.migratedWithSiteDefaults()
        let ids = migrated.providers.map(\.id)
        let kimiIndex = try! XCTUnwrap(ids.firstIndex(of: "kimi-official"))

        XCTAssertEqual(
            Array(ids[kimiIndex..<(kimiIndex + 6)]),
            [
                "kimi-official",
                "moonshot-official",
                "minimax-official",
                "deepseek-official",
                "xiaomi-mimo-official",
                "trae-official"
            ]
        )

        let migratedMoonshot = try! XCTUnwrap(migrated.providers.first(where: { $0.id == "moonshot-official" }))
        XCTAssertTrue(migratedMoonshot.enabled)
        XCTAssertEqual(migratedMoonshot.pollIntervalSec, 333)
        XCTAssertEqual(migratedMoonshot.threshold.lowRemaining, 7)
        XCTAssertEqual(migratedMoonshot.auth.keychainAccount, "custom/moonshot/token")
        XCTAssertFalse(migratedMoonshot.showsInMenuBar)
    }

    func testMigrationRemovesLegacyGenericRelayProviderOnExampleDotComHosts() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Relay Fixture",
            baseURL: "https://relay-fixture.example.com",
            preferredAdapterID: "generic-newapi"
        )
        relay.id = "open-relay-fixture-example-com-1"

        let config = AppConfig(language: .zhHans, providers: [relay])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertNil(migrated.providers.first(where: { $0.id == relay.id }))
    }

    func testMigrationRemovesRelayFixtureDebugProviderOnFixtureHost() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Relay Fixture",
            baseURL: "https://relay-fixture.dev",
            preferredAdapterID: "generic-newapi"
        )
        relay.id = "open-relay-fixture-dev-1"

        let config = AppConfig(language: .zhHans, providers: [relay])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertNil(migrated.providers.first(where: { $0.id == relay.id }))
    }

    func testMigrationRemovesRelayFixtureDebugProviderOnPreferenceHost() {
        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Relay Fixture",
            baseURL: "https://relay-preference.dev",
            preferredAdapterID: "generic-newapi"
        )
        relay.id = "open-relay-preference-dev-1778063136"

        let config = AppConfig(language: .zhHans, providers: [relay])
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertNil(migrated.providers.first(where: { $0.id == relay.id }))
    }

    func testMigrationRemovesStatusBarRefreshFixtureProviders() {
        var first = ProviderDescriptor.makeOpenRelay(
            name: "First Relay",
            baseURL: "https://first-status-provider.test",
            preferredAdapterID: "generic-newapi"
        )
        first.id = "status-provider-first"

        var second = ProviderDescriptor.makeOpenRelay(
            name: "Second Relay",
            baseURL: "https://second-status-provider.test",
            preferredAdapterID: "generic-newapi"
        )
        second.id = "status-provider-second"

        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true

        let config = AppConfig(
            language: .zhHans,
            statusBarProviderID: second.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: [first.id, second.id, codex.id],
            providers: [first, second, codex]
        )
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertNil(migrated.providers.first(where: { $0.id == first.id }))
        XCTAssertNil(migrated.providers.first(where: { $0.id == second.id }))
        XCTAssertEqual(migrated.statusBarProviderID, codex.id)
        XCTAssertEqual(migrated.statusBarMultiProviderIDs, [codex.id])
    }

    func testMigrationStatusBarFallsBackWhenLegacyRelayExampleWasSelected() {
        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true

        var relay = ProviderDescriptor.makeOpenRelay(
            name: "Relay Example",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )
        relay.id = "open-relay-example-statusbar"

        let config = AppConfig(
            language: .zhHans,
            statusBarProviderID: relay.id,
            statusBarMultiUsageEnabled: true,
            statusBarMultiProviderIDs: [relay.id, codex.id],
            providers: [relay, codex]
        )
        let migrated = config.migratedWithSiteDefaults()

        XCTAssertEqual(migrated.statusBarProviderID, codex.id)
        XCTAssertEqual(migrated.statusBarMultiProviderIDs, [codex.id])
    }
}
