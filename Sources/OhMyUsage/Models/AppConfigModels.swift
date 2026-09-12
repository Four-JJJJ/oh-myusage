import Foundation

struct AppConfigDecodeDiagnostics: Equatable {
    var droppedProviderEntryCount: Int = 0

    var hadLossyProviderDecoding: Bool {
        droppedProviderEntryCount > 0
    }

    static let none = AppConfigDecodeDiagnostics()
}

struct AppConfigDecodeResult {
    var config: AppConfig
    var diagnostics: AppConfigDecodeDiagnostics
}

struct AppConfig: Codable, Equatable {
    var language: AppLanguage
    var resourceMode: ResourceMode
    var launchAtLoginEnabled: Bool
    var simplifiedRelayConfig: Bool
    var showOfficialAccountEmailInMenuBar: Bool
    var claudeStatusBarDisplaySlotID: CodexSlotID?
    var statusBarProviderID: String?
    var statusBarMultiUsageEnabled: Bool
    var statusBarMultiProviderIDs: [String]
    var statusBarAppearanceMode: StatusBarAppearanceMode
    var statusBarDisplayStyle: StatusBarDisplayStyle
    var providers: [ProviderDescriptor]

    init(
        language: AppLanguage = .zhHans,
        resourceMode: ResourceMode = .background5Minutes,
        launchAtLoginEnabled: Bool = false,
        simplifiedRelayConfig: Bool = true,
        showOfficialAccountEmailInMenuBar: Bool = false,
        claudeStatusBarDisplaySlotID: CodexSlotID? = nil,
        statusBarProviderID: String? = nil,
        statusBarMultiUsageEnabled: Bool = false,
        statusBarMultiProviderIDs: [String]? = nil,
        statusBarAppearanceMode: StatusBarAppearanceMode = .followWallpaper,
        statusBarDisplayStyle: StatusBarDisplayStyle = .iconPercent,
        providers: [ProviderDescriptor]
    ) {
        let normalizedProviders = providers.map { $0.normalized() }
        let resolvedStatusProviderID: String?
        if let statusBarProviderID,
           normalizedProviders.contains(where: { $0.id == statusBarProviderID && $0.enabled && $0.showsInMenuBar }) {
            resolvedStatusProviderID = statusBarProviderID
        } else {
            resolvedStatusProviderID = Self.defaultStatusBarProviderID(from: normalizedProviders)
        }
        self.language = language
        self.resourceMode = resourceMode
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.simplifiedRelayConfig = true
        self.showOfficialAccountEmailInMenuBar = showOfficialAccountEmailInMenuBar
        self.claudeStatusBarDisplaySlotID = claudeStatusBarDisplaySlotID
        self.statusBarProviderID = resolvedStatusProviderID
        self.statusBarMultiUsageEnabled = statusBarMultiUsageEnabled
        let decodedMultiProviderIDs = statusBarMultiProviderIDs
            ?? (resolvedStatusProviderID.map { [$0] } ?? [])
        self.statusBarMultiProviderIDs = Self.normalizedStatusBarMultiProviderIDs(
            decodedMultiProviderIDs,
            providers: normalizedProviders
        )
        self.statusBarAppearanceMode = statusBarAppearanceMode
        self.statusBarDisplayStyle = statusBarDisplayStyle
        self.providers = normalizedProviders
    }

    static let `default` = AppConfig(
        language: .zhHans,
        resourceMode: .background5Minutes,
        providers: ProviderDefaultCatalog.allDefaultProviders
    )

    private enum CodingKeys: String, CodingKey {
        case language
        case resourceMode
        case launchAtLoginEnabled
        case simplifiedRelayConfig
        case showOfficialAccountEmailInMenuBar
        case claudeStatusBarDisplaySlotID
        case statusBarProviderID
        case statusBarMultiUsageEnabled
        case statusBarMultiProviderIDs
        case statusBarAppearanceMode
        case statusBarDisplayStyle
        case providers
    }

    private struct LossyProviderDescriptorArray: Decodable {
        let values: [ProviderDescriptor]
        let droppedEntryCount: Int

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var decoded: [ProviderDescriptor] = []
            var droppedEntryCount = 0
            while !container.isAtEnd {
                let startIndex = container.currentIndex
                if let provider = try? container.decode(ProviderDescriptor.self) {
                    decoded.append(provider)
                    continue
                }
                guard (try? container.decode(JSONDiscardValue.self)) != nil,
                      container.currentIndex > startIndex else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Unable to skip invalid provider entry at index \(startIndex)"
                    )
                }
                droppedEntryCount += 1
            }
            values = decoded
            self.droppedEntryCount = droppedEntryCount
        }
    }

    private struct JSONDiscardValue: Decodable {
        init(from decoder: Decoder) throws {
            if var unkeyed = try? decoder.unkeyedContainer() {
                while !unkeyed.isAtEnd {
                    _ = try? unkeyed.decode(JSONDiscardValue.self)
                }
                return
            }

            if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
                for key in keyed.allKeys {
                    _ = try? keyed.decode(JSONDiscardValue.self, forKey: key)
                }
                return
            }

            _ = try? decoder.singleValueContainer()
        }
    }

    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    init(from decoder: Decoder) throws {
        self = try Self.decodePayload(from: decoder).config
    }

    static func decodeWithDiagnostics(from data: Data) throws -> AppConfigDecodeResult {
        let decoder = JSONDecoder()
        return try decoder.decode(AppConfigDiagnosticEnvelope.self, from: data).result
    }

    fileprivate static func decodePayload(from decoder: Decoder) throws -> AppConfigDecodeResult {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .zhHans
        let resourceMode = try container.decodeIfPresent(ResourceMode.self, forKey: .resourceMode) ?? .background5Minutes
        let launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        _ = try container.decodeIfPresent(Bool.self, forKey: .simplifiedRelayConfig)
        let showOfficialAccountEmailInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showOfficialAccountEmailInMenuBar) ?? false
        let claudeStatusBarDisplaySlotID = try container.decodeIfPresent(CodexSlotID.self, forKey: .claudeStatusBarDisplaySlotID)
        let providerPayload = try container.decodeIfPresent(LossyProviderDescriptorArray.self, forKey: .providers)
        let decodedProviders = providerPayload?.values ?? AppConfig.default.providers
        let statusBarProviderID = try container.decodeIfPresent(String.self, forKey: .statusBarProviderID)
        let statusBarMultiUsageEnabled = try container.decodeIfPresent(Bool.self, forKey: .statusBarMultiUsageEnabled) ?? false
        let decodedMultiProviderIDs = try container.decodeIfPresent([String].self, forKey: .statusBarMultiProviderIDs)
        let statusBarAppearanceMode = try container.decodeIfPresent(StatusBarAppearanceMode.self, forKey: .statusBarAppearanceMode)
            ?? .followWallpaper
        let statusBarDisplayStyle = try container.decodeIfPresent(StatusBarDisplayStyle.self, forKey: .statusBarDisplayStyle)
            ?? .iconPercent

        let config = AppConfig(
            language: language,
            resourceMode: resourceMode,
            launchAtLoginEnabled: launchAtLoginEnabled,
            simplifiedRelayConfig: true,
            showOfficialAccountEmailInMenuBar: showOfficialAccountEmailInMenuBar,
            claudeStatusBarDisplaySlotID: claudeStatusBarDisplaySlotID,
            statusBarProviderID: statusBarProviderID,
            statusBarMultiUsageEnabled: statusBarMultiUsageEnabled,
            statusBarMultiProviderIDs: decodedMultiProviderIDs,
            statusBarAppearanceMode: statusBarAppearanceMode,
            statusBarDisplayStyle: statusBarDisplayStyle,
            providers: decodedProviders
        )

        return AppConfigDecodeResult(
            config: config,
            diagnostics: AppConfigDecodeDiagnostics(
                droppedProviderEntryCount: providerPayload?.droppedEntryCount ?? 0
            )
        )
    }

    static func defaultStatusBarProviderID(from providers: [ProviderDescriptor]) -> String? {
        if let codex = providers.first(where: { $0.enabled && $0.showsInMenuBar && $0.type == .codex && $0.family == .official }) {
            return codex.id
        }
        return providers.first(where: { $0.enabled && $0.showsInMenuBar })?.id
    }

    static func normalizedStatusBarMultiProviderIDs(_ ids: [String], providers: [ProviderDescriptor]) -> [String] {
        let validProviderIDs = Set(providers.filter(\.showsInMenuBar).map(\.id))
        var seenIDs = Set<String>()
        var normalizedIDs: [String] = []
        for id in ids {
            guard validProviderIDs.contains(id), seenIDs.insert(id).inserted else { continue }
            normalizedIDs.append(id)
        }
        return normalizedIDs
    }

    static func statusBarMultiProviderIDsMatchingProviderOrder(
        _ ids: [String],
        providers: [ProviderDescriptor]
    ) -> [String] {
        let selectedIDs = Set(normalizedStatusBarMultiProviderIDs(ids, providers: providers))
        return providers.compactMap { provider in
            selectedIDs.contains(provider.id) ? provider.id : nil
        }
    }

    func statusBarProvidersForDisplay() -> [ProviderDescriptor] {
        if !statusBarMultiUsageEnabled {
            if let id = statusBarProviderID,
               let selected = providers.first(where: { $0.id == id && $0.enabled && $0.showsInMenuBar }) {
                return [selected]
            }
            if let fallbackID = Self.defaultStatusBarProviderID(from: providers),
               let fallback = providers.first(where: { $0.id == fallbackID && $0.enabled && $0.showsInMenuBar }) {
                return [fallback]
            }
            return []
        }

        let selectedIDs = Set(statusBarMultiProviderIDs)
        return providers.filter { provider in
            provider.enabled && provider.showsInMenuBar && selectedIDs.contains(provider.id)
        }
    }
}

private struct AppConfigDiagnosticEnvelope: Decodable {
    let result: AppConfigDecodeResult

    init(from decoder: Decoder) throws {
        self.result = try AppConfig.decodePayload(from: decoder)
    }
}
