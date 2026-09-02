import Foundation

struct MenuViewLocalization: Equatable {
    var updatedAgoLabel: String
    var quota: MenuQuotaLocalization
    var usedLabel: String
    var balanceLabel: String
    var tightText: String
    var sufficientText: String
    var exhaustedText: String
    var disconnectedText: String
    var codexSwitchAction: String
    var claudeSwitchAction: String
}

struct MenuViewClockContext: Equatable {
    var lastUpdatedAt: Date?
    var language: AppLanguage
    var updatedAgoLabel: String
}

struct MenuViewState: Equatable {
    var header: MenuDashboardHeaderPresentation
    var shouldShowPermissionGuide: Bool
    var cards: [MenuCardViewState]
    var clockContext: MenuViewClockContext
}

enum MenuCardViewState: Identifiable, Equatable {
    case percentage(MenuPercentageCardViewState)
    case amount(MenuAmountCardViewState)
    case officialGroup(MenuOfficialProviderGroupCardViewState)

    var id: String {
        switch self {
        case let .percentage(card):
            return card.id
        case let .amount(card):
            return card.id
        case let .officialGroup(card):
            return card.id
        }
    }
}

struct MenuPercentageCardViewState: Identifiable, Equatable {
    var id: String
    var title: String
    var planType: String?
    var iconName: String
    var iconFallback: String
    var subtitle: String?
    var status: MenuCardStatusPresentation
    var metrics: [MenuQuotaMetricDisplayPresentation]
    var errorText: String?
    var isDisconnected: Bool
    var highlightTone: MenuCardStatusPresentation.Tone?
}

struct MenuAmountCardViewState: Identifiable, Equatable {
    var id: String
    var title: String
    var planType: String?
    var iconName: String
    var iconFallback: String
    var status: MenuCardStatusPresentation
    var amountText: String
    var secondaryText: String?
    var errorText: String?
    var isDisconnected: Bool
    var highlightTone: MenuCardStatusPresentation.Tone?
    var balanceLabel: String
}

enum MenuOfficialProviderSwitchKind: Equatable {
    case codex
    case claude
}

struct MenuOfficialProviderGroupCardViewState: Identifiable, Equatable {
    var id: String
    var switchKind: MenuOfficialProviderSwitchKind
    var iconName: String
    var iconFallback: String
    var group: MenuOfficialProviderGroupPresentation<CodexSlotID>
}
