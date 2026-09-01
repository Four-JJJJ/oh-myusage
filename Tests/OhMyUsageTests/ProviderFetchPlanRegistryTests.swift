import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class ProviderFetchPlanRegistryTests: XCTestCase {
    private let registry = ProviderFetchPlanRegistry()

    func testEveryProviderTypeHasAPlan() {
        for type in ProviderType.allCases {
            let plan = registry.plan(for: type)
            XCTAssertEqual(plan.providerType, type)
        }
    }

    func testEveryPlanHasPositiveTTLOrdering() {
        for type in ProviderType.allCases {
            let plan = registry.plan(for: type)
            XCTAssertGreaterThan(plan.activeTTL, 0, "\(type) activeTTL must be positive")
            XCTAssertGreaterThanOrEqual(
                plan.backgroundTTL,
                plan.activeTTL,
                "\(type) background refresh must not be more frequent than active refresh"
            )
            XCTAssertGreaterThanOrEqual(
                plan.metadataTTL,
                plan.backgroundTTL,
                "\(type) metadata changes slower than quota data"
            )
        }
    }

    func testActiveTTLFollowsCurrentDefaultPollIntervals() {
        // Anchored at OfficialProviderDefaultCatalog pollIntervalSec defaults.
        XCTAssertEqual(registry.plan(for: .codex).activeTTL, 120)
        XCTAssertEqual(registry.plan(for: .claude).activeTTL, 120)
        XCTAssertEqual(registry.plan(for: .gemini).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .copilot).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .microsoftCopilot).activeTTL, 120)
        XCTAssertEqual(registry.plan(for: .zai).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .zaiBalance).activeTTL, 300)
        XCTAssertEqual(registry.plan(for: .amp).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .cursor).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .jetbrains).activeTTL, 120)
        XCTAssertEqual(registry.plan(for: .kiro).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .windsurf).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .trae).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .kimi).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .kimiBalance).activeTTL, 300)
        XCTAssertEqual(registry.plan(for: .grok).activeTTL, 120)
        XCTAssertEqual(registry.plan(for: .openrouterCredits).activeTTL, 60)
        XCTAssertEqual(registry.plan(for: .openrouterAPI).activeTTL, 60)
        // Relay descriptors clamp poll intervals to >= 120 during migration.
        XCTAssertEqual(registry.plan(for: .relay).activeTTL, 120)
        XCTAssertEqual(registry.plan(for: .open).activeTTL, 120)
        XCTAssertEqual(registry.plan(for: .dragon).activeTTL, 120)
    }

    func testWebOnlyProvidersUseLongerTTLOnlyWhereTheConsoleIsTheDataSource() {
        // Plan §8.4: Web-only providers should refresh less aggressively to keep
        // console session traffic low; balance channels also poll slower.
        for type in [ProviderType.qwen, .qwenBalance, .ollamaCloud, .opencodeGo] {
            XCTAssertGreaterThanOrEqual(
                registry.plan(for: type).activeTTL,
                300,
                "\(type) is web-session sourced and needs a longer active TTL"
            )
            XCTAssertGreaterThanOrEqual(
                registry.plan(for: type).backgroundTTL,
                1_800,
                "\(type) is web-session sourced and needs a longer background TTL"
            )
        }
        for type in [ProviderType.zaiBalance, .kimiBalance, .qwenBalance] {
            XCTAssertEqual(
                registry.plan(for: type).backgroundTTL,
                1_800,
                "\(type) balance changes slowly and background refreshes can space out"
            )
        }
        // API/OAuth providers keep the plan §9.3 background magnitude.
        for type in [ProviderType.codex, .claude, .gemini, .copilot, .relay] {
            XCTAssertEqual(registry.plan(for: type).backgroundTTL, 900)
        }
    }

    func testRequiresBrowserAccessMatchesWebOnlyProviders() {
        // Providers whose only live data source is a console session cookie.
        let webOnlyTypes: Set<ProviderType> = [.qwen, .qwenBalance, .ollamaCloud]
        for type in ProviderType.allCases {
            let plan = registry.plan(for: type)
            XCTAssertEqual(
                plan.requiresBrowserAccess,
                webOnlyTypes.contains(type),
                "\(type) requiresBrowserAccess should be \(webOnlyTypes.contains(type))"
            )
        }
    }

    func testBrowserAccessAlwaysImpliesWebOverlaySupport() {
        for type in ProviderType.allCases {
            let plan = registry.plan(for: type)
            if plan.requiresBrowserAccess {
                XCTAssertTrue(plan.supportsWebOverlay, "\(type) requires browser access but denies web overlay")
            }
        }
    }

    func testWebOverlaySupportMatchesProviderBehavior() {
        let overlayTypes: Set<ProviderType> = [
            .codex, .claude, // OAuth usage + web overlay merge
            .relay, .open, .dragon, // browser credential recovery fallback
            .kimi, // legacy browser token fallback
            .trae, // browser JWT recovery fallback
            .ollamaCloud, .opencodeGo, .qwen, .qwenBalance // web console session
        ]
        for type in ProviderType.allCases {
            let plan = registry.plan(for: type)
            XCTAssertEqual(
                plan.supportsWebOverlay,
                overlayTypes.contains(type),
                "\(type) supportsWebOverlay should be \(overlayTypes.contains(type))"
            )
        }
    }

    func testLocalOnlyProvidersMakeZeroNetworkRequests() {
        for type in [ProviderType.jetbrains, .kiro] {
            let plan = registry.plan(for: type)
            XCTAssertEqual(plan.estimatedRequestCount, 0, "\(type) refreshes from local data only")
            XCTAssertFalse(plan.supportsWebOverlay)
            XCTAssertFalse(plan.requiresBrowserAccess)
        }
    }

    func testEstimatedRequestCountStaysWithinReasonableRange() {
        for type in ProviderType.allCases {
            let count = registry.plan(for: type).estimatedRequestCount
            XCTAssertGreaterThanOrEqual(count, 0, "\(type) request count must not be negative")
            XCTAssertLessThanOrEqual(count, 8, "\(type) request count looks implausibly high")
        }
    }

    func testEstimatedRequestCountMatchesCurrentRefreshBehavior() {
        // Gemini keeps loadCodeAssist + retrieveUserQuota (plan §8.4).
        XCTAssertEqual(registry.plan(for: .gemini).estimatedRequestCount, 2)
        // Microsoft Copilot fetches D7 and D30 reports.
        XCTAssertEqual(registry.plan(for: .microsoftCopilot).estimatedRequestCount, 2)
        // Single-endpoint providers.
        for type in [ProviderType.copilot, .amp, .cursor, .windsurf, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo, .kimiBalance, .zaiBalance] {
            XCTAssertEqual(registry.plan(for: type).estimatedRequestCount, 1, "\(type) is a single-request refresh")
        }
        // Qwen: session context + usage + subscription + addon list.
        XCTAssertEqual(registry.plan(for: .qwen).estimatedRequestCount, 4)
        // Qwen balance: session context + balance query.
        XCTAssertEqual(registry.plan(for: .qwenBalance).estimatedRequestCount, 2)
        // Relay runs token + balance channels per refresh.
        for type in [ProviderType.relay, .open, .dragon] {
            XCTAssertEqual(registry.plan(for: type).estimatedRequestCount, 2, "\(type) refreshes both channels")
        }
    }

    func testPlanMetadataTTLIsLongestForOrgAndPlanTierMetadata() {
        // Claude organization ID and Qwen plan tier metadata use a 24h TTL.
        XCTAssertEqual(registry.plan(for: .claude).metadataTTL, 86_400)
        XCTAssertEqual(registry.plan(for: .qwen).metadataTTL, 86_400)
        XCTAssertEqual(registry.plan(for: .qwenBalance).metadataTTL, 86_400)
        // Project/subscription metadata uses a 6h TTL.
        XCTAssertEqual(registry.plan(for: .gemini).metadataTTL, 21_600)
        XCTAssertEqual(registry.plan(for: .zai).metadataTTL, 21_600)
    }
}
