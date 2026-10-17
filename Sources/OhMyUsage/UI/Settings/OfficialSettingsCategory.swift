import Foundation
import OhMyUsageDomain

enum OfficialSettingsCategory: String, CaseIterable {
    case subscription
    case api

    func detail(language: AppLanguage) -> String {
        switch self {
        case .subscription:
            return language == .zhHans ? "管理订阅账号、套餐额度与重置时间。" : "Manage subscription accounts, plan quotas, and resets."
        case .api:
            return language == .zhHans ? "管理开放平台凭证、账户余额与 API 用量。" : "Manage platform credentials, account balances, and API usage."
        }
    }

    static func resolve(for provider: ProviderDescriptor) -> Self? {
        guard provider.family == .official || provider.isOfficialRelayProvider else { return nil }
        if provider.isRelay {
            // Token Plan is a subscription even though its fetcher uses a relay adapter.
            return provider.usesXiaomimimoTokenPlanQuota ? .subscription : .api
        }
        switch provider.type {
        case .zaiBalance, .kimiBalance, .qwenBalance, .openrouterCredits, .openrouterAPI:
            return .api
        default:
            return .subscription
        }
    }

    func providers(in providers: [ProviderDescriptor]) -> [ProviderDescriptor] {
        let matching = providers.filter { Self.resolve(for: $0) == self }
        return matching.filter(\.enabled) + matching.filter { !$0.enabled }
    }
}

enum OfficialAPIUsagePresenter {
    static func amount(_ value: Double?, unit: String?) -> String {
        guard let value, value.isFinite else { return "—" }
        let amount = value.formatted(.number.precision(.fractionLength(0...2)))
        let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return unit.isEmpty ? amount : "\(amount) \(unit)"
    }
}
