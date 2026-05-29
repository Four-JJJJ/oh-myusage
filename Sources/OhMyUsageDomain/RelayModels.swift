import Foundation

public struct RelayProviderConfig: Codable, Equatable, Sendable {
    public var adapterID: String?
    public var baseURL: String
    public var tokenChannelEnabled: Bool
    public var balanceChannelEnabled: Bool
    public var balanceAuth: AuthConfig
    public var balanceCredentialMode: RelayCredentialMode?
    public var quotaDisplayMode: OfficialQuotaDisplayMode
    public var showExpirationTimeInMenuBar: Bool
    public var manualOverrides: RelayManualOverride?

    public init(
        adapterID: String? = nil,
        baseURL: String,
        tokenChannelEnabled: Bool = true,
        balanceChannelEnabled: Bool = false,
        balanceAuth: AuthConfig,
        balanceCredentialMode: RelayCredentialMode? = nil,
        quotaDisplayMode: OfficialQuotaDisplayMode = .remaining,
        showExpirationTimeInMenuBar: Bool = true,
        manualOverrides: RelayManualOverride? = nil
    ) {
        self.adapterID = adapterID
        self.baseURL = baseURL
        self.tokenChannelEnabled = tokenChannelEnabled
        self.balanceChannelEnabled = balanceChannelEnabled
        self.balanceAuth = balanceAuth
        self.balanceCredentialMode = balanceCredentialMode
        self.quotaDisplayMode = quotaDisplayMode
        self.showExpirationTimeInMenuBar = showExpirationTimeInMenuBar
        self.manualOverrides = manualOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case adapterID
        case baseURL
        case tokenChannelEnabled
        case balanceChannelEnabled
        case balanceAuth
        case balanceCredentialMode
        case quotaDisplayMode
        case showExpirationTimeInMenuBar
        case manualOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.adapterID = try container.decodeIfPresent(String.self, forKey: .adapterID)
        self.baseURL = try container.decode(String.self, forKey: .baseURL)
        self.tokenChannelEnabled = try container.decodeIfPresent(Bool.self, forKey: .tokenChannelEnabled) ?? true
        self.balanceChannelEnabled = try container.decodeIfPresent(Bool.self, forKey: .balanceChannelEnabled) ?? false
        self.balanceAuth = try container.decode(AuthConfig.self, forKey: .balanceAuth)
        self.balanceCredentialMode = try container.decodeIfPresent(RelayCredentialMode.self, forKey: .balanceCredentialMode)
        self.quotaDisplayMode = try container.decodeIfPresent(OfficialQuotaDisplayMode.self, forKey: .quotaDisplayMode) ?? .remaining
        self.showExpirationTimeInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showExpirationTimeInMenuBar) ?? true
        self.manualOverrides = try container.decodeIfPresent(RelayManualOverride.self, forKey: .manualOverrides)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(adapterID, forKey: .adapterID)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(tokenChannelEnabled, forKey: .tokenChannelEnabled)
        try container.encode(balanceChannelEnabled, forKey: .balanceChannelEnabled)
        try container.encode(balanceAuth, forKey: .balanceAuth)
        try container.encodeIfPresent(balanceCredentialMode, forKey: .balanceCredentialMode)
        try container.encode(quotaDisplayMode, forKey: .quotaDisplayMode)
        try container.encode(showExpirationTimeInMenuBar, forKey: .showExpirationTimeInMenuBar)
        try container.encodeIfPresent(manualOverrides, forKey: .manualOverrides)
    }
}

public enum RelayCredentialMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manualPreferred
    case browserPreferred
    case browserOnly

    public var id: String { rawValue }
}

public struct RelayManualOverride: Codable, Equatable, Sendable {
    public var authHeader: String?
    public var authScheme: String?
    public var userID: String?
    public var userIDHeader: String?
    public var requestMethod: String?
    public var requestBodyJSON: String?
    public var endpointPath: String?
    public var remainingExpression: String?
    public var usedExpression: String?
    public var limitExpression: String?
    public var successExpression: String?
    public var unitExpression: String?
    public var accountLabelExpression: String?
    public var staticHeaders: [String: String]?

    public init(
        authHeader: String? = nil,
        authScheme: String? = nil,
        userID: String? = nil,
        userIDHeader: String? = nil,
        requestMethod: String? = nil,
        requestBodyJSON: String? = nil,
        endpointPath: String? = nil,
        remainingExpression: String? = nil,
        usedExpression: String? = nil,
        limitExpression: String? = nil,
        successExpression: String? = nil,
        unitExpression: String? = nil,
        accountLabelExpression: String? = nil,
        staticHeaders: [String: String]? = nil
    ) {
        self.authHeader = authHeader
        self.authScheme = authScheme
        self.userID = userID
        self.userIDHeader = userIDHeader
        self.requestMethod = requestMethod
        self.requestBodyJSON = requestBodyJSON
        self.endpointPath = endpointPath
        self.remainingExpression = remainingExpression
        self.usedExpression = usedExpression
        self.limitExpression = limitExpression
        self.successExpression = successExpression
        self.unitExpression = unitExpression
        self.accountLabelExpression = accountLabelExpression
        self.staticHeaders = staticHeaders
    }

    public var isEmpty: Bool {
        authHeader == nil &&
        authScheme == nil &&
        userID == nil &&
        userIDHeader == nil &&
        requestMethod == nil &&
        requestBodyJSON == nil &&
        endpointPath == nil &&
        remainingExpression == nil &&
        usedExpression == nil &&
        limitExpression == nil &&
        successExpression == nil &&
        unitExpression == nil &&
        accountLabelExpression == nil &&
        (staticHeaders?.isEmpty ?? true)
    }
}

public enum RelayAuthStrategyKind: String, Codable, CaseIterable, Sendable {
    case savedBearer
    case browserBearer
    case savedCookieHeader
    case browserCookieHeader
    case namedCookie
    case customHeader
}

public struct RelayAuthStrategy: Codable, Equatable, Sendable {
    public var kind: RelayAuthStrategyKind
    public var cookieName: String?

    public init(kind: RelayAuthStrategyKind, cookieName: String? = nil) {
        self.kind = kind
        self.cookieName = cookieName
    }
}

public struct RelayAdapterMatch: Codable, Equatable, Sendable {
    public var hostPatterns: [String]
    public var defaultDisplayName: String?
    public var defaultTokenChannelEnabled: Bool
    public var defaultBalanceChannelEnabled: Bool

    public init(
        hostPatterns: [String],
        defaultDisplayName: String? = nil,
        defaultTokenChannelEnabled: Bool = true,
        defaultBalanceChannelEnabled: Bool = false
    ) {
        self.hostPatterns = hostPatterns
        self.defaultDisplayName = defaultDisplayName
        self.defaultTokenChannelEnabled = defaultTokenChannelEnabled
        self.defaultBalanceChannelEnabled = defaultBalanceChannelEnabled
    }
}

public enum RelayRequiredInputKind: String, Codable, CaseIterable, Sendable {
    case displayName
    case baseURL
    case quotaAuth
    case balanceAuth
    case userID
}

public struct RelaySetupManifest: Codable, Equatable, Sendable {
    public struct LocalizedText: Codable, Equatable, Sendable {
        public var zhHans: String?
        public var en: String?

        public init(zhHans: String? = nil, en: String? = nil) {
            self.zhHans = zhHans
            self.en = en
        }
    }

    public var recommendedBaseURL: String?
    public var requiredInputs: [RelayRequiredInputKind]
    public var quotaAuthHint: LocalizedText?
    public var balanceAuthHint: LocalizedText?
    public var userIDHint: LocalizedText?
    public var diagnosticHints: LocalizedText?

    public init(
        recommendedBaseURL: String? = nil,
        requiredInputs: [RelayRequiredInputKind] = [],
        quotaAuthHint: LocalizedText? = nil,
        balanceAuthHint: LocalizedText? = nil,
        userIDHint: LocalizedText? = nil,
        diagnosticHints: LocalizedText? = nil
    ) {
        self.recommendedBaseURL = recommendedBaseURL
        self.requiredInputs = requiredInputs
        self.quotaAuthHint = quotaAuthHint
        self.balanceAuthHint = balanceAuthHint
        self.userIDHint = userIDHint
        self.diagnosticHints = diagnosticHints
    }
}

public struct RelayRequestManifest: Codable, Equatable, Sendable {
    public var method: String
    public var path: String
    public var bodyJSON: String?
    public var headers: [String: String]?
    public var userID: String?
    public var userIDHeader: String?
    public var authHeader: String?
    public var authScheme: String?

    public init(
        method: String = "GET",
        path: String,
        bodyJSON: String? = nil,
        headers: [String: String]? = nil,
        userID: String? = nil,
        userIDHeader: String? = nil,
        authHeader: String? = nil,
        authScheme: String? = nil
    ) {
        self.method = method
        self.path = path
        self.bodyJSON = bodyJSON
        self.headers = headers
        self.userID = userID
        self.userIDHeader = userIDHeader
        self.authHeader = authHeader
        self.authScheme = authScheme
    }
}

public struct RelayTokenRequestManifest: Codable, Equatable, Sendable {
    public var usagePath: String
    public var subscriptionPath: String?
    public var billingUsagePath: String?

    public init(
        usagePath: String = "/api/usage/token/",
        subscriptionPath: String? = "/v1/dashboard/billing/subscription",
        billingUsagePath: String? = "/v1/dashboard/billing/usage"
    ) {
        self.usagePath = usagePath
        self.subscriptionPath = subscriptionPath
        self.billingUsagePath = billingUsagePath
    }
}

public struct RelayExtractManifest: Codable, Equatable, Sendable {
    public var success: String?
    public var remaining: String
    public var used: String?
    public var limit: String?
    public var unit: String?
    public var accountLabel: String?

    public init(
        success: String? = nil,
        remaining: String,
        used: String? = nil,
        limit: String? = nil,
        unit: String? = nil,
        accountLabel: String? = nil
    ) {
        self.success = success
        self.remaining = remaining
        self.used = used
        self.limit = limit
        self.unit = unit
        self.accountLabel = accountLabel
    }
}

public enum RelayPostprocessID: String, Codable, Equatable, Sendable {
    case quotaDisplayStatus
}

public enum RelayDisplayMode: String, Codable, Equatable, Sendable {
    case balance
    case quotaPercent
    case hybrid
}

public struct RelayAdapterManifest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var match: RelayAdapterMatch
    public var setup: RelaySetupManifest?
    public var authStrategies: [RelayAuthStrategy]
    public var displayMode: RelayDisplayMode
    public var supportsBrowserFallback: Bool
    public var supportsSeparateBalanceAuth: Bool
    public var balanceRequest: RelayRequestManifest
    public var tokenRequest: RelayTokenRequestManifest?
    public var extract: RelayExtractManifest
    public var postprocessID: RelayPostprocessID?

    public init(
        id: String,
        displayName: String,
        match: RelayAdapterMatch,
        setup: RelaySetupManifest? = nil,
        authStrategies: [RelayAuthStrategy],
        displayMode: RelayDisplayMode = .balance,
        supportsBrowserFallback: Bool = true,
        supportsSeparateBalanceAuth: Bool = true,
        balanceRequest: RelayRequestManifest,
        tokenRequest: RelayTokenRequestManifest? = nil,
        extract: RelayExtractManifest,
        postprocessID: RelayPostprocessID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.match = match
        self.setup = setup
        self.authStrategies = authStrategies
        self.displayMode = displayMode
        self.supportsBrowserFallback = supportsBrowserFallback
        self.supportsSeparateBalanceAuth = supportsSeparateBalanceAuth
        self.balanceRequest = balanceRequest
        self.tokenRequest = tokenRequest
        self.extract = extract
        self.postprocessID = postprocessID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case match
        case setup
        case authStrategies
        case displayMode
        case supportsBrowserFallback
        case supportsSeparateBalanceAuth
        case balanceRequest
        case tokenRequest
        case extract
        case postprocessID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        match = try container.decode(RelayAdapterMatch.self, forKey: .match)
        setup = try container.decodeIfPresent(RelaySetupManifest.self, forKey: .setup)
        authStrategies = try container.decode([RelayAuthStrategy].self, forKey: .authStrategies)
        displayMode = try container.decodeIfPresent(RelayDisplayMode.self, forKey: .displayMode) ?? .balance
        supportsBrowserFallback = try container.decodeIfPresent(Bool.self, forKey: .supportsBrowserFallback) ?? true
        supportsSeparateBalanceAuth = try container.decodeIfPresent(Bool.self, forKey: .supportsSeparateBalanceAuth) ?? true
        balanceRequest = try container.decode(RelayRequestManifest.self, forKey: .balanceRequest)
        tokenRequest = try container.decodeIfPresent(RelayTokenRequestManifest.self, forKey: .tokenRequest)
        extract = try container.decode(RelayExtractManifest.self, forKey: .extract)
        postprocessID = try container.decodeIfPresent(RelayPostprocessID.self, forKey: .postprocessID)
    }
}
