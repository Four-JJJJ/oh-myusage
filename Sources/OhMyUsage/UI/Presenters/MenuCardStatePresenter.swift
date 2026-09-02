import OhMyUsageDomain
import OhMyUsageApplication
import Foundation

struct MenuCardVisualPresentation: Equatable {
    var status: MenuCardStatusPresentation
    var errorText: String?
    var isDisconnected: Bool
    /// Border highlight tone. `nil` renders no border; `.error` marks
    /// error-level credibility problems (auth failure, refresh failure,
    /// disconnect). Warning-level degradations (cache fallback, estimates)
    /// stay border-free to keep normal screens quiet (doc §10.1).
    var highlightTone: MenuCardStatusPresentation.Tone?
}

struct MenuAmountCardPresentation: Equatable {
    var visual: MenuCardVisualPresentation
    var amountText: String
    var secondaryText: String?
    var balanceLabel: String
}

struct MenuSlotActionPresentation: Equatable {
    enum InfoTone: Equatable {
        case normal
        case error
    }

    var showsLeadingAccent: Bool
    var actionLabel: String?
    var actionDisabled: Bool
    var infoText: String?
    var infoTone: InfoTone
}

enum MenuCardStatePresenter {
    static func percentageVisualPresentation(
        snapshot: UsageSnapshot?,
        errorText: String?,
        healthPercents: [Double?],
        language: AppLanguage,
        tightText: String,
        sufficientText: String,
        exhaustedText: String,
        disconnectedText: String
    ) -> MenuCardVisualPresentation {
        let stale = snapshot?.valueFreshness == .cachedFallback
        let disconnected = errorText != nil && !stale
        let degraded = MenuCardStatusPresenter.degradedCredibilityStatus(
            snapshot: snapshot,
            disconnected: disconnected,
            disconnectedText: disconnectedText,
            language: language
        )

        return MenuCardVisualPresentation(
            status: MenuCardStatusPresenter.percentageStatus(
                healthPercents: healthPercents,
                snapshot: snapshot,
                disconnected: disconnected,
                language: language,
                tightText: tightText,
                sufficientText: sufficientText,
                exhaustedText: exhaustedText,
                disconnectedText: disconnectedText
            ),
            errorText: errorText,
            isDisconnected: disconnected,
            highlightTone: degraded?.tone == .error ? .error : nil
        )
    }

    static func amountPresentation(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        errorText: String?,
        language: AppLanguage,
        secondaryText: String?,
        usedLabel: String,
        balanceLabel: String,
        tightText: String,
        sufficientText: String,
        exhaustedText: String,
        disconnectedText: String
    ) -> MenuAmountCardPresentation {
        let stale = snapshot?.valueFreshness == .cachedFallback
        let disconnected = errorText != nil && !stale
        let degraded = MenuCardStatusPresenter.degradedCredibilityStatus(
            snapshot: snapshot,
            disconnected: disconnected,
            disconnectedText: disconnectedText,
            language: language
        )
        let visual = MenuCardVisualPresentation(
            status: MenuCardStatusPresenter.amountStatus(
                remaining: snapshot?.remaining,
                snapshot: snapshot,
                disconnected: disconnected,
                language: language,
                tightText: tightText,
                sufficientText: sufficientText,
                exhaustedText: exhaustedText,
                disconnectedText: disconnectedText
            ),
            errorText: errorText,
            isDisconnected: disconnected,
            highlightTone: degraded?.tone == .error ? .error : nil
        )

        return MenuAmountCardPresentation(
            visual: visual,
            // Cached fallback keeps showing the cached balance (doc §10.2
            // "显示旧数据"); only a live disconnect suppresses the value.
            amountText: disconnected ? "-" : formattedBalanceNumber(displayedAmountValue(provider: provider, snapshot: snapshot)),
            secondaryText: disconnected ? nil : secondaryText,
            balanceLabel: provider.displaysUsedQuota ? usedLabel : balanceLabel
        )
    }

    static func slotActionPresentation(
        isActive: Bool,
        canSwitch: Bool,
        isSwitching: Bool,
        actionLabel: String,
        infoText: String?,
        infoIsError: Bool
    ) -> MenuSlotActionPresentation {
        let showsSwitchAction = !isActive && canSwitch
        return MenuSlotActionPresentation(
            showsLeadingAccent: isActive,
            actionLabel: showsSwitchAction ? actionLabel : nil,
            actionDisabled: showsSwitchAction ? isSwitching : false,
            infoText: infoText,
            infoTone: infoIsError ? .error : .normal
        )
    }

    private static func displayedAmountValue(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?
    ) -> Double? {
        guard let snapshot else { return nil }
        if provider.displaysUsedQuota, let used = snapshot.used {
            return used
        }
        return snapshot.remaining
    }

    private static func formattedBalanceNumber(_ value: Double?) -> String {
        guard let value else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
