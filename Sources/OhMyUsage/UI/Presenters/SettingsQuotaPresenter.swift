import Foundation
import OhMyUsageDomain
import OhMyUsagePresentation

typealias OfficialMonitoringHealthStatus = OhMyUsagePresentation.OfficialMonitoringHealthStatus

enum SettingsQuotaPresenter {
    nonisolated static func resolvedOfficialMonitoringProvider(
        type: ProviderType,
        providers: [ProviderDescriptor]
    ) -> ProviderDescriptor {
        if let configured = providers.first(where: { $0.family == .official && $0.type == type }) {
            return configured
        }

        return ProviderDescriptor(
            id: "\(type.rawValue)-official",
            name: type.rawValue,
            family: .official,
            type: type,
            enabled: false,
            pollIntervalSec: 60,
            threshold: AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true),
            auth: .none,
            officialConfig: ProviderDescriptor.defaultOfficialConfig(type: type)
        )
    }

    nonisolated static func quotaMetricPercents(
        for window: UsageQuotaWindow,
        displaysUsedQuota: Bool
    ) -> (displayPercent: Double, healthPercent: Double) {
        OfficialMonitoringHealthPresenter.quotaMetricPercents(
            for: window,
            displaysUsedQuota: displaysUsedQuota
        )
    }

    nonisolated static func officialMonitoringHealthStatus(
        snapshot: UsageSnapshot?,
        healthPercents: [Double]
    ) -> OfficialMonitoringHealthStatus {
        OfficialMonitoringHealthPresenter.officialMonitoringHealthStatus(
            snapshot: snapshot,
            healthPercents: healthPercents
        )
    }
}

enum QuotaBlockagePresenter {
    nonisolated static func normalizedKind(
        for window: UsageQuotaWindow,
        provider: ProviderDescriptor
    ) -> UsageQuotaKind {
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if provider.type == .kimi, window.kind == .custom, normalizedTitle == "overall" {
            return .weekly
        }
        return window.kind
    }

    nonisolated static func isBlockedByDepletedWeeklyQuota(
        currentKind: UsageQuotaKind?,
        currentRemainingPercent: Double?,
        currentIsAvailable: Bool = true,
        candidateWindows: [(kind: UsageQuotaKind?, remainingPercent: Double?, isAvailable: Bool)]
    ) -> Bool {
        QuotaBlockagePolicy.isBlockedByDepletedWeeklyQuota(
            currentKind: currentKind,
            currentRemainingPercent: currentRemainingPercent,
            currentIsAvailable: currentIsAvailable,
            candidateWindows: candidateWindows
        )
    }

    nonisolated static func isBlockedByDepletedWeeklyQuota(
        window: UsageQuotaWindow,
        in windows: [UsageQuotaWindow],
        provider: ProviderDescriptor
    ) -> Bool {
        isBlockedByDepletedWeeklyQuota(
            currentKind: normalizedKind(for: window, provider: provider),
            currentRemainingPercent: window.remainingPercent,
            candidateWindows: windows.map {
                (
                    kind: normalizedKind(for: $0, provider: provider),
                    remainingPercent: $0.remainingPercent,
                    isAvailable: true
                )
            }
        )
    }
}
