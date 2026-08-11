import OhMyUsageDomain
import CryptoKit
import Foundation
import OhMyUsageProviders

enum CodexAccountProfileError: LocalizedError {
    case invalidJSON
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid auth.json content"
        case .missingAccessToken:
            return "auth.json is missing access_token"
        }
    }
}

struct CodexParsedAuthPayload {
    var accessToken: String
    var refreshToken: String?
    var accountId: String?
    var idToken: String?
    var accountEmail: String?
    var accountSubject: String?
    var tenantKey: String?
    var identityKey: String?
    var credentialFingerprint: String
}

final class CodexAccountProfileStore {
    private struct ProfileFile: Codable {
        var profiles: [CodexAccountProfile]
        var ignoredFingerprints: [String]?
    }

    private struct MatchingProbe {
        var explicitSlotID: CodexSlotID?
        var identityKey: String?
        var accountID: String?
        var subject: String?
        var email: String?
        var fingerprint: String?

        var principal: String? {
            subject ?? email
        }
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
            self.fileURL = directory.appendingPathComponent("codex_profiles.json")
        }
    }

    func profiles() -> [CodexAccountProfile] {
        load().sorted { $0.slotID < $1.slotID }
    }

    func profile(slotID: CodexSlotID) -> CodexAccountProfile? {
        load().first(where: { $0.slotID == slotID })
    }

    func matchingProfile(authJSON: String) -> CodexAccountProfile? {
        let trimmed = authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let payload = try? Self.parseAuthJSON(trimmed) else {
            return nil
        }
        let items = load()
        guard let index = matchingIndex(for: payload, in: items) else {
            return nil
        }
        return items[index]
    }

    @discardableResult
    func saveProfile(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        authJSON: String,
        currentFingerprint: String?
    ) throws -> CodexAccountProfile {
        var items = load()
        let payload = try Self.parseAuthJSON(authJSON)
        var profile = try Self.makeProfile(slotID: slotID, displayName: displayName, note: note, authJSON: authJSON)
        profile.isCurrentSystemAccount = profile.credentialFingerprint == currentFingerprint
        profile = normalizedProfile(profile, payload: payload)
        var ignoredFingerprints = loadIgnoredFingerprints()

        if let matchedIndex = matchingIndex(for: payload, in: items),
           items[matchedIndex].slotID != slotID {
            items.remove(at: matchedIndex)
        }
        ignoredFingerprints.remove(payload.credentialFingerprint.lowercased())

        if let existing = items.firstIndex(where: { $0.slotID == slotID }) {
            items[existing] = profile
        } else {
            items.append(profile)
        }
        try save(items, ignoredFingerprints: ignoredFingerprints)
        return profile
    }

    @discardableResult
    func updateCurrentFingerprint(_ fingerprint: String?) -> [CodexAccountProfile] {
        updateCurrentProfiles(load(), currentIdentityKey: nil, currentFingerprint: fingerprint)
    }

    @discardableResult
    func updateStoredAuthJSON(slotID: CodexSlotID, authJSON: String) -> CodexAccountProfile? {
        let trimmed = authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let payload = try? Self.parseAuthJSON(trimmed) else { return nil }

        var items = load()
        guard let index = items.firstIndex(where: { $0.slotID == slotID }) else { return nil }
        var profile = items[index]
        profile.authJSON = trimmed
        profile.accountId = payload.accountId
        profile.accountEmail = payload.accountEmail
        profile.accountSubject = payload.accountSubject
        profile.credentialFingerprint = payload.credentialFingerprint
        profile.lastImportedAt = Date()
        profile = normalizedProfile(profile, payload: payload)
        items[index] = profile
        try? save(items, ignoredFingerprints: loadIgnoredFingerprints())
        return profile
    }

    func nextAvailableSlotID() -> CodexSlotID {
        let existing = Set(load().map(\.slotID))
        return CodexSlotID.nextAvailable(excluding: existing)
    }

    @discardableResult
    func removeProfile(slotID: CodexSlotID) -> [CodexAccountProfile] {
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

    func reset() {
        try? fileManager.removeItem(at: fileURL)
    }

    @discardableResult
    func captureCurrentAuthIfNeeded(
        authJSON: String?,
        preferredAutoSlots: [CodexSlotID] = [.a, .b]
    ) -> [CodexAccountProfile] {
        let existingProfiles = load()
        guard let authJSON else {
            return updateCurrentProfiles(existingProfiles, currentIdentityKey: nil, currentFingerprint: nil)
        }

        let trimmed = authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let payload = try? Self.parseAuthJSON(trimmed) else {
            return updateCurrentProfiles(existingProfiles, currentIdentityKey: nil, currentFingerprint: nil)
        }

        var items = existingProfiles
        let currentFingerprint = payload.credentialFingerprint.lowercased()
        let currentIdentityKey = CodexIdentity.from(payload: payload).identityKey
        let ignoredFingerprints = loadIgnoredFingerprints()

        if ignoredFingerprints.contains(currentFingerprint) {
            return updateCurrentProfiles(
                items,
                currentIdentityKey: currentIdentityKey,
                currentFingerprint: currentFingerprint
            )
        }

        if let existing = matchingIndex(for: payload, in: items) {
            let previous = items[existing]
            var updated = previous
            updated.authJSON = trimmed
            updated.accountId = payload.accountId
            updated.accountEmail = payload.accountEmail
            updated.accountSubject = payload.accountSubject
            updated.credentialFingerprint = payload.credentialFingerprint
            let identity = CodexIdentity.from(payload: payload)
            updated.tenantKey = identity.tenantKey
            updated.identityKey = identity.identityKey
            if previous.authJSON.trimmingCharacters(in: .whitespacesAndNewlines) != trimmed
                || previous.accountId != payload.accountId
                || previous.accountEmail != payload.accountEmail
                || previous.accountSubject != payload.accountSubject
                || previous.tenantKey != identity.tenantKey
                || previous.identityKey?.lowercased() != identity.identityKey
                || previous.credentialFingerprint?.lowercased() != currentFingerprint {
                updated.lastImportedAt = Date()
            }
            items[existing] = updated
            return updateCurrentProfiles(
                items,
                currentIdentityKey: currentIdentityKey,
                currentFingerprint: currentFingerprint
            )
        }

        let occupied = Set(items.map(\.slotID))
        let slotID = preferredAutoSlots.first(where: { !occupied.contains($0) })
            ?? CodexSlotID.nextAvailable(excluding: occupied)
        let identity = CodexIdentity.from(payload: payload)

        items.append(
            CodexAccountProfile(
                slotID: slotID,
                displayName: "Codex \(slotID.rawValue)",
                note: nil,
                authJSON: trimmed,
                accountId: payload.accountId,
                accountEmail: payload.accountEmail,
                accountSubject: payload.accountSubject,
                tenantKey: identity.tenantKey,
                identityKey: identity.identityKey,
                credentialFingerprint: payload.credentialFingerprint,
                lastImportedAt: Date(),
                isCurrentSystemAccount: true
            )
        )

        return updateCurrentProfiles(
            items,
            currentIdentityKey: currentIdentityKey,
            currentFingerprint: currentFingerprint
        )
    }

    static func makeProfile(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        authJSON: String,
        importedAt: Date = Date()
    ) throws -> CodexAccountProfile {
        let payload = try parseAuthJSON(authJSON)
        let identity = CodexIdentity.from(payload: payload)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexAccountProfile(
            slotID: slotID,
            displayName: trimmedName.isEmpty ? "Codex \(slotID.rawValue)" : trimmedName,
            note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote,
            authJSON: authJSON.trimmingCharacters(in: .whitespacesAndNewlines),
            accountId: payload.accountId,
            accountEmail: payload.accountEmail,
            accountSubject: payload.accountSubject,
            tenantKey: identity.tenantKey,
            identityKey: identity.identityKey,
            credentialFingerprint: payload.credentialFingerprint,
            lastImportedAt: importedAt,
            isCurrentSystemAccount: false
        )
    }

    static func parseAuthJSON(_ raw: String) throws -> CodexParsedAuthPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAccountProfileError.invalidJSON
        }

        let tokens = (json["tokens"] as? [String: Any]) ?? json
        guard let accessToken = OfficialValueParser.string(tokens["access_token"] ?? tokens["accessToken"]),
              !accessToken.isEmpty else {
            throw CodexAccountProfileError.missingAccessToken
        }

        let accountId = OfficialValueParser.string(tokens["account_id"] ?? tokens["accountId"])
        let refreshToken = OfficialValueParser.string(tokens["refresh_token"] ?? tokens["refreshToken"])
        let idToken = OfficialValueParser.string(tokens["id_token"] ?? tokens["idToken"])
        let email = idToken.flatMap(JWTInspector.email)
        let subject = idToken.flatMap(JWTInspector.subject)
        let fingerprint = credentialFingerprint(for: accessToken) ?? credentialFingerprint(for: trimmed) ?? UUID().uuidString

        var payload = CodexParsedAuthPayload(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: accountId,
            idToken: idToken,
            accountEmail: email,
            accountSubject: subject,
            tenantKey: nil,
            identityKey: nil,
            credentialFingerprint: fingerprint
        )
        let identity = CodexIdentity.from(payload: payload)
        payload.tenantKey = identity.tenantKey
        payload.identityKey = identity.identityKey
        return payload
    }

    static func credentialFingerprint(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func matchingIndex(
        for snapshot: UsageSnapshot,
        in profiles: [CodexAccountProfile]
    ) -> Int? {
        matchingIndex(for: probe(from: snapshot), in: profiles)
    }

    private func load() -> [CodexAccountProfile] {
        normalizeProfiles(loadFile().profiles)
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

    private func save(_ profiles: [CodexAccountProfile], ignoredFingerprints: Set<String> = []) throws {
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

    private func normalizeProfiles(_ profiles: [CodexAccountProfile]) -> [CodexAccountProfile] {
        profiles.map { normalizedProfile($0, payload: nil) }
    }

    private func normalizedProfile(
        _ profile: CodexAccountProfile,
        payload: CodexParsedAuthPayload?
    ) -> CodexAccountProfile {
        var updated = profile
        let needsParsedPayload = CodexIdentity.trimmed(updated.accountId) == nil
            || CodexIdentity.trimmed(updated.accountEmail) == nil
            || CodexIdentity.trimmed(updated.accountSubject) == nil
            || CodexIdentity.trimmed(updated.credentialFingerprint) == nil
        let parsedPayload = payload ?? (needsParsedPayload ? (try? Self.parseAuthJSON(profile.authJSON)) : nil)
        updated.note = CodexIdentity.trimmed(updated.note)

        if CodexIdentity.trimmed(updated.accountId) == nil {
            updated.accountId = parsedPayload?.accountId
        }
        if CodexIdentity.trimmed(updated.accountEmail) == nil {
            updated.accountEmail = parsedPayload?.accountEmail
        }
        if CodexIdentity.trimmed(updated.accountSubject) == nil {
            updated.accountSubject = parsedPayload?.accountSubject
        }
        if CodexIdentity.trimmed(updated.credentialFingerprint) == nil {
            updated.credentialFingerprint = parsedPayload?.credentialFingerprint
        }

        let identity = CodexIdentity.from(profile: updated)
        updated.tenantKey = identity.tenantKey
        updated.identityKey = identity.identityKey
        return updated
    }

    private func matchingIndex(
        for payload: CodexParsedAuthPayload,
        in profiles: [CodexAccountProfile]
    ) -> Int? {
        Self.matchingIndex(for: Self.probe(from: payload), in: profiles)
    }

    private static func probe(from payload: CodexParsedAuthPayload) -> MatchingProbe {
        let identity = CodexIdentity.from(payload: payload)
        return MatchingProbe(
            explicitSlotID: nil,
            identityKey: identity.identityKey,
            accountID: CodexIdentity.normalizedAccountID(payload.accountId),
            subject: CodexIdentity.normalizedSubject(payload.accountSubject),
            email: CodexIdentity.normalizedEmail(payload.accountEmail),
            fingerprint: CodexIdentity.normalizedFingerprint(payload.credentialFingerprint)
        )
    }

    private static func probe(from snapshot: UsageSnapshot) -> MatchingProbe {
        let identity = CodexIdentity.from(snapshot: snapshot)
        return MatchingProbe(
            explicitSlotID: CodexAccountSlotStore.explicitSlotID(from: snapshot),
            identityKey: identity.identityKey,
            accountID: CodexIdentity.normalizedAccountID(CodexIdentity.teamID(from: snapshot)),
            subject: CodexIdentity.normalizedSubject(snapshot.rawMeta["codex.subject"]),
            email: CodexIdentity.normalizedEmail(snapshot.accountLabel ?? snapshot.rawMeta["codex.accountLabel"]),
            fingerprint: CodexIdentity.normalizedFingerprint(snapshot.rawMeta["codex.credentialFingerprint"])
        )
    }

    private static func profilePrincipal(_ profile: CodexAccountProfile) -> String? {
        if let subject = CodexIdentity.normalizedSubject(profile.accountSubject) {
            return subject
        }
        return CodexIdentity.normalizedEmail(profile.accountEmail)
    }

    private static func matchingIndex(
        for probe: MatchingProbe,
        in profiles: [CodexAccountProfile]
    ) -> Int? {
        if let explicitSlotID = probe.explicitSlotID,
           let index = profiles.firstIndex(where: { $0.slotID == explicitSlotID }) {
            return index
        }

        if let identityKey = CodexIdentity.normalizedIdentityKey(probe.identityKey),
           identityKey != "unknown",
           let index = profiles.firstIndex(where: {
               CodexIdentity.normalizedIdentityKey($0.identityKey ?? CodexIdentity.from(profile: $0).identityKey) == identityKey
           }) {
            return index
        }

        if let accountID = probe.accountID,
           let principal = probe.principal,
           let index = profiles.firstIndex(where: {
               CodexIdentity.normalizedAccountID($0.accountId) == accountID && profilePrincipal($0) == principal
           }) {
            return index
        }

        if let accountID = probe.accountID, probe.principal == nil {
            let noPrincipalCandidates = profiles.indices.filter { index in
                CodexIdentity.normalizedAccountID(profiles[index].accountId) == accountID
                    && profilePrincipal(profiles[index]) == nil
            }
            if noPrincipalCandidates.count == 1 {
                return noPrincipalCandidates[0]
            }
        }

        if let principal = probe.principal,
           let index = profiles.firstIndex(where: {
               profilePrincipal($0) == principal
                   && !CodexIdentity.hasConflictingAccountID(probe.accountID, $0.accountId)
           }) {
            return index
        }

        if let fingerprint = probe.fingerprint,
           let index = profiles.firstIndex(where: {
               if let probePrincipal = probe.principal,
                  let profilePrincipal = profilePrincipal($0),
                  profilePrincipal != probePrincipal {
                   return false
               }
               return CodexIdentity.normalizedFingerprint($0.credentialFingerprint) == fingerprint
                   && !CodexIdentity.hasConflictingAccountID(probe.accountID, $0.accountId)
           }) {
            return index
        }

        return nil
    }

    private func updateCurrentProfiles(
        _ profiles: [CodexAccountProfile],
        currentIdentityKey: String?,
        currentFingerprint: String?
    ) -> [CodexAccountProfile] {
        var items = normalizeProfiles(profiles)
        let ignoredFingerprints = loadIgnoredFingerprints()
        var changed = false
        let normalizedIdentityKey = CodexIdentity.normalizedIdentityKey(currentIdentityKey)
        for index in items.indices {
            let isCurrent: Bool
            if let normalizedIdentityKey, normalizedIdentityKey != "unknown" {
                let profileIdentity = CodexIdentity.normalizedIdentityKey(
                    items[index].identityKey ?? CodexIdentity.from(profile: items[index]).identityKey
                )
                isCurrent = profileIdentity == normalizedIdentityKey
            } else {
                isCurrent = items[index].credentialFingerprint?.lowercased() == currentFingerprint && currentFingerprint != nil
            }
            if items[index].isCurrentSystemAccount != isCurrent {
                items[index].isCurrentSystemAccount = isCurrent
                changed = true
            }
        }
        if changed || items != load() {
            try? save(items, ignoredFingerprints: ignoredFingerprints)
        }
        return items.sorted { $0.slotID < $1.slotID }
    }
}
