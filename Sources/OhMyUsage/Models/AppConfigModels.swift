import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

struct AppConfigDecodeDiagnostics: Equatable {
    var droppedProviderEntryCount: Int = 0
    /// One entry per user-editable enum field whose persisted raw value was
    /// unrecognized and therefore fell back to its default instead of failing
    /// the decode, e.g. "language=zh-hant" or
    /// "providers[0].officialConfig.sourceMode=cliOAuth".
    var unknownEnumFields: [String] = []

    var hadLossyProviderDecoding: Bool {
        droppedProviderEntryCount > 0
    }

    var hadUnknownEnumFallback: Bool {
        !unknownEnumFields.isEmpty
    }

    static let none = AppConfigDecodeDiagnostics()
}

struct AppConfigDecodeResult {
    var config: AppConfig
    var diagnostics: AppConfigDecodeDiagnostics
}

struct AppConfig: Codable, Equatable {
    /// Persisted config schema version. Increment by 1 whenever the persisted
    /// shape changes in a way a future migration might need to detect:
    ///   1 = 2.5.x and earlier (files written before this field existed; a
    ///       missing key decodes as 1)
    ///   2 = 2.6.0 (corrupt-snapshot archive + snapshot recovery)
    ///   3 = this change (enum fields decode tolerantly + schemaVersion anchor)
    /// Encoding always stamps the current version, so any re-saved config is
    /// self-upgraded. No cross-version migration runs yet; the field is an
    /// anchor for future migrations and for diagnostics.
    static let currentSchemaVersion = 3
    /// Value reported when decoding files written before the field existed.
    private static let schemaVersionBeforeVersioning = 1

    var schemaVersion: Int
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
        schemaVersion: Int = AppConfig.currentSchemaVersion,
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
        self.schemaVersion = schemaVersion
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
        case schemaVersion
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Always stamp the current schema version, even when the in-memory
        // value came from an older persisted file.
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(language, forKey: .language)
        try container.encode(resourceMode, forKey: .resourceMode)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encode(simplifiedRelayConfig, forKey: .simplifiedRelayConfig)
        try container.encode(showOfficialAccountEmailInMenuBar, forKey: .showOfficialAccountEmailInMenuBar)
        try container.encodeIfPresent(claudeStatusBarDisplaySlotID, forKey: .claudeStatusBarDisplaySlotID)
        try container.encodeIfPresent(statusBarProviderID, forKey: .statusBarProviderID)
        try container.encode(statusBarMultiUsageEnabled, forKey: .statusBarMultiUsageEnabled)
        try container.encode(statusBarMultiProviderIDs, forKey: .statusBarMultiProviderIDs)
        try container.encode(statusBarAppearanceMode, forKey: .statusBarAppearanceMode)
        try container.encode(statusBarDisplayStyle, forKey: .statusBarDisplayStyle)
        try container.encode(providers, forKey: .providers)
    }

    private struct LossyProviderDescriptorArray: Decodable {
        let values: [ProviderDescriptor]
        let droppedEntryCount: Int
        let unknownEnumFields: [String]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var decoded: [ProviderDescriptor] = []
            var droppedEntryCount = 0
            var unknownEnumFields: [String] = []
            while !container.isAtEnd {
                let startIndex = container.currentIndex
                let entryIndex = decoded.count + droppedEntryCount
                if let provider = try? container.decode(ProviderDescriptor.self) {
                    decoded.append(provider)
                    continue
                }
                // The strict decode failed. Before dropping the entry, give
                // the enum-tolerant path a chance to recover it: a single
                // unknown enum raw value (hand-edited config or a file written
                // by a newer build) must not cost the user a whole provider.
                let recovery = Self.decodeEntryWithEnumFallbacks(
                    from: &container,
                    entryIndex: entryIndex
                )
                if let provider = recovery.provider {
                    decoded.append(provider)
                    unknownEnumFields.append(contentsOf: recovery.unknownEnumFields)
                    continue
                }
                if recovery.consumedRawEntry {
                    droppedEntryCount += 1
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
            self.unknownEnumFields = unknownEnumFields
        }

        /// Attempts a tolerant re-decode of the current provider entry after a
        /// strict decode failure. Only non-identity enum fields are corrected
        /// (see `ProviderEntryEnumSanitizer`); unknown identity enums such as
        /// the provider type still fail here and the entry is dropped through
        /// the lossy path.
        ///
        /// A failed `ProviderDescriptor` decode leaves the element unconsumed,
        /// but a successful `ProviderEntryJSONValue` decode consumes it, so the
        /// result reports whether the raw entry was consumed to keep the
        /// caller's skip bookkeeping aligned.
        private static func decodeEntryWithEnumFallbacks(
            from container: inout UnkeyedDecodingContainer,
            entryIndex: Int
        ) -> (provider: ProviderDescriptor?, unknownEnumFields: [String], consumedRawEntry: Bool) {
            guard let rawEntry = try? container.decode(ProviderEntryJSONValue.self) else {
                return (nil, [], false)
            }
            let sanitized = ProviderEntryEnumSanitizer.sanitized(
                rawEntry,
                fieldPathPrefix: "providers[\(entryIndex)]"
            )
            guard sanitized.didModify,
                  let data = try? JSONEncoder().encode(sanitized.value),
                  let provider = try? JSONDecoder().decode(ProviderDescriptor.self, from: data) else {
                // The JSON value decode consumed the entry; the failure is
                // structural, not a recoverable enum, so the entry is dropped
                // without a second skip.
                return (nil, [], true)
            }
            return (provider, sanitized.unknownEnumFields, true)
        }
    }

    /// Self-contained JSON value tree used to inspect and repair a provider
    /// entry whose strict decode failed, before re-decoding it.
    private enum ProviderEntryJSONValue: Codable {
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        case null
        case array([ProviderEntryJSONValue])
        case object([String: ProviderEntryJSONValue])

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer() {
                if let boolValue = try? single.decode(Bool.self) {
                    self = .bool(boolValue)
                    return
                }
                if let intValue = try? single.decode(Int64.self) {
                    self = .int(intValue)
                    return
                }
                if let doubleValue = try? single.decode(Double.self) {
                    self = .double(doubleValue)
                    return
                }
                if let stringValue = try? single.decode(String.self) {
                    self = .string(stringValue)
                    return
                }
                if single.decodeNil() {
                    self = .null
                    return
                }
            }
            if var unkeyed = try? decoder.unkeyedContainer() {
                var items: [ProviderEntryJSONValue] = []
                while !unkeyed.isAtEnd {
                    items.append(try unkeyed.decode(ProviderEntryJSONValue.self))
                }
                self = .array(items)
                return
            }
            if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
                var dict: [String: ProviderEntryJSONValue] = [:]
                for key in keyed.allKeys {
                    dict[key.stringValue] = try keyed.decode(ProviderEntryJSONValue.self, forKey: key)
                }
                self = .object(dict)
                return
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .bool(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .int(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .double(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .string(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .null:
                var container = encoder.singleValueContainer()
                try container.encodeNil()
            case .array(let items):
                var container = encoder.unkeyedContainer()
                try container.encode(contentsOf: items)
            case .object(let dict):
                var container = encoder.container(keyedBy: AnyCodingKey.self)
                for key in dict.keys.sorted() {
                    guard let codingKey = AnyCodingKey(stringValue: key),
                          let value = dict[key] else {
                        continue
                    }
                    try container.encode(value, forKey: codingKey)
                }
            }
        }
    }

    /// Corrects unknown raw values of user-editable, non-identity enum fields
    /// inside a provider entry so the entry survives decoding with the field
    /// reset to its default. Known raw values are derived from the enums
    /// themselves (`CaseIterable`), so new cases never need a table update.
    ///
    /// Deliberately NOT covered (an unknown value still drops the entry via
    /// the lossy provider path):
    /// - `type` / `family`: identity of the entry; the existing drop semantics
    ///   for unknown identity enums are a red line of this design.
    /// - `AuthKind` fields: they wire credential lookups; a silent default
    ///   could misroute Keychain access, so failing loudly (entry dropped,
    ///   config preserved) is the safer degradation.
    private enum ProviderEntryEnumSanitizer {
        private enum Rule {
            case replaceScalar(path: [String], knownRawValues: Set<String>, fallbackRawValue: String)
            case removeKey(path: [String], knownRawValues: Set<String>)
            case dropUnknownArrayElements(path: [String], knownRawValues: Set<String>)
        }

        private static func knownRawValues<E: RawRepresentable & CaseIterable>(
            _ type: E.Type
        ) -> Set<String> where E.RawValue == String {
            Set(type.allCases.map(\.rawValue))
        }

        private static let rules: [Rule] = [
            .replaceScalar(
                path: ["officialConfig", "sourceMode"],
                knownRawValues: knownRawValues(OfficialSourceMode.self),
                fallbackRawValue: OfficialSourceMode.auto.rawValue
            ),
            .replaceScalar(
                path: ["officialConfig", "webMode"],
                knownRawValues: knownRawValues(OfficialWebMode.self),
                fallbackRawValue: OfficialWebMode.disabled.rawValue
            ),
            .replaceScalar(
                path: ["officialConfig", "quotaDisplayMode"],
                knownRawValues: knownRawValues(OfficialQuotaDisplayMode.self),
                fallbackRawValue: OfficialQuotaDisplayMode.remaining.rawValue
            ),
            .removeKey(
                path: ["officialConfig", "traeValueDisplayMode"],
                knownRawValues: knownRawValues(OfficialTraeValueDisplayMode.self)
            ),
            .replaceScalar(
                path: ["relayConfig", "quotaDisplayMode"],
                knownRawValues: knownRawValues(OfficialQuotaDisplayMode.self),
                fallbackRawValue: OfficialQuotaDisplayMode.remaining.rawValue
            ),
            .removeKey(
                path: ["relayConfig", "balanceCredentialMode"],
                knownRawValues: knownRawValues(RelayCredentialMode.self)
            ),
            .replaceScalar(
                path: ["kimiConfig", "authMode"],
                knownRawValues: knownRawValues(KimiAuthMode.self),
                fallbackRawValue: KimiAuthMode.auto.rawValue
            ),
            .dropUnknownArrayElements(
                path: ["kimiConfig", "browserOrder"],
                knownRawValues: knownRawValues(KimiBrowserKind.self)
            )
        ]

        static func sanitized(
            _ entry: ProviderEntryJSONValue,
            fieldPathPrefix: String
        ) -> (value: ProviderEntryJSONValue, unknownEnumFields: [String], didModify: Bool) {
            var sanitizedValue = entry
            var notes: [String] = []
            for rule in rules {
                switch rule {
                case let .replaceScalar(path, knownRawValues, fallbackRawValue):
                    if case .string(let raw)? = value(at: path, in: sanitizedValue), !knownRawValues.contains(raw) {
                        notes.append("\(fieldPathPrefix).\(path.joined(separator: "."))=\(raw)")
                        sanitizedValue = setValue(at: path, in: sanitizedValue, to: .string(fallbackRawValue)) ?? sanitizedValue
                    }
                case let .removeKey(path, knownRawValues):
                    if case .string(let raw)? = value(at: path, in: sanitizedValue), !knownRawValues.contains(raw) {
                        notes.append("\(fieldPathPrefix).\(path.joined(separator: "."))=\(raw)")
                        sanitizedValue = removeValue(at: path, in: sanitizedValue) ?? sanitizedValue
                    }
                case let .dropUnknownArrayElements(path, knownRawValues):
                    if case .array(let items)? = value(at: path, in: sanitizedValue) {
                        var kept: [ProviderEntryJSONValue] = []
                        for item in items {
                            if case .string(let raw) = item, !knownRawValues.contains(raw) {
                                notes.append("\(fieldPathPrefix).\(path.joined(separator: "."))=\(raw)")
                                continue
                            }
                            kept.append(item)
                        }
                        if kept.count != items.count {
                            sanitizedValue = setValue(at: path, in: sanitizedValue, to: .array(kept)) ?? sanitizedValue
                        }
                    }
                }
            }
            return (sanitizedValue, notes, !notes.isEmpty)
        }

        private static func value(at path: [String], in value: ProviderEntryJSONValue) -> ProviderEntryJSONValue? {
            var current = value
            for key in path {
                guard case .object(let dict) = current, let next = dict[key] else { return nil }
                current = next
            }
            return current
        }

        private static func setValue(
            at path: [String],
            in value: ProviderEntryJSONValue,
            to newValue: ProviderEntryJSONValue
        ) -> ProviderEntryJSONValue? {
            guard let key = path.first else { return newValue }
            guard case .object(var dict) = value else { return nil }
            if path.count == 1 {
                dict[key] = newValue
                return .object(dict)
            }
            guard let existing = dict[key],
                  let updated = setValue(at: Array(path.dropFirst()), in: existing, to: newValue) else {
                return nil
            }
            dict[key] = updated
            return .object(dict)
        }

        private static func removeValue(
            at path: [String],
            in value: ProviderEntryJSONValue
        ) -> ProviderEntryJSONValue? {
            guard let key = path.first, case .object(var dict) = value else { return nil }
            if path.count == 1 {
                dict.removeValue(forKey: key)
                return .object(dict)
            }
            guard let existing = dict[key],
                  let updated = removeValue(at: Array(path.dropFirst()), in: existing) else {
                return nil
            }
            dict[key] = updated
            return .object(dict)
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
        let decoded = try decoder.decode(AppConfigDiagnosticEnvelope.self, from: data).result
        if decoded.diagnostics.hadUnknownEnumFallback {
            NSLog(
                "[AppConfig] Unknown enum field values fell back to defaults: %@",
                decoded.diagnostics.unknownEnumFields.joined(separator: ", ")
            )
        }
        return decoded
    }

    /// Decodes a user-editable enum field, falling back to `fallback` with a
    /// diagnostic when the persisted value is unknown or malformed, instead of
    /// failing the whole config decode. A missing or null key keeps the legacy
    /// silent-default behavior (no diagnostic).
    private static func decodeUserFacingEnum<E: RawRepresentable>(
        _ type: E.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        fallback: E,
        field: String,
        recognize: (String) -> E?,
        unknownEnumFields: inout [String]
    ) -> E where E.RawValue == String {
        guard container.contains(key) else { return fallback }
        let rawValue: String?
        do {
            rawValue = try container.decodeIfPresent(String.self, forKey: key)
        } catch {
            unknownEnumFields.append("\(field)=<malformed value>")
            return fallback
        }
        guard let rawValue else { return fallback }
        guard let value = recognize(rawValue) else {
            unknownEnumFields.append("\(field)=\(rawValue)")
            return fallback
        }
        return value
    }

    fileprivate static func decodePayload(from decoder: Decoder) throws -> AppConfigDecodeResult {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.schemaVersionBeforeVersioning
        var unknownEnumFields: [String] = []
        let language = decodeUserFacingEnum(
            AppLanguage.self,
            from: container,
            forKey: .language,
            fallback: .zhHans,
            field: "language",
            recognize: { AppLanguage(rawValue: $0) },
            unknownEnumFields: &unknownEnumFields
        )
        let resourceMode = decodeUserFacingEnum(
            ResourceMode.self,
            from: container,
            forKey: .resourceMode,
            fallback: .background5Minutes,
            field: "resourceMode",
            recognize: ResourceMode.value(forPersistedRawValue:),
            unknownEnumFields: &unknownEnumFields
        )
        let launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        _ = try container.decodeIfPresent(Bool.self, forKey: .simplifiedRelayConfig)
        let showOfficialAccountEmailInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showOfficialAccountEmailInMenuBar) ?? false
        let claudeStatusBarDisplaySlotID = try container.decodeIfPresent(CodexSlotID.self, forKey: .claudeStatusBarDisplaySlotID)
        let providerPayload = try container.decodeIfPresent(LossyProviderDescriptorArray.self, forKey: .providers)
        let decodedProviders = providerPayload?.values ?? AppConfig.default.providers
        let statusBarProviderID = try container.decodeIfPresent(String.self, forKey: .statusBarProviderID)
        let statusBarMultiUsageEnabled = try container.decodeIfPresent(Bool.self, forKey: .statusBarMultiUsageEnabled) ?? false
        let decodedMultiProviderIDs = try container.decodeIfPresent([String].self, forKey: .statusBarMultiProviderIDs)
        let statusBarAppearanceMode = decodeUserFacingEnum(
            StatusBarAppearanceMode.self,
            from: container,
            forKey: .statusBarAppearanceMode,
            fallback: .followWallpaper,
            field: "statusBarAppearanceMode",
            recognize: { StatusBarAppearanceMode(rawValue: $0) },
            unknownEnumFields: &unknownEnumFields
        )
        let statusBarDisplayStyle = decodeUserFacingEnum(
            StatusBarDisplayStyle.self,
            from: container,
            forKey: .statusBarDisplayStyle,
            fallback: .iconPercent,
            field: "statusBarDisplayStyle",
            recognize: { StatusBarDisplayStyle(rawValue: $0) },
            unknownEnumFields: &unknownEnumFields
        )
        if let providerEnumFields = providerPayload?.unknownEnumFields {
            unknownEnumFields.append(contentsOf: providerEnumFields)
        }

        let config = AppConfig(
            schemaVersion: schemaVersion,
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
                droppedProviderEntryCount: providerPayload?.droppedEntryCount ?? 0,
                unknownEnumFields: unknownEnumFields
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
