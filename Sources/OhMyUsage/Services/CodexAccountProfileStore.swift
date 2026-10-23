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

final class CodexAccountProfileStore: @unchecked Sendable {
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
    private let protectedFile: PrivateProfileFile
    /// OAuth vault holding the authoritative per-slot token JSON. When nil
    /// (test/recovery probes) the store keeps its legacy behavior: tokens stay
    /// in the profile file untouched.
    private let oauthVault: OfficialOAuthVaultStore?
    /// Official refreshes re-sync profile state on the main actor every cycle,
    /// so JSON encoding and file IO live on this serial queue; MainActor callers
    /// only touch the in-memory mirror and enqueue writes.
    private let ioQueue = DispatchQueue(label: "OhMyUsage.codexProfileStore.io", qos: .utility)
    /// Guards the in-memory profile mirror (read-modify-write atomicity). Never
    /// held while the IO queue executes a write.
    private let stateLock = NSLock()
    /// In-memory mirror of the persisted `ProfileFile`, always normalized.
    /// In vault mode the in-memory copy keeps the resolved token so existing
    /// callers (switch/refresh/UI) work unchanged; only the encoded disk
    /// payload strips tokens.
    private var cachedProfiles: [CodexAccountProfile]
    private var cachedIgnoredFingerprints: Set<String>
    /// stateLock-guarded: slots whose in-memory token is confirmed persisted in
    /// the OAuth vault. Only these slots strip the token from the profile file.
    private var vaultSyncedSlots: Set<CodexSlotID> = []
    /// IO-queue confined: the last payload successfully written to disk. Saves
    /// whose encoded content matches it are skipped entirely.
    private var lastWrittenData: Data?

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        oauthVault: OfficialOAuthVaultStore? = nil
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = PrivateProfileFile.defaultURL(name: "codex_profiles.json", fileManager: fileManager)
        }
        self.protectedFile = PrivateProfileFile(url: self.fileURL, fileManager: fileManager, ownsParentDirectory: fileURL == nil)
        self.oauthVault = oauthVault
        do { try protectedFile.protectExistingFile() }
        catch { NSLog("[CodexAccountProfileStore] Unable to restrict profile file permissions") }
        self.cachedProfiles = []
        self.cachedIgnoredFingerprints = []
        // One-time cold-start read, serialized on the IO queue so every disk
        // access for this store is queue-confined. In vault mode this also runs
        // the lossless token migration: file tokens move into the vault first
        // and the file is only rewritten (without tokens) after the vault write
        // succeeded. The loaded state seeds the dedupe fingerprint so a no-op
        // first save never rewrites the file.
        ioQueue.sync {
            let file = self.loadFileOnIOQueue()
            var normalized = Self.normalizeProfiles(file.profiles)
            let ignoredFingerprints = Set(file.ignoredFingerprints?.map { $0.lowercased() } ?? [])
            var syncedSlots: Set<CodexSlotID> = []
            var strippedAnyToken = false
            if let vault = oauthVault {
                for index in normalized.indices {
                    let slotID = normalized[index].slotID
                    let trimmed = normalized[index].authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        // Legacy inline token: copy it into the vault first. The
                        // file keeps the plaintext copy until that write is
                        // confirmed, so a failed write only delays migration to
                        // the next launch — it can never lose the credential.
                        if vault.saveProfileOAuthJSON(provider: .codex, slotID: slotID, rawJSON: trimmed) {
                            syncedSlots.insert(slotID)
                            strippedAnyToken = true
                        }
                    } else {
                        // Metadata-only profile: the vault is the token
                        // authority; resolve the in-memory copy for callers.
                        if let resolved = Self.resolveVaultToken(
                            vault: vault,
                            slotID: slotID,
                            fingerprint: normalized[index].credentialFingerprint
                        ) {
                            normalized[index].authJSON = resolved
                            syncedSlots.insert(slotID)
                        } else {
                            normalized[index].authJSON = ""
                        }
                    }
                }
            }
            self.cachedProfiles = normalized
            self.cachedIgnoredFingerprints = ignoredFingerprints
            self.vaultSyncedSlots = syncedSlots
            let persistedData = Self.encodedData(
                profiles: Self.strippingVaultTokens(normalized, slots: syncedSlots),
                ignoredFingerprints: ignoredFingerprints
            )
            if strippedAnyToken, let persistedData {
                // The vault now holds these tokens, so the file must not keep
                // plaintext copies until the next unrelated commit rewrites it.
                do { try protectedFile.write(persistedData) }
                catch { NSLog("[CodexAccountProfileStore] Failed to strip migrated tokens: \(error.localizedDescription)") }
            }
            self.lastWrittenData = persistedData
        }
    }

    func profiles() -> [CodexAccountProfile] {
        stateLock.lock()
        let current = cachedProfiles
        stateLock.unlock()
        return current.sorted { $0.slotID < $1.slotID }
    }

    func profile(slotID: CodexSlotID) -> CodexAccountProfile? {
        stateLock.lock()
        let matched = cachedProfiles.first(where: { $0.slotID == slotID })
        stateLock.unlock()
        return matched
    }

    func matchingProfile(authJSON: String) -> CodexAccountProfile? {
        let trimmed = authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let payload = try? Self.parseAuthJSON(trimmed) else {
            return nil
        }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let index = Self.matchingIndex(for: payload, in: cachedProfiles) else {
            return nil
        }
        return cachedProfiles[index]
    }

    @discardableResult
    func saveProfile(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        authJSON: String,
        currentFingerprint: String?
    ) throws -> CodexAccountProfile {
        let payload = try Self.parseAuthJSON(authJSON)
        var profile = try Self.makeProfile(slotID: slotID, displayName: displayName, note: note, authJSON: authJSON)
        profile.isCurrentSystemAccount = profile.credentialFingerprint == currentFingerprint
        profile = Self.normalizedProfile(profile, payload: payload)

        stateLock.lock()
        defer { stateLock.unlock() }
        var items = cachedProfiles
        var ignoredFingerprints = cachedIgnoredFingerprints

        if let matchedIndex = Self.matchingIndex(for: payload, in: items),
           items[matchedIndex].slotID != slotID {
            items.remove(at: matchedIndex)
        }
        ignoredFingerprints.remove(payload.credentialFingerprint.lowercased())

        if let existing = items.firstIndex(where: { $0.slotID == slotID }) {
            items[existing] = profile
        } else {
            items.append(profile)
        }
        syncVaultTokenLocked(
            slotID: slotID,
            previousToken: cachedProfiles.first(where: { $0.slotID == slotID })?.authJSON,
            newToken: profile.authJSON
        )
        commitLocked(items: items, ignoredFingerprints: ignoredFingerprints)
        return profile
    }

    @discardableResult
    func updateCurrentFingerprint(_ fingerprint: String?) -> [CodexAccountProfile] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return updateCurrentProfilesLocked(cachedProfiles, currentIdentityKey: nil, currentFingerprint: fingerprint)
    }

    @discardableResult
    func updateStoredAuthJSON(slotID: CodexSlotID, authJSON: String) -> CodexAccountProfile? {
        let trimmed = authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let payload = try? Self.parseAuthJSON(trimmed) else { return nil }

        stateLock.lock()
        defer { stateLock.unlock() }
        guard let index = cachedProfiles.firstIndex(where: { $0.slotID == slotID }) else { return nil }
        var items = cachedProfiles
        var profile = items[index]
        let previousToken = profile.authJSON
        profile.authJSON = trimmed
        profile.accountId = payload.accountId
        profile.accountEmail = payload.accountEmail
        profile.accountSubject = payload.accountSubject
        profile.credentialFingerprint = payload.credentialFingerprint
        profile.lastImportedAt = Date()
        profile = Self.normalizedProfile(profile, payload: payload)
        items[index] = profile
        syncVaultTokenLocked(slotID: slotID, previousToken: previousToken, newToken: trimmed)
        commitLocked(items: items, ignoredFingerprints: cachedIgnoredFingerprints)
        return profile
    }

    func nextAvailableSlotID() -> CodexSlotID {
        stateLock.lock()
        let existing = Set(cachedProfiles.map(\.slotID))
        stateLock.unlock()
        return CodexSlotID.nextAvailable(excluding: existing)
    }

    @discardableResult
    func removeProfile(slotID: CodexSlotID) -> [CodexAccountProfile] {
        stateLock.lock()
        defer { stateLock.unlock() }
        var items = cachedProfiles
        var ignoredFingerprints = cachedIgnoredFingerprints
        if let removed = items.first(where: { $0.slotID == slotID })?.credentialFingerprint?.lowercased(),
           !removed.isEmpty {
            ignoredFingerprints.insert(removed)
        }
        items.removeAll { $0.slotID == slotID }
        // The vault slot entry is intentionally kept: dropping a profile must
        // never destroy the only remaining copy of the credential.
        vaultSyncedSlots.remove(slotID)
        commitLocked(items: items, ignoredFingerprints: ignoredFingerprints)
        return items.sorted { $0.slotID < $1.slotID }
    }

    func reset() {
        stateLock.lock()
        cachedProfiles = []
        cachedIgnoredFingerprints = []
        vaultSyncedSlots = []
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.fileURL)
            self.lastWrittenData = nil
        }
        stateLock.unlock()
    }

    /// Order fence for save-then-load semantics across store instances: blocks
    /// until every enqueued write/removal has completed on the IO queue.
    func flushPendingDiskWrites() {
        ioQueue.sync {}
    }

    @discardableResult
    func captureCurrentAuthIfNeeded(
        authJSON: String?,
        preferredAutoSlots: [CodexSlotID] = [.a, .b]
    ) -> [CodexAccountProfile] {
        stateLock.lock()
        defer { stateLock.unlock() }

        let existingProfiles = cachedProfiles
        guard let authJSON else {
            return updateCurrentProfilesLocked(existingProfiles, currentIdentityKey: nil, currentFingerprint: nil)
        }

        let trimmed = authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let payload = try? Self.parseAuthJSON(trimmed) else {
            return updateCurrentProfilesLocked(existingProfiles, currentIdentityKey: nil, currentFingerprint: nil)
        }

        var items = existingProfiles
        let currentFingerprint = payload.credentialFingerprint.lowercased()
        let currentIdentityKey = CodexIdentity.from(payload: payload).identityKey
        let ignoredFingerprints = cachedIgnoredFingerprints

        if ignoredFingerprints.contains(currentFingerprint) {
            return updateCurrentProfilesLocked(
                items,
                currentIdentityKey: currentIdentityKey,
                currentFingerprint: currentFingerprint
            )
        }

        if let existing = Self.matchingIndex(for: payload, in: items) {
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
            syncVaultTokenLocked(slotID: previous.slotID, previousToken: previous.authJSON, newToken: trimmed)
            return updateCurrentProfilesLocked(
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
        syncVaultTokenLocked(slotID: slotID, previousToken: nil, newToken: trimmed)

        return updateCurrentProfilesLocked(
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

    /// Must be called with `stateLock` held. Updates the in-memory mirror and
    /// enqueues the encode + write on the IO queue; enqueue order matches
    /// mutation order, and content-identical payloads are dropped there. In
    /// vault mode the encoded payload strips tokens for slots confirmed in the
    /// vault (the in-memory mirror keeps the resolved token for callers).
    private func commitLocked(items: [CodexAccountProfile], ignoredFingerprints: Set<String>) {
        cachedProfiles = items
        cachedIgnoredFingerprints = ignoredFingerprints
        let stripSlots = oauthVault != nil ? vaultSyncedSlots : []
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.writeIfNeeded(Self.encodedData(
                profiles: Self.strippingVaultTokens(items, slots: stripSlots),
                ignoredFingerprints: ignoredFingerprints
            ))
        }
    }

    /// Must be called with `stateLock` held. Persists the slot token into the
    /// vault; on success the slot is marked safe to strip from the file. When
    /// there is no vault, or the write fails, the slot is unmarked so the file
    /// keeps the token (never both stores empty) and migration retries later.
    /// Unchanged tokens on already-synced slots skip the keychain entirely.
    private func syncVaultTokenLocked(slotID: CodexSlotID, previousToken: String?, newToken: String) {
        guard let oauthVault else { return }
        let trimmedNew = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty else {
            vaultSyncedSlots.remove(slotID)
            return
        }
        if vaultSyncedSlots.contains(slotID),
           previousToken?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedNew {
            return
        }
        if oauthVault.saveProfileOAuthJSON(provider: .codex, slotID: slotID, rawJSON: trimmedNew) {
            vaultSyncedSlots.insert(slotID)
        } else {
            vaultSyncedSlots.remove(slotID)
        }
    }

    /// Resolves the in-memory token for a metadata-only profile: the per-slot
    /// vault entry, or — as a self-healing fallback for a cleared slot entry —
    /// the provider-wide vault entry when its fingerprint matches the profile.
    private static func resolveVaultToken(
        vault: OfficialOAuthVaultStore,
        slotID: CodexSlotID,
        fingerprint: String?
    ) -> String? {
        if let slotJSON = vault.readProfileOAuthJSON(provider: .codex, slotID: slotID) {
            return slotJSON
        }
        guard let fingerprint = CodexIdentity.normalizedFingerprint(fingerprint),
              let currentJSON = vault.readOAuthJSON(provider: .codex),
              let payload = try? Self.parseAuthJSON(currentJSON),
              CodexIdentity.normalizedFingerprint(payload.credentialFingerprint) == fingerprint else {
            return nil
        }
        // Fingerprint match means this profile IS the current system account;
        // backfill the per-slot entry from the provider-wide copy.
        _ = vault.saveProfileOAuthJSON(provider: .codex, slotID: slotID, rawJSON: currentJSON)
        return currentJSON
    }

    /// Returns copies with the token replaced by an empty placeholder for slots
    /// whose token is confirmed persisted in the vault; the encoded profile file
    /// keeps metadata only. Slots without a confirmed vault copy keep their
    /// token so a failed vault write can never leave both stores empty.
    private static func strippingVaultTokens(
        _ profiles: [CodexAccountProfile],
        slots: Set<CodexSlotID>
    ) -> [CodexAccountProfile] {
        guard !slots.isEmpty else { return profiles }
        return profiles.map { profile in
            guard slots.contains(profile.slotID), !profile.authJSON.isEmpty else { return profile }
            var stripped = profile
            stripped.authJSON = ""
            return stripped
        }
    }

    /// IO-queue confined. Skips the write when the payload matches the last
    /// successfully persisted one, so refresh cycles that leave the profile
    /// file unchanged never touch the disk.
    private func writeIfNeeded(_ data: Data?) {
        guard let data, data != lastWrittenData else { return }
        do {
            try protectedFile.write(data)
            lastWrittenData = data
        } catch {
            NSLog("[CodexAccountProfileStore] Failed to persist profiles: \(error.localizedDescription)")
        }
    }

    /// IO-queue confined (cold start).
    private func loadFileOnIOQueue() -> ProfileFile {
        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
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

    private static func encodedData(profiles: [CodexAccountProfile], ignoredFingerprints: Set<String>) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(
            ProfileFile(
                profiles: profiles,
                ignoredFingerprints: ignoredFingerprints.isEmpty ? nil : ignoredFingerprints.sorted()
            )
        )
    }

    private static func normalizeProfiles(_ profiles: [CodexAccountProfile]) -> [CodexAccountProfile] {
        profiles.map { normalizedProfile($0, payload: nil) }
    }

    private static func normalizedProfile(
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

    private static func matchingIndex(
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

    /// Must be called with `stateLock` held. Recomputes `isCurrentSystemAccount`
    /// flags against the given identity and persists only when something
    /// actually changed (same-content saves never reach the disk).
    private func updateCurrentProfilesLocked(
        _ profiles: [CodexAccountProfile],
        currentIdentityKey: String?,
        currentFingerprint: String?
    ) -> [CodexAccountProfile] {
        var items = Self.normalizeProfiles(profiles)
        let ignoredFingerprints = cachedIgnoredFingerprints
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
        if changed || items != cachedProfiles {
            commitLocked(items: items, ignoredFingerprints: ignoredFingerprints)
        }
        return items.sorted { $0.slotID < $1.slotID }
    }
}
