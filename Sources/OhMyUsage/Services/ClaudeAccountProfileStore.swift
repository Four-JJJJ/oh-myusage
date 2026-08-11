import OhMyUsageDomain
import CryptoKit
import Foundation
import OhMyUsageProviders

enum ClaudeAccountProfileError: LocalizedError {
    case invalidCredentialsJSON
    case missingAccessToken
    case missingConfigDirectory
    case missingCredentialsFile(String)
    case missingStoredCredentials

    var errorDescription: String? {
        switch self {
        case .invalidCredentialsJSON:
            return "Invalid Claude credentials JSON"
        case .missingAccessToken:
            return "Claude credentials JSON is missing access token"
        case .missingConfigDirectory:
            return "Claude config directory is required"
        case .missingCredentialsFile(let path):
            return "Unable to read Claude credentials at \(path)"
        case .missingStoredCredentials:
            return "No stored Claude credentials"
        }
    }
}

struct ClaudeParsedCredentialsPayload {
    var accessToken: String
    var refreshToken: String?
    var expiresAtMs: Double?
    var subscriptionType: String?
    var scopes: [String]
    var accountId: String?
    var accountEmail: String?
    var credentialFingerprint: String
}

struct ClaudeAutoCaptureCompactionResult {
    var profiles: [ClaudeAccountProfile]
    var removedSlotIDs: [CodexSlotID]
    var didCompact: Bool
}

final class ClaudeAccountProfileStore {
    private struct ProfileFile: Codable {
        var profiles: [ClaudeAccountProfile]
        var ignoredFingerprints: [String]?
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("OhMyUsage", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("claude_profiles.json")
        }
    }

    func profiles() -> [ClaudeAccountProfile] {
        load().sorted { $0.slotID < $1.slotID }
    }

    func profile(slotID: CodexSlotID) -> ClaudeAccountProfile? {
        load().first(where: { $0.slotID == slotID })
    }

    func matchingProfile(credentialsJSON: String) -> ClaudeAccountProfile? {
        let trimmed = credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsedPayload = try? Self.parseCredentialsJSON(trimmed) else {
            return nil
        }
        let items = load()
        guard let index = Self.matchingIndex(for: parsedPayload, in: items) else {
            return nil
        }
        return items[index]
    }

    func nextAvailableSlotID() -> CodexSlotID {
        let existing = Set(load().map(\.slotID))
        return CodexSlotID.nextAvailable(excluding: existing)
    }

    @discardableResult
    func saveProfile(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?,
        currentFingerprint: String?
    ) throws -> ClaudeAccountProfile {
        let resolvedConfigDir = Self.normalizedConfigDirectory(configDir)
        let resolvedCredentialsJSON = try Self.resolveCredentialsJSON(
            source: source,
            configDir: resolvedConfigDir,
            credentialsJSON: credentialsJSON
        )
        let payload = Self.applyingAccountEmailFallback(
            try Self.parseCredentialsJSON(resolvedCredentialsJSON),
            configDir: resolvedConfigDir
        )

        var items = load()
        var ignoredFingerprints = loadIgnoredFingerprints()
        ignoredFingerprints.remove(payload.credentialFingerprint.lowercased())

        var profile = ClaudeAccountProfile(
            slotID: slotID,
            displayName: Self.fallbackDisplayName(displayName, slotID: slotID),
            note: Self.normalizedNote(note),
            source: source,
            configDir: resolvedConfigDir,
            credentialsJSON: source == .manualCredentials ? resolvedCredentialsJSON : resolvedCredentialsJSON,
            accountId: payload.accountId,
            accountEmail: payload.accountEmail,
            credentialFingerprint: payload.credentialFingerprint,
            lastImportedAt: Date(),
            isCurrentSystemAccount: payload.credentialFingerprint.lowercased() == currentFingerprint?.lowercased()
        )
        profile = normalizedProfile(profile)

        if let matched = Self.matchingIndex(for: payload, in: items),
           items[matched].slotID != slotID {
            items.remove(at: matched)
        }

        if let existing = items.firstIndex(where: { $0.slotID == slotID }) {
            profile.lastImportedAt = Date()
            items[existing] = profile
        } else {
            items.append(profile)
        }

        try save(items, ignoredFingerprints: ignoredFingerprints)
        return profile
    }

    @discardableResult
    func updateProfileMetadataIfCredentialInputsUnchanged(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?
    ) throws -> ClaudeAccountProfile? {
        let resolvedConfigDir = Self.normalizedConfigDirectory(configDir)
        var items = load()
        guard let existingIndex = items.firstIndex(where: { $0.slotID == slotID }) else {
            return nil
        }

        let existingProfile = items[existingIndex]
        guard Self.credentialInputsUnchanged(
            profile: existingProfile,
            source: source,
            configDir: resolvedConfigDir,
            credentialsJSON: credentialsJSON
        ) else {
            return nil
        }

        var updatedProfile = existingProfile
        updatedProfile.displayName = Self.fallbackDisplayName(displayName, slotID: slotID)
        updatedProfile.note = Self.normalizedNote(note)
        updatedProfile = normalizedProfile(updatedProfile)
        guard updatedProfile != existingProfile else {
            return updatedProfile
        }

        items[existingIndex] = updatedProfile
        try save(items, ignoredFingerprints: loadIgnoredFingerprints())
        return updatedProfile
    }

    @discardableResult
    func updateStoredCredentials(slotID: CodexSlotID, credentialsJSON: String) -> ClaudeAccountProfile? {
        let trimmed = credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsedPayload = try? Self.parseCredentialsJSON(trimmed) else { return nil }

        var items = load()
        guard let index = items.firstIndex(where: { $0.slotID == slotID }) else { return nil }
        var profile = items[index]
        let payload = Self.applyingAccountEmailFallback(parsedPayload, configDir: profile.configDir)
        profile.credentialsJSON = trimmed
        profile.accountId = payload.accountId
        profile.accountEmail = payload.accountEmail
        profile.credentialFingerprint = payload.credentialFingerprint
        profile.lastImportedAt = Date()
        profile = normalizedProfile(profile)
        items[index] = profile
        try? save(items, ignoredFingerprints: loadIgnoredFingerprints())
        return profile
    }

    @discardableResult
    func removeProfile(slotID: CodexSlotID) -> [ClaudeAccountProfile] {
        var items = load()
        var ignoredFingerprints = loadIgnoredFingerprints()
        if let removed = items.first(where: { $0.slotID == slotID })?.credentialFingerprint?.lowercased(),
           !removed.isEmpty {
            ignoredFingerprints.insert(removed)
        }
        items.removeAll { $0.slotID == slotID }
        try? save(items, ignoredFingerprints: ignoredFingerprints)
        return items.sorted { $0.slotID < $1.slotID }
    }

    @discardableResult
    func updateCurrentFingerprint(_ fingerprint: String?) -> [ClaudeAccountProfile] {
        var items = load()
        let normalizedCurrentFingerprint = Self.normalizedFingerprint(fingerprint)
        let changed = applyCurrentFingerprint(normalizedCurrentFingerprint, to: &items)
        if changed {
            try? save(items, ignoredFingerprints: loadIgnoredFingerprints())
        }
        return items.sorted { $0.slotID < $1.slotID }
    }

    @discardableResult
    func compactAutoCapturedProfiles(
        defaultConfigDir: String?,
        currentFingerprint: String?
    ) -> ClaudeAutoCaptureCompactionResult {
        var items = load()
        let ignoredFingerprints = loadIgnoredFingerprints()
        let normalizedDefaultConfigDir = Self.normalizedConfigDirectory(defaultConfigDir)
        let normalizedCurrentFingerprint = Self.normalizedFingerprint(currentFingerprint)

        var groupedIndices: [String: [Int]] = [:]
        groupedIndices.reserveCapacity(items.count)
        for (index, profile) in items.enumerated() {
            guard let key = Self.autoCaptureMergeKey(
                for: profile,
                defaultConfigDir: normalizedDefaultConfigDir
            ) else {
                continue
            }
            groupedIndices[key, default: []].append(index)
        }

        var removeIndices: Set<Int> = []
        var removedSlotIDs: [CodexSlotID] = []
        for indices in groupedIndices.values where indices.count > 1 {
            guard let keepIndex = Self.preferredCompactionIndex(
                from: indices,
                profiles: items,
                currentFingerprint: normalizedCurrentFingerprint
            ) else {
                continue
            }
            for index in indices where index != keepIndex {
                removeIndices.insert(index)
                removedSlotIDs.append(items[index].slotID)
            }
        }

        if !removeIndices.isEmpty {
            for index in removeIndices.sorted(by: >) {
                items.remove(at: index)
            }
        }

        let currentChanged = applyCurrentFingerprint(normalizedCurrentFingerprint, to: &items)
        let didCompact = !removeIndices.isEmpty || currentChanged
        if didCompact {
            try? save(items, ignoredFingerprints: ignoredFingerprints)
        }

        return ClaudeAutoCaptureCompactionResult(
            profiles: items.sorted { $0.slotID < $1.slotID },
            removedSlotIDs: removedSlotIDs.sorted(),
            didCompact: didCompact
        )
    }

    @discardableResult
    func captureCurrentCredentialsIfNeeded(
        credentialsJSON: String?,
        defaultConfigDir: String?,
        preferredAutoSlots: [CodexSlotID] = [.a, .b]
    ) -> [ClaudeAccountProfile] {
        guard let credentialsJSON else {
            return updateCurrentFingerprint(nil)
        }

        let trimmed = credentialsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedConfigDir = Self.normalizedConfigDirectory(defaultConfigDir) ?? Self.defaultClaudeConfigDirectory()
        guard !trimmed.isEmpty,
              let parsedPayload = try? Self.parseCredentialsJSON(trimmed) else {
            return updateCurrentFingerprint(nil)
        }
        let payload = Self.applyingAccountEmailFallback(parsedPayload, configDir: normalizedConfigDir)

        var items = load()
        let currentFingerprint = Self.normalizedFingerprint(payload.credentialFingerprint)
        let ignoredFingerprints = loadIgnoredFingerprints()
        if let currentFingerprint, ignoredFingerprints.contains(currentFingerprint) {
            let changed = applyCurrentFingerprint(currentFingerprint, to: &items)
            if changed {
                try? save(items, ignoredFingerprints: ignoredFingerprints)
            }
            return items.sorted { $0.slotID < $1.slotID }
        }

        if let existing = Self.autoCaptureMatchingIndex(
            for: payload,
            defaultConfigDir: normalizedConfigDir,
            in: items
        ) {
            var profile = items[existing]
            let normalizedPayloadAccountID = Self.normalizedAccountID(payload.accountId)
            let normalizedPayloadEmail = Self.normalizedEmail(payload.accountEmail)
            let normalizedPayloadFingerprint = Self.normalizedFingerprint(payload.credentialFingerprint)
            let normalizedProfileAccountID = Self.normalizedAccountID(profile.accountId)
            let normalizedProfileEmail = Self.normalizedEmail(profile.accountEmail)
            let normalizedProfileFingerprint = Self.normalizedFingerprint(profile.credentialFingerprint)
            let normalizedProfileCredentials = profile.credentialsJSON?.trimmingCharacters(in: .whitespacesAndNewlines)
            var profileChanged = false

            if profile.source != .configDir {
                profile.source = .configDir
                profileChanged = true
            }
            if profile.source == .configDir {
                let currentConfigDir = Self.normalizedConfigDirectory(profile.configDir)
                if currentConfigDir != normalizedConfigDir {
                    profile.configDir = normalizedConfigDir
                    profileChanged = true
                }
            }

            if normalizedProfileCredentials != trimmed {
                profile.credentialsJSON = trimmed
                profileChanged = true
            }
            if normalizedProfileAccountID != normalizedPayloadAccountID {
                profile.accountId = payload.accountId
                profileChanged = true
            }
            if normalizedProfileEmail != normalizedPayloadEmail {
                profile.accountEmail = payload.accountEmail
                profileChanged = true
            }
            if normalizedProfileFingerprint != normalizedPayloadFingerprint {
                profile.credentialFingerprint = payload.credentialFingerprint
                profileChanged = true
            }
            if profileChanged {
                profile.lastImportedAt = Date()
            }

            profile = normalizedProfile(profile)
            if items[existing] != profile {
                items[existing] = profile
                profileChanged = true
            }

            let currentChanged = applyCurrentFingerprint(currentFingerprint, to: &items)
            if profileChanged || currentChanged {
                try? save(items, ignoredFingerprints: ignoredFingerprints)
            }
            return items.sorted { $0.slotID < $1.slotID }
        }

        let occupied = Set(items.map(\.slotID))
        let slotID = preferredAutoSlots.first(where: { !occupied.contains($0) })
            ?? CodexSlotID.nextAvailable(excluding: occupied)

        items.append(
            ClaudeAccountProfile(
                slotID: slotID,
                displayName: "Claude \(slotID.rawValue)",
                note: nil,
                source: .configDir,
                configDir: normalizedConfigDir,
                credentialsJSON: trimmed,
                accountId: payload.accountId,
                accountEmail: payload.accountEmail,
                credentialFingerprint: payload.credentialFingerprint,
                lastImportedAt: Date(),
                isCurrentSystemAccount: true
            )
        )
        _ = applyCurrentFingerprint(currentFingerprint, to: &items)
        try? save(items, ignoredFingerprints: ignoredFingerprints)
        return items.sorted { $0.slotID < $1.slotID }
    }

    func reset() {
        try? fileManager.removeItem(at: fileURL)
    }

    func resolvedCredentialsJSON(for profile: ClaudeAccountProfile) throws -> String {
        try Self.resolvedCredentialsJSON(for: profile)
    }

    static func resolvedCredentialsJSON(for profile: ClaudeAccountProfile) throws -> String {
        let normalizedConfigDir = normalizedConfigDirectory(profile.configDir)
        let cached = profile.credentialsJSON?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch profile.source {
        case .configDir:
            if let normalizedConfigDir,
               let fromDirectory = try? loadCredentialsJSON(fromConfigDirectory: normalizedConfigDir) {
                return fromDirectory
            }
            if let cached, !cached.isEmpty {
                return cached
            }
            throw ClaudeAccountProfileError.missingStoredCredentials
        case .manualCredentials:
            if let cached, !cached.isEmpty {
                return cached
            }
            if let normalizedConfigDir,
               let fromDirectory = try? loadCredentialsJSON(fromConfigDirectory: normalizedConfigDir) {
                return fromDirectory
            }
            throw ClaudeAccountProfileError.missingStoredCredentials
        }
    }

    static func parseCredentialsJSON(_ raw: String) throws -> ClaudeParsedCredentialsPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAccountProfileError.invalidCredentialsJSON
        }

        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
        guard let accessToken = OfficialValueParser.string(
            oauth["accessToken"] ?? oauth["access_token"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !accessToken.isEmpty else {
            throw ClaudeAccountProfileError.missingAccessToken
        }

        let refreshToken = OfficialValueParser.string(
            oauth["refreshToken"] ?? oauth["refresh_token"]
        )
        let expiresAtMs = OfficialValueParser.double(oauth["expiresAt"] ?? oauth["expires_at"])
        let subscriptionType = OfficialValueParser.string(oauth["subscriptionType"] ?? oauth["subscription_type"])
        let scopes = (oauth["scopes"] as? [String]) ?? []
        let accountId = OfficialValueParser.string(
            json["accountId"] ?? json["account_id"] ?? oauth["accountId"] ?? oauth["account_id"]
        )
        let accountEmail = Self.extractAccountEmail(from: json, oauth: oauth)
        let fingerprint = credentialFingerprint(for: accessToken)
            ?? credentialFingerprint(for: trimmed)
            ?? UUID().uuidString

        return ClaudeParsedCredentialsPayload(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtMs: expiresAtMs,
            subscriptionType: subscriptionType,
            scopes: scopes,
            accountId: accountId,
            accountEmail: accountEmail,
            credentialFingerprint: fingerprint
        )
    }

    static func credentialFingerprint(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedConfigDirectory(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let standard = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
        return standard
    }

    static func defaultClaudeConfigDirectory() -> String {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .path
    }

    static func credentialsFilePath(configDirectory: String) -> String {
        URL(fileURLWithPath: configDirectory, isDirectory: true)
            .appendingPathComponent(".credentials.json")
            .path
    }

    static func claudeConfigFilePath(configDirectory: String) -> String {
        URL(fileURLWithPath: configDirectory, isDirectory: true)
            .appendingPathComponent("claude.json")
            .path
    }

    static func loadCredentialsJSON(fromConfigDirectory configDirectory: String) throws -> String {
        let normalizedConfigDir = normalizedConfigDirectory(configDirectory)
        guard let normalizedConfigDir else {
            throw ClaudeAccountProfileError.missingConfigDirectory
        }
        let path = credentialsFilePath(configDirectory: normalizedConfigDir)
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else {
            throw ClaudeAccountProfileError.missingCredentialsFile(path)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClaudeAccountProfileError.missingCredentialsFile(path)
        }
        return trimmed
    }

    static func loadClaudeConfigJSON(fromConfigDirectory configDirectory: String) -> [String: Any]? {
        guard let normalizedConfigDir = normalizedConfigDirectory(configDirectory) else {
            return nil
        }
        let path = claudeConfigFilePath(configDirectory: normalizedConfigDir)
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return root
    }

    static func matchingIndex(
        for snapshot: UsageSnapshot,
        in profiles: [ClaudeAccountProfile]
    ) -> Int? {
        if let explicitSlot = ClaudeAccountSlotStore.explicitSlotID(from: snapshot),
           let index = profiles.firstIndex(where: { $0.slotID == explicitSlot }) {
            return index
        }

        let fingerprint = normalizedFingerprint(snapshot.rawMeta["claude.credentialFingerprint"])
        if let fingerprint {
            return profiles.firstIndex(where: { normalizedFingerprint($0.credentialFingerprint) == fingerprint })
        }

        let email = normalizedEmail(snapshot.accountLabel ?? snapshot.rawMeta["claude.accountLabel"])
        if let email,
           let index = profiles.firstIndex(where: { normalizedEmail($0.accountEmail) == email }) {
            return index
        }

        return nil
    }

    static func supportsQuotaMonitoring(_ payload: ClaudeParsedCredentialsPayload) -> Bool {
        payload.scopes.isEmpty || payload.scopes.contains("user:profile")
    }

    static func supportsQuotaMonitoring(credentialsJSON: String) -> Bool {
        guard let payload = try? parseCredentialsJSON(credentialsJSON) else {
            return false
        }
        return supportsQuotaMonitoring(payload)
    }

    static func supportsQuotaMonitoring(profile: ClaudeAccountProfile) -> Bool {
        if let credentialsJSON = profile.credentialsJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
           !credentialsJSON.isEmpty {
            return supportsQuotaMonitoring(credentialsJSON: credentialsJSON)
        }
        guard let credentialsJSON = try? resolvedCredentialsJSON(for: profile) else {
            return false
        }
        return supportsQuotaMonitoring(credentialsJSON: credentialsJSON)
    }

    private static func resolveCredentialsJSON(
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?
    ) throws -> String {
        let trimmedCredentials = credentialsJSON?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source {
        case .configDir:
            guard let configDir else {
                throw ClaudeAccountProfileError.missingConfigDirectory
            }
            return try loadCredentialsJSON(fromConfigDirectory: configDir)
        case .manualCredentials:
            if let trimmedCredentials, !trimmedCredentials.isEmpty {
                return trimmedCredentials
            }
            if let configDir {
                return try loadCredentialsJSON(fromConfigDirectory: configDir)
            }
            throw ClaudeAccountProfileError.missingStoredCredentials
        }
    }

    private static func applyingAccountEmailFallback(
        _ payload: ClaudeParsedCredentialsPayload,
        configDir: String?
    ) -> ClaudeParsedCredentialsPayload {
        if normalizedEmail(payload.accountEmail) != nil {
            return payload
        }
        guard let email = accountEmailFromClaudeConfig(configDir: configDir) else {
            return payload
        }
        var updated = payload
        updated.accountEmail = email
        return updated
    }

    private static func extractAccountEmail(from json: [String: Any], oauth: [String: Any]) -> String? {
        if let email = OfficialValueParser.string(json["email"]) {
            return email
        }
        if let user = json["user"] as? [String: Any],
           let email = OfficialValueParser.string(user["email"]) {
            return email
        }
        if let account = json["account"] as? [String: Any],
           let email = OfficialValueParser.string(account["email"]) {
            return email
        }
        if let oauthEmail = OfficialValueParser.string(oauth["email"]) {
            return oauthEmail
        }
        return nil
    }

    private static func accountEmailFromClaudeConfig(configDir: String?) -> String? {
        guard let configDir = normalizedConfigDirectory(configDir),
              let root = loadClaudeConfigJSON(fromConfigDirectory: configDir) else {
            return nil
        }
        return extractAccountEmail(fromClaudeConfigRoot: root)
    }

    private static func extractAccountEmail(fromClaudeConfigRoot root: [String: Any]) -> String? {
        let directPaths: [Any?] = [
            root["email"],
            (root["user"] as? [String: Any])?["email"],
            (root["account"] as? [String: Any])?["email"],
            (root["profile"] as? [String: Any])?["email"],
            (root["auth"] as? [String: Any])?["email"],
            (root["claudeAiOauth"] as? [String: Any])?["email"],
            ((root["claudeAiOauth"] as? [String: Any])?["user"] as? [String: Any])?["email"]
        ]
        for candidate in directPaths {
            if let email = normalizedEmailCandidate(candidate) {
                return email
            }
        }
        return firstEmailCandidate(in: root)
    }

    private static func firstEmailCandidate(in value: Any) -> String? {
        if let email = normalizedEmailCandidate(value) {
            return email
        }
        if let dict = value as? [String: Any] {
            for (key, candidate) in dict where key.caseInsensitiveCompare("email") == .orderedSame {
                if let email = normalizedEmailCandidate(candidate) {
                    return email
                }
            }
            for (key, candidate) in dict where key.localizedCaseInsensitiveContains("email") {
                if let email = normalizedEmailCandidate(candidate) {
                    return email
                }
            }
            for candidate in dict.values {
                if let email = firstEmailCandidate(in: candidate) {
                    return email
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            for item in array {
                if let email = firstEmailCandidate(in: item) {
                    return email
                }
            }
        }
        return nil
    }

    private static func normalizedEmailCandidate(_ value: Any?) -> String? {
        guard let raw = OfficialValueParser.string(value) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"),
              !trimmed.contains(" "),
              !trimmed.contains("\n"),
              !trimmed.contains("\t") else {
            return nil
        }
        return trimmed
    }

    private static func fallbackDisplayName(_ displayName: String, slotID: CodexSlotID) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Claude \(slotID.rawValue)" : trimmed
    }

    private static func normalizedNote(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func credentialInputsUnchanged(
        profile: ClaudeAccountProfile,
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?
    ) -> Bool {
        guard profile.source == source else {
            return false
        }
        guard normalizedConfigDirectory(profile.configDir) == normalizedConfigDirectory(configDir) else {
            return false
        }

        switch source {
        case .configDir:
            return true
        case .manualCredentials:
            return normalizedCredentialsJSON(profile.credentialsJSON) == normalizedCredentialsJSON(credentialsJSON)
        }
    }

    private static func normalizedCredentialsJSON(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizedFingerprint(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private static func normalizedAccountID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private static func matchingIndex(
        for payload: ClaudeParsedCredentialsPayload,
        in profiles: [ClaudeAccountProfile]
    ) -> Int? {
        if let fingerprint = normalizedFingerprint(payload.credentialFingerprint) {
            return profiles.firstIndex(where: { normalizedFingerprint($0.credentialFingerprint) == fingerprint })
        }

        if let email = normalizedEmail(payload.accountEmail),
           let index = profiles.firstIndex(where: { normalizedEmail($0.accountEmail) == email }) {
            return index
        }

        return nil
    }

    private static func autoCaptureMatchingIndex(
        for payload: ClaudeParsedCredentialsPayload,
        defaultConfigDir: String?,
        in profiles: [ClaudeAccountProfile]
    ) -> Int? {
        if let accountID = normalizedAccountID(payload.accountId) {
            let candidates = profiles.indices.filter { index in
                normalizedAccountID(profiles[index].accountId) == accountID
            }
            if let preferred = preferredAutoCaptureIndex(from: candidates, profiles: profiles) {
                return preferred
            }
        }

        if let email = normalizedEmail(payload.accountEmail) {
            let normalizedConfigDir = normalizedConfigDirectory(defaultConfigDir)
            let exactConfigCandidates = profiles.indices.filter { index in
                guard normalizedEmail(profiles[index].accountEmail) == email else {
                    return false
                }
                return normalizedConfigDirectory(profiles[index].configDir) == normalizedConfigDir
            }
            if let preferred = preferredAutoCaptureIndex(from: exactConfigCandidates, profiles: profiles) {
                return preferred
            }

            let emailCandidates = profiles.indices.filter { index in
                normalizedEmail(profiles[index].accountEmail) == email
            }
            if emailCandidates.count == 1 {
                return emailCandidates[0]
            }
        }

        if let fingerprint = normalizedFingerprint(payload.credentialFingerprint) {
            let candidates = profiles.indices.filter { index in
                normalizedFingerprint(profiles[index].credentialFingerprint) == fingerprint
            }
            if let preferred = preferredAutoCaptureIndex(from: candidates, profiles: profiles) {
                return preferred
            }
        }

        return nil
    }

    private static func preferredAutoCaptureIndex(
        from candidates: [Int],
        profiles: [ClaudeAccountProfile]
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        return candidates.sorted { lhs, rhs in
            let left = profiles[lhs]
            let right = profiles[rhs]
            if left.source != right.source {
                return left.source == .configDir
            }
            if left.lastImportedAt != right.lastImportedAt {
                return left.lastImportedAt > right.lastImportedAt
            }
            return left.slotID < right.slotID
        }
        .first
    }

    private static func autoCaptureMergeKey(
        for profile: ClaudeAccountProfile,
        defaultConfigDir: String?
    ) -> String? {
        guard profile.source == .configDir else {
            return nil
        }
        if let accountID = normalizedAccountID(profile.accountId) {
            return "account:\(accountID)"
        }
        guard let email = normalizedEmail(profile.accountEmail) else {
            return nil
        }
        let normalizedConfig = normalizedConfigDirectory(profile.configDir)
            ?? normalizedConfigDirectory(defaultConfigDir)
            ?? "default"
        return "email:\(email)|config:\(normalizedConfig)"
    }

    private static func preferredCompactionIndex(
        from indices: [Int],
        profiles: [ClaudeAccountProfile],
        currentFingerprint: String?
    ) -> Int? {
        guard !indices.isEmpty else { return nil }
        let normalizedCurrentFingerprint = normalizedFingerprint(currentFingerprint)
        let currentCandidates: [Int]
        if let normalizedCurrentFingerprint {
            currentCandidates = indices.filter { index in
                normalizedFingerprint(profiles[index].credentialFingerprint) == normalizedCurrentFingerprint
            }
        } else {
            currentCandidates = []
        }
        let effectiveCandidates = currentCandidates.isEmpty ? indices : currentCandidates
        return effectiveCandidates.sorted { lhs, rhs in
            let left = profiles[lhs]
            let right = profiles[rhs]
            if left.lastImportedAt != right.lastImportedAt {
                return left.lastImportedAt > right.lastImportedAt
            }
            return left.slotID < right.slotID
        }
        .first
    }

    private func applyCurrentFingerprint(_ fingerprint: String?, to items: inout [ClaudeAccountProfile]) -> Bool {
        let normalizedCurrentFingerprint = Self.normalizedFingerprint(fingerprint)
        var changed = false
        for index in items.indices {
            let isCurrent = Self.normalizedFingerprint(items[index].credentialFingerprint) == normalizedCurrentFingerprint
                && normalizedCurrentFingerprint != nil
            if items[index].isCurrentSystemAccount != isCurrent {
                items[index].isCurrentSystemAccount = isCurrent
                changed = true
            }
        }
        return changed
    }

    private func normalizedProfile(_ profile: ClaudeAccountProfile) -> ClaudeAccountProfile {
        var updated = profile
        updated.configDir = Self.normalizedConfigDirectory(updated.configDir)
        updated.displayName = Self.fallbackDisplayName(updated.displayName, slotID: updated.slotID)
        updated.note = Self.normalizedNote(updated.note)
        let needsParsedPayload = updated.accountId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            || updated.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            || updated.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        if let credentialsJSON = updated.credentialsJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
           !credentialsJSON.isEmpty,
           needsParsedPayload,
           let parsedPayload = try? Self.parseCredentialsJSON(credentialsJSON) {
            let payload = Self.applyingAccountEmailFallback(parsedPayload, configDir: updated.configDir)
            if updated.accountId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                updated.accountId = payload.accountId
            }
            if updated.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                updated.accountEmail = payload.accountEmail
            }
            if updated.credentialFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                updated.credentialFingerprint = payload.credentialFingerprint
            }
        }
        return updated
    }

    private func load() -> [ClaudeAccountProfile] {
        loadFile().profiles.map { normalizedProfile($0) }
    }

    private func loadIgnoredFingerprints() -> Set<String> {
        Set(loadFile().ignoredFingerprints?.map { $0.lowercased() } ?? [])
    }

    private func loadFile() -> ProfileFile {
        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fileURL) else {
            return ProfileFile(profiles: [], ignoredFingerprints: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(ProfileFile.self, from: data) {
            return decoded
        }
        return ProfileFile(profiles: [], ignoredFingerprints: [])
    }

    private func save(_ profiles: [ClaudeAccountProfile], ignoredFingerprints: Set<String> = []) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(
            ProfileFile(
                profiles: profiles,
                ignoredFingerprints: ignoredFingerprints.isEmpty ? nil : ignoredFingerprints.sorted()
            )
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
