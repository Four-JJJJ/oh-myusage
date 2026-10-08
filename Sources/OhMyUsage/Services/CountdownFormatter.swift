import OhMyUsageDomain
import Foundation

enum CountdownFormatter {
    static func textWithTrustLabel(
        for window: UsageQuotaWindow,
        snapshotFreshness: ValueFreshness?,
        now: Date = Date(),
        placeholder: String,
        language: AppLanguage
    ) -> String {
        text(to: window.resetAt, now: now, placeholder: placeholder, language: language)
    }

    static func resetTrustLabel(
        for window: UsageQuotaWindow,
        snapshotFreshness: ValueFreshness?,
        language: AppLanguage
    ) -> String {
        if snapshotFreshness == .cachedFallback ||
            snapshotFreshness == .empty ||
            window.resetAt == nil ||
            window.confidence == .stale ||
            window.confidence == .unknown {
            return localized(zhHans: "待刷新", en: "Pending", language: language)
        }

        switch (window.resetSource, window.confidence) {
        case (.official, .confirmed):
            return localized(zhHans: "官方确认", en: "Official", language: language)
        case (.userCalibrated, .confirmed):
            return localized(zhHans: "用户校准", en: "Calibrated", language: language)
        case (.webObserved, _):
            return localized(zhHans: "网页观测", en: "Observed", language: language)
        case (.localEstimate, _):
            return localized(zhHans: "本地估算", en: "Estimated", language: language)
        case (.unknown, _):
            return localized(zhHans: "待刷新", en: "Pending", language: language)
        case (_, .estimated):
            return localized(zhHans: "本地估算", en: "Estimated", language: language)
        case (_, .stale), (_, .unknown):
            return localized(zhHans: "待刷新", en: "Pending", language: language)
        case (_, .confirmed):
            return localized(zhHans: "官方确认", en: "Official", language: language)
        }
    }

    static func text(
        to target: Date?,
        now: Date = Date(),
        placeholder: String,
        language: AppLanguage
    ) -> String {
        guard let target else { return placeholder }
        let interval = max(0, Int(target.timeIntervalSince(now)))
        let days = interval / 86_400
        if days > 0 {
            let hours = (interval % 86_400) / 3_600
            switch language {
            case .zhHans:
                return "\(days)天\(hours)时"
            case .en:
                return "\(days) d \(hours) h"
            }
        }
        let hours = interval / 3_600
        let minutes = (interval % 3_600) / 60
        switch language {
        case .zhHans:
            return "\(hours)时\(minutes)分"
        case .en:
            return "\(hours) h \(minutes) m"
        }
    }

    /// Subscription / plan expiry countdown shown beside the metric clock icon.
    static func expiryText(
        to target: Date?,
        now: Date = Date(),
        placeholder: String,
        language: AppLanguage
    ) -> String {
        guard let target else { return placeholder }
        let interval = max(0, Int(target.timeIntervalSince(now)))
        let days = interval / 86_400
        if days > 0 {
            switch language {
            case .zhHans:
                return "\(days)天到期"
            case .en:
                return "\(days)d left"
            }
        }
        let hours = max(1, interval / 3_600)
        switch language {
        case .zhHans:
            return "\(hours)时到期"
        case .en:
            return "\(hours)h left"
        }
    }

    private static func localized(zhHans: String, en: String, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return zhHans
        case .en:
            return en
        }
    }
}
