import Foundation
import OhMyUsageProviders

final class BrowserStorageCredentialReader {
    private struct BearerTokenCandidate {
        let token: String
        let exp: TimeInterval?
        let score: Int
    }

    private struct ExpiringPathCacheEntry {
        let paths: [String]
        let expiresAt: Date
    }

    private static let defaultBrowserOrder: [KimiBrowserKind] = [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]

    private let fileManager: FileManager
    private let browserOrder: [KimiBrowserKind]
    private let storagePathCacheTTL: TimeInterval
    private let now: () -> Date
    private let storagePathEnumerator: ((KimiBrowserKind) -> [String])?
    private let storagePathCacheLock = NSLock()
    private var bearerStoragePathCache: [KimiBrowserKind: ExpiringPathCacheEntry] = [:]

    init(
        fileManager: FileManager = .default,
        browserOrder: [KimiBrowserKind] = BrowserStorageCredentialReader.defaultBrowserOrder,
        storagePathCacheTTL: TimeInterval = 60,
        now: @escaping () -> Date = Date.init,
        storagePathEnumerator: ((KimiBrowserKind) -> [String])? = nil
    ) {
        self.fileManager = fileManager
        self.browserOrder = browserOrder
        self.storagePathCacheTTL = max(0, storagePathCacheTTL)
        self.now = now
        self.storagePathEnumerator = storagePathEnumerator
    }

    func bearerTokenCandidates(
        host: String,
        order: [KimiBrowserKind]? = nil,
        refreshPaths: Bool = false
    ) -> [BrowserDetectedCredential] {
        let actualOrder = order ?? browserOrder
        var candidates: [(token: String, source: String, exp: TimeInterval?, score: Int)] = []
        for browser in actualOrder {
            let source = "\(browserLabel(browser)):localStorage"
            for path in candidateBearerStoragePaths(for: browser, bypassCache: refreshPaths) {
                let perPath = bearerTokenCandidatesFromStorage(path: path, host: host)
                for candidate in perPath {
                    candidates.append((
                        token: candidate.token,
                        source: source,
                        exp: candidate.exp,
                        score: candidate.score
                    ))
                }
            }
        }
        return sortedUniqueCredentials(candidates)
    }

    func bearerTokenCandidates(
        for browser: KimiBrowserKind,
        hostCandidates: [String],
        source: String,
        refreshPaths: Bool = false
    ) -> [BrowserDetectedCredential] {
        var candidates: [(token: String, source: String, exp: TimeInterval?, score: Int)] = []
        let paths = candidateBearerStoragePaths(for: browser, bypassCache: refreshPaths)
        for path in paths {
            for host in hostCandidates {
                let perPath = bearerTokenCandidatesFromStorage(path: path, host: host)
                for candidate in perPath {
                    candidates.append((
                        token: candidate.token,
                        source: source,
                        exp: candidate.exp,
                        score: candidate.score
                    ))
                }
            }
        }
        return sortedUniqueCredentials(candidates)
    }

    func bearerTokenCandidates(
        storagePaths: [String],
        host: String,
        source: String
    ) -> [BrowserDetectedCredential] {
        var candidates: [(token: String, source: String, exp: TimeInterval?, score: Int)] = []
        for path in storagePaths {
            let perPath = bearerTokenCandidatesFromStorage(path: path, host: host)
            for candidate in perPath {
                candidates.append((
                    token: candidate.token,
                    source: source,
                    exp: candidate.exp,
                    score: candidate.score
                ))
            }
        }
        return sortedUniqueCredentials(candidates)
    }

    private func candidateLocalStoragePaths(for browser: KimiBrowserKind) -> [String] {
        guard let base = browserUserDataPath(for: browser) else { return [] }

        var result: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                guard url.lastPathComponent == "leveldb",
                      url.path.contains("/Local Storage/") else { continue }
                result.append(url.path)
            }
        }
        return Array(Set(result)).sorted()
    }

    private func candidateSessionStoragePaths(for browser: KimiBrowserKind) -> [String] {
        guard let base = browserUserDataPath(for: browser) else { return [] }

        var result: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                guard url.lastPathComponent == "Session Storage" else { continue }
                result.append(url.path)
            }
        }
        return Array(Set(result)).sorted()
    }

    private func candidateIndexedDBPaths(for browser: KimiBrowserKind) -> [String] {
        guard let base = browserUserDataPath(for: browser) else { return [] }

        var result: [String] = []
        let baseURL = URL(fileURLWithPath: base)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                guard url.path.hasSuffix(".indexeddb.leveldb") else { continue }
                result.append(url.path)
            }
        }
        return Array(Set(result)).sorted()
    }

    private func candidateBearerStoragePaths(for browser: KimiBrowserKind, bypassCache: Bool = false) -> [String] {
        guard storagePathCacheTTL > 0 else {
            return enumerateCandidateBearerStoragePaths(for: browser)
        }

        let currentDate = now()
        if !bypassCache, let cached = cachedBearerStoragePaths(for: browser, now: currentDate) {
            return cached
        }

        let paths = enumerateCandidateBearerStoragePaths(for: browser)
        cacheBearerStoragePaths(paths, for: browser, now: currentDate)
        return paths
    }

    private func enumerateCandidateBearerStoragePaths(for browser: KimiBrowserKind) -> [String] {
        if let storagePathEnumerator {
            return Array(Set(storagePathEnumerator(browser))).sorted()
        }

        let merged = candidateLocalStoragePaths(for: browser)
            + candidateSessionStoragePaths(for: browser)
            + candidateIndexedDBPaths(for: browser)
        return Array(Set(merged)).sorted()
    }

    private func cachedBearerStoragePaths(for browser: KimiBrowserKind, now: Date) -> [String]? {
        storagePathCacheLock.lock()
        defer { storagePathCacheLock.unlock() }
        purgeExpiredStoragePathCacheLocked(now: now)
        return bearerStoragePathCache[browser]?.paths
    }

    private func cacheBearerStoragePaths(_ paths: [String], for browser: KimiBrowserKind, now: Date) {
        storagePathCacheLock.lock()
        bearerStoragePathCache[browser] = ExpiringPathCacheEntry(
            paths: paths,
            expiresAt: now.addingTimeInterval(storagePathCacheTTL)
        )
        purgeExpiredStoragePathCacheLocked(now: now)
        storagePathCacheLock.unlock()
    }

    private func purgeExpiredStoragePathCacheLocked(now: Date) {
        bearerStoragePathCache = bearerStoragePathCache.filter { _, entry in
            entry.expiresAt > now
        }
    }

    private func browserUserDataPath(for browser: KimiBrowserKind) -> String? {
        let home = NSHomeDirectory()
        switch browser {
        case .arc:
            return "\(home)/Library/Application Support/Arc/User Data"
        case .chrome:
            return "\(home)/Library/Application Support/Google/Chrome"
        case .edge:
            return "\(home)/Library/Application Support/Microsoft Edge"
        case .brave:
            return "\(home)/Library/Application Support/BraveSoftware/Brave-Browser"
        case .chromium:
            return "\(home)/Library/Application Support/Chromium"
        case .opera:
            return "\(home)/Library/Application Support/com.operasoftware.Opera"
        case .operaGX:
            return "\(home)/Library/Application Support/com.operasoftware.OperaGX"
        case .vivaldi:
            return "\(home)/Library/Application Support/Vivaldi"
        case .firefox:
            return nil
        case .safari:
            return nil
        }
    }

    private func bearerTokenCandidatesFromStorage(path: String, host: String) -> [BearerTokenCandidate] {
        guard fileManager.fileExists(atPath: path) else { return [] }
        guard let files = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }

        let normalizedHost = host.lowercased()
        let hostMarkers = [
            "_https://\(normalizedHost)",
            "_http://\(normalizedHost)",
            normalizedHost,
        ]
        let keyHints = ["auth_token", "access_token", "token", "jwt", "id_token", "authorization", "hongmacode_token"]
        let jwtRegex = try? NSRegularExpression(pattern: #"([A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,})"#)
        let skRegex = try? NSRegularExpression(pattern: #"(sk-[A-Za-z0-9][A-Za-z0-9_-]{8,})"#)
        let keyedTokenRegex = try? NSRegularExpression(
            pattern: #"(?i)(hongmacode_token|auth_token|access_token|id_token|refresh_token|token|authorization)[^A-Za-z0-9]{0,24}(?:bearer\s+)?([A-Za-z0-9._\-+/=]{16,})"#
        )
        var candidates: [BearerTokenCandidate] = []

        for name in files where name.hasSuffix(".log") || name.hasSuffix(".ldb") || name.hasPrefix("MANIFEST-") {
            let filePath = path + "/" + name
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath), options: [.mappedIfSafe]),
                  let text = String(data: data, encoding: .isoLatin1) else {
                continue
            }
            let lowered = text.lowercased()
            let hostMatchedByPath = path.lowercased().contains(normalizedHost)
            let hostMatchedByMarker = hostMarkers.contains(where: { lowered.contains($0) })
            let hostMatchedBySiteKey: Bool
            if normalizedHost == "hongmacc.com" {
                hostMatchedBySiteKey = lowered.contains("hongmacode_token")
            } else {
                hostMatchedBySiteKey = false
            }
            let hostMatched = hostMatchedByPath || hostMatchedByMarker || hostMatchedBySiteKey
            guard hostMatched else { continue }

            let ns = text as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            let jwtMatches = jwtRegex?.matches(in: text, options: [], range: fullRange) ?? []
            for match in jwtMatches where match.numberOfRanges > 1 {
                appendCandidate(
                    token: ns.substring(with: match.range(at: 1)),
                    around: match.range(at: 1),
                    nsText: ns,
                    normalizedHost: normalizedHost,
                    requiresNearbyHost: !hostMatchedByPath && !hostMatchedBySiteKey,
                    keyHints: keyHints,
                    candidates: &candidates
                )
            }

            let skMatches = skRegex?.matches(in: text, options: [], range: fullRange) ?? []
            for match in skMatches where match.numberOfRanges > 1 {
                appendCandidate(
                    token: ns.substring(with: match.range(at: 1)),
                    around: match.range(at: 1),
                    nsText: ns,
                    normalizedHost: normalizedHost,
                    requiresNearbyHost: !hostMatchedByPath && !hostMatchedBySiteKey,
                    keyHints: keyHints,
                    candidates: &candidates
                )
            }

            let keyedMatches = keyedTokenRegex?.matches(in: text, options: [], range: fullRange) ?? []
            for match in keyedMatches where match.numberOfRanges > 2 {
                appendCandidate(
                    token: ns.substring(with: match.range(at: 2)),
                    around: match.range(at: 2),
                    nsText: ns,
                    normalizedHost: normalizedHost,
                    requiresNearbyHost: !hostMatchedByPath && !hostMatchedBySiteKey,
                    keyHints: keyHints,
                    candidates: &candidates
                )
            }
        }

        var unique: [String: BearerTokenCandidate] = [:]
        for candidate in candidates {
            if let current = unique[candidate.token] {
                if candidate.score > current.score {
                    unique[candidate.token] = candidate
                }
            } else {
                unique[candidate.token] = candidate
            }
        }

        return Array(unique.values)
    }

    private func appendCandidate(
        token rawToken: String,
        around range: NSRange,
        nsText: NSString,
        normalizedHost: String,
        requiresNearbyHost: Bool,
        keyHints: [String],
        candidates: inout [BearerTokenCandidate]
    ) {
        var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bearer ") || token.hasPrefix("bearer ") {
            token = String(token.dropFirst(7))
        }
        if let decoded = token.removingPercentEncoding, !decoded.isEmpty {
            token = decoded
        }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`;,)}]"))
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`{(["))
        guard token.count >= 16 else { return }
        guard token.range(of: #"^[A-Za-z0-9._-]{16,}$"#, options: .regularExpression) != nil else { return }
        if token.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil {
            return
        }
        let looksJWT = token.split(separator: ".").count >= 3
        let looksSK = token.lowercased().hasPrefix("sk-")
        let looksLongOpaque = token.count >= 80
        guard looksJWT || looksSK || looksLongOpaque else { return }

        let windowStart = max(0, range.location - 260)
        let windowLen = min(nsText.length - windowStart, range.length + 520)
        let window = nsText.substring(with: NSRange(location: windowStart, length: windowLen)).lowercased()
        guard !requiresNearbyHost || window.contains(normalizedHost) else { return }

        var score = 0
        if window.contains(normalizedHost) { score += 4 }
        if keyHints.contains(where: { window.contains($0) }) { score += 6 }
        if window.contains("bearer") { score += 2 }
        if looksSK { score += 8 }
        if looksJWT { score += 4 }
        if token.count >= 64 { score += 2 }

        let exp = jwtExpiration(token)
        if let exp {
            if exp > Date().timeIntervalSince1970 {
                score += 8
            } else {
                score -= 4
            }
        }

        guard score >= 6 else { return }
        candidates.append(BearerTokenCandidate(token: token, exp: exp, score: score))
    }

    private func sortedUniqueCredentials(
        _ candidates: [(token: String, source: String, exp: TimeInterval?, score: Int)]
    ) -> [BrowserDetectedCredential] {
        let sorted = candidates.sorted { lhs, rhs in
            let lhsExp = lhs.exp ?? -1
            let rhsExp = rhs.exp ?? -1
            if lhsExp != rhsExp { return lhsExp > rhsExp }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.token.count > rhs.token.count
        }
        var seen = Set<String>()
        var output: [BrowserDetectedCredential] = []
        for candidate in sorted {
            if seen.insert(candidate.token).inserted {
                output.append(BrowserDetectedCredential(value: candidate.token, source: candidate.source))
            }
        }
        return output
    }

    private func jwtExpiration(_ token: String) -> TimeInterval? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = json["exp"] as? NSNumber else {
            return nil
        }
        return exp.doubleValue
    }

    private func browserLabel(_ browser: KimiBrowserKind) -> String {
        switch browser {
        case .arc:
            return "auto:Arc"
        case .chrome:
            return "auto:Chrome"
        case .safari:
            return "auto:Safari"
        case .edge:
            return "auto:Edge"
        case .brave:
            return "auto:Brave"
        case .chromium:
            return "auto:Chromium"
        case .firefox:
            return "auto:Firefox"
        case .opera:
            return "auto:Opera"
        case .operaGX:
            return "auto:OperaGX"
        case .vivaldi:
            return "auto:Vivaldi"
        }
    }
}
