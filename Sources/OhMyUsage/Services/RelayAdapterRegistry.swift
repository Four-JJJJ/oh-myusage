import Foundation
import OhMyUsageDomain

final class RelayAdapterRegistry: @unchecked Sendable {
    static let shared = RelayAdapterRegistry()
    typealias LocalManifestEnumerator = (_ directory: URL) -> FileManager.DirectoryEnumerator?

    private struct LocalManifestDirectoryFingerprint: Equatable {
        var paths: [String]
        var fileCount: Int
        var totalSize: UInt64
        var latestModificationTime: Date?
    }

    private struct LocalManifestCache {
        var fingerprint: LocalManifestDirectoryFingerprint
        var manifests: [RelayAdapterManifest]
        var expiresAt: Date
    }

    private let fileManager: FileManager
    private let bundledManifests: [RelayAdapterManifest]
    private let localManifestDirectoryURL: URL?
    private let localManifestCacheTTL: TimeInterval
    private let now: () -> Date
    private let localManifestEnumerator: LocalManifestEnumerator
    private let cacheLock = NSLock()
    private var localManifestCache: LocalManifestCache?

    init(
        fileManager: FileManager = .default,
        builtInManifests: [RelayAdapterManifest]? = nil,
        localManifestDirectoryURL: URL? = nil,
        localManifestCacheTTL: TimeInterval = 60,
        now: @escaping () -> Date = Date.init,
        localManifestEnumerator: LocalManifestEnumerator? = nil
    ) {
        self.fileManager = fileManager
        self.bundledManifests = builtInManifests ?? Self.loadBundledManifests()
        self.localManifestDirectoryURL = localManifestDirectoryURL
        self.localManifestCacheTTL = max(0, localManifestCacheTTL)
        self.now = now
        self.localManifestEnumerator = localManifestEnumerator ?? { [fileManager] directory in
            fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        }
    }

    func manifest(for baseURL: String, preferredID: String? = nil) -> RelayAdapterManifest {
        let all = availableManifests()
        if let preferredID,
           let matched = all.first(where: { $0.id == preferredID }) {
            return decorate(matched)
        }

        let host = URL(string: ProviderDescriptor.normalizeRelayBaseURL(baseURL))?.host?.lowercased()
        if let host,
           let matched = all
            .filter({ $0.match.hostPatterns.contains(where: { $0 != "*" }) })
            .sorted(by: Self.compareSpecificity)
            .first(where: { manifest in
                manifest.match.hostPatterns.contains(where: { Self.host(host, matches: $0) && $0 != "*" })
            }) {
            return decorate(matched)
        }

        return decorate(all.first(where: { $0.id == "generic-newapi" }) ?? Self.genericManifest)
    }

    func manifest(id: String) -> RelayAdapterManifest? {
        availableManifests().first(where: { $0.id == id }).map(decorate)
    }

    func builtInManifests() -> [RelayAdapterManifest] {
        bundledManifests
            .filter { !Self.isLegacyRelayExampleManifest($0) }
            .sorted { $0.id < $1.id }
            .map(decorate)
    }

    func availableManifests() -> [RelayAdapterManifest] {
        var merged: [String: RelayAdapterManifest] = [:]
        for manifest in bundledManifests {
            merged[manifest.id] = manifest
        }
        for manifest in loadLocalManifests() {
            merged[manifest.id] = manifest
        }
        return merged.values
            .filter { !Self.isLegacyRelayExampleManifest($0) }
            .sorted { $0.id < $1.id }
            .map(decorate)
    }

    func invalidateLocalManifestCache() {
        cacheLock.lock()
        localManifestCache = nil
        cacheLock.unlock()
    }

    static let genericNewAPIAdapterID = "generic-newapi"
    static let genericSub2APIAdapterID = "generic-sub2api"

    static func isGenericRelaySiteTemplate(_ id: String?) -> Bool {
        id == genericNewAPIAdapterID || id == genericSub2APIAdapterID
    }

    static func isGenericRelaySiteTemplate(_ manifest: RelayAdapterManifest) -> Bool {
        isGenericRelaySiteTemplate(manifest.id)
    }

    private func decorate(_ manifest: RelayAdapterManifest) -> RelayAdapterManifest {
        var copy = manifest
        switch copy.id {
        case "ailinyu":
            copy.displayMode = .hybrid
            copy.supportsBrowserFallback = true
            copy.supportsSeparateBalanceAuth = true
        case "xiaomimimo-token-plan":
            copy.displayMode = .quotaPercent
            copy.supportsBrowserFallback = true
            copy.supportsSeparateBalanceAuth = true
        case "generic-newapi", "generic-sub2api", "deepseek", "hongmacc", "xiaomimimo", "moonshot", "minimax":
            copy.displayMode = .balance
            copy.supportsBrowserFallback = true
            copy.supportsSeparateBalanceAuth = true
        default:
            break
        }

        if copy.setup?.diagnosticHints == nil {
            var setup = copy.setup ?? RelaySetupManifest()
            setup.diagnosticHints = diagnosticHints(for: copy.id)
            copy.setup = setup
        }
        return copy
    }

    private func diagnosticHints(for id: String) -> RelaySetupManifest.LocalizedText? {
        switch id {
        case "ailinyu":
            return .init(
                zhHans: "优先确认 API Key 与后台访问令牌分别填写正确；该站点可同时展示 token 配额和账户余额。",
                en: "Confirm the API key and dashboard access token separately. This site can expose both token quota and account balance."
            )
        case "xiaomimimo-token-plan":
            return .init(
                zhHans: "该模板读取 Token Plan 套餐详情与用量接口，展示套餐名称、到期时间和当前套餐用量；如果测试连接失败，优先确认浏览器里 platform.xiaomimimo.com 仍处于登录状态。",
                en: "This template reads Token Plan detail and usage endpoints to display plan name, expiration time, and current usage. If testing fails, first confirm platform.xiaomimimo.com is still logged in in your browser."
            )
        case "deepseek", "hongmacc", "xiaomimimo", "moonshot", "minimax":
            return .init(
                zhHans: "测试连接时会优先使用当前模板的默认余额接口；若站点返回结构不同，再展开高级设置覆盖路径。",
                en: "Connection testing uses the template's default balance endpoint first. Open Advanced settings only if the site returns a different shape."
            )
        case "generic-newapi":
            return .init(
                zhHans: "先尝试标准 New API 配置；只有当站点接口路径或字段不兼容时再改高级设置。",
                en: "Start with the standard New API template. Change Advanced settings only when the site uses different paths or field names."
            )
        case "generic-sub2api":
            return .init(
                zhHans: "填写站点根地址（不要带 /v1）和分组 API Key；通过 GET /v1/usage 读取钱包、配额或订阅余额。",
                en: "Enter the site root URL (without /v1) and a group API key. Balance comes from GET /v1/usage for wallet, quota, or subscription modes."
            )
        default:
            return nil
        }
    }

    private func loadLocalManifests() -> [RelayAdapterManifest] {
        let currentDate = now()
        if let cached = cachedLocalManifests(validAt: currentDate) {
            return cached
        }

        guard let directory = localManifestDirectory() else {
            storeLocalManifests(
                [],
                fingerprint: emptyLocalManifestFingerprint(),
                now: currentDate
            )
            return []
        }

        let manifestFiles = localManifestFiles(in: directory)
        let fingerprint = localManifestFingerprint(for: manifestFiles)
        if let cached = cachedLocalManifests(matching: fingerprint) {
            storeLocalManifests(cached, fingerprint: fingerprint, now: currentDate)
            return cached
        }

        let decoder = JSONDecoder()
        var manifests: [RelayAdapterManifest] = []
        for url in manifestFiles {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(RelayAdapterManifest.self, from: data) else {
                continue
            }
            manifests.append(manifest)
        }
        manifests.sort { $0.id < $1.id }
        storeLocalManifests(manifests, fingerprint: fingerprint, now: currentDate)
        return manifests
    }

    private func localManifestDirectory() -> URL? {
        if let localManifestDirectoryURL {
            return localManifestDirectoryURL
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("OhMyUsage", isDirectory: true)
            .appendingPathComponent("relay-adapters", isDirectory: true)
    }

    private func emptyLocalManifestFingerprint() -> LocalManifestDirectoryFingerprint {
        LocalManifestDirectoryFingerprint(
            paths: [],
            fileCount: 0,
            totalSize: 0,
            latestModificationTime: nil
        )
    }

    private func localManifestFiles(in directory: URL) -> [URL] {
        guard let enumerator = localManifestEnumerator(directory) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            files.append(url.standardizedFileURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    private func localManifestFingerprint(for files: [URL]) -> LocalManifestDirectoryFingerprint {
        var totalSize: UInt64 = 0
        var latestModificationTime: Date?

        for url in files {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                continue
            }
            if let fileSize = values.fileSize, fileSize > 0 {
                totalSize += UInt64(fileSize)
            }
            if let modifiedAt = values.contentModificationDate,
               latestModificationTime == nil || modifiedAt > (latestModificationTime ?? .distantPast) {
                latestModificationTime = modifiedAt
            }
        }

        return LocalManifestDirectoryFingerprint(
            paths: files.map(\.path),
            fileCount: files.count,
            totalSize: totalSize,
            latestModificationTime: latestModificationTime
        )
    }

    private func cachedLocalManifests(validAt now: Date) -> [RelayAdapterManifest]? {
        guard localManifestCacheTTL > 0 else { return nil }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let localManifestCache,
              localManifestCache.expiresAt > now else {
            return nil
        }
        return localManifestCache.manifests
    }

    private func cachedLocalManifests(
        matching fingerprint: LocalManifestDirectoryFingerprint
    ) -> [RelayAdapterManifest]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let localManifestCache,
              localManifestCache.fingerprint == fingerprint else {
            return nil
        }
        return localManifestCache.manifests
    }

    private func storeLocalManifests(
        _ manifests: [RelayAdapterManifest],
        fingerprint: LocalManifestDirectoryFingerprint,
        now: Date
    ) {
        cacheLock.lock()
        localManifestCache = LocalManifestCache(
            fingerprint: fingerprint,
            manifests: manifests,
            expiresAt: now.addingTimeInterval(localManifestCacheTTL)
        )
        cacheLock.unlock()
    }

    private static func loadBundledManifests() -> [RelayAdapterManifest] {
        let decoder = JSONDecoder()
        guard let resourceURL = Bundle.module.resourceURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) else {
            return [genericManifest]
        }

        var manifests: [RelayAdapterManifest] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(RelayAdapterManifest.self, from: data) else {
                continue
            }
            manifests.append(manifest)
        }
        manifests.sort { $0.id < $1.id }

        if !manifests.contains(where: { $0.id == genericSub2APIAdapterID }) {
            manifests.append(genericSub2APIManifest)
            manifests.sort { $0.id < $1.id }
        }

        return manifests.isEmpty ? [genericManifest] : manifests
    }

    private static func host(_ host: String, matches pattern: String) -> Bool {
        let lowered = pattern.lowercased()
        if lowered == "*" {
            return true
        }
        if lowered.hasPrefix("*.") {
            return host == String(lowered.dropFirst(2)) || host.hasSuffix(String(lowered.dropFirst(1)))
        }
        return host == lowered || host.hasSuffix(".\(lowered)")
    }

    private static func compareSpecificity(lhs: RelayAdapterManifest, rhs: RelayAdapterManifest) -> Bool {
        lhs.match.hostPatterns.map(\.count).max() ?? 0 > rhs.match.hostPatterns.map(\.count).max() ?? 0
    }

    private static func isLegacyRelayExampleManifest(_ manifest: RelayAdapterManifest) -> Bool {
        let normalizedID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDisplayName = manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDefaultDisplayName = manifest.match.defaultDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedHosts = manifest.match.hostPatterns.compactMap(Self.normalizeHostPattern)
        let hasRelayExampleHost = normalizedHosts.contains(where: Self.isRelayExampleHost)
        let hasExampleHost = normalizedHosts.contains(where: Self.isExampleHost)
        let hasRelayExampleID = normalizedID.contains("relay-example")
        let hasRelayExampleName = normalizedDisplayName.contains("relay example")
            || (normalizedDefaultDisplayName?.contains("relay example") ?? false)

        if hasRelayExampleHost {
            return true
        }

        if hasRelayExampleID || hasRelayExampleName {
            return true
        }

        return hasExampleHost && looksLikeGenericRelaySample(manifest)
    }

    private static func normalizeHostPattern(_ pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        var hostPart = trimmed
        if let parsedHost = URL(string: trimmed)?.host?.lowercased() {
            hostPart = parsedHost
        } else {
            hostPart = hostPart
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            if let slash = hostPart.firstIndex(of: "/") {
                hostPart = String(hostPart[..<slash])
            }
            if let query = hostPart.firstIndex(of: "?") {
                hostPart = String(hostPart[..<query])
            }
            if let hash = hostPart.firstIndex(of: "#") {
                hostPart = String(hostPart[..<hash])
            }
        }
        return hostPart.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isRelayExampleHost(_ hostPattern: String) -> Bool {
        let host = hostPattern.replacingOccurrences(of: "*.", with: "")
        return host == "relay.example.com" || host.hasSuffix(".relay.example.com")
    }

    private static func isExampleHost(_ hostPattern: String) -> Bool {
        let host = hostPattern.replacingOccurrences(of: "*.", with: "")
        return host == "example.com" || host.hasSuffix(".example.com")
    }

    private static func looksLikeGenericRelaySample(_ manifest: RelayAdapterManifest) -> Bool {
        let endpointPath = manifest.balanceRequest.path.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let remainingExpression = manifest.extract.remaining
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let usedExpression = manifest.extract.used?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        return endpointPath == "/api/user/self"
            && (remainingExpression.contains("quota") || usedExpression.contains("quota"))
    }

    static let genericManifest = RelayAdapterManifest(
        id: "generic-newapi",
        displayName: "Generic New API",
        match: RelayAdapterMatch(
            hostPatterns: ["*"],
            defaultDisplayName: "Generic New API",
            defaultTokenChannelEnabled: false,
            defaultBalanceChannelEnabled: true
        ),
        setup: RelaySetupManifest(
            requiredInputs: [.displayName, .baseURL, .balanceAuth, .userID],
            balanceAuthHint: .init(
                zhHans: "填写后台 Access Token，支持直接粘贴 `Bearer ...` 或纯 token。",
                en: "Enter the dashboard access token. Both `Bearer ...` and the raw token are accepted."
            ),
            userIDHint: .init(
                zhHans: "填写请求头 `New-Api-User` 对应的 userId。",
                en: "Enter the userId used for the `New-Api-User` request header."
            )
        ),
        authStrategies: [
            RelayAuthStrategy(kind: .savedBearer),
            RelayAuthStrategy(kind: .browserBearer),
            RelayAuthStrategy(kind: .savedCookieHeader),
            RelayAuthStrategy(kind: .browserCookieHeader)
        ],
        displayMode: .balance,
        supportsBrowserFallback: true,
        supportsSeparateBalanceAuth: true,
        balanceRequest: RelayRequestManifest(
            method: "GET",
            path: "/api/user/self",
            userIDHeader: "New-Api-User",
            authHeader: "Authorization",
            authScheme: "Bearer"
        ),
        tokenRequest: RelayTokenRequestManifest(),
        extract: RelayExtractManifest(
            success: "success",
            remaining: "data.quota",
            used: "data.used_quota",
            limit: "add(data.quota,data.used_quota)",
            unit: "quota",
            accountLabel: "coalesce(data.group,\"默认套餐\")"
        ),
        postprocessID: .quotaDisplayStatus
    )

    static let genericSub2APIManifest = RelayAdapterManifest(
        id: genericSub2APIAdapterID,
        displayName: "Generic Sub2API",
        match: RelayAdapterMatch(
            hostPatterns: ["*"],
            defaultDisplayName: "Generic Sub2API",
            defaultTokenChannelEnabled: false,
            defaultBalanceChannelEnabled: true
        ),
        setup: RelaySetupManifest(
            requiredInputs: [.displayName, .baseURL, .balanceAuth],
            balanceAuthHint: .init(
                zhHans: "填写 Sub2API 分组 API Key，支持直接粘贴 `Bearer sk-...` 或纯 `sk-...`。站点地址填根地址，不要带 `/v1`。",
                en: "Enter the Sub2API group API key. Both `Bearer sk-...` and the raw `sk-...` key are accepted. Use the site root URL without `/v1`."
            )
        ),
        authStrategies: [
            RelayAuthStrategy(kind: .savedBearer),
            RelayAuthStrategy(kind: .browserBearer)
        ],
        displayMode: .balance,
        supportsBrowserFallback: true,
        supportsSeparateBalanceAuth: true,
        balanceRequest: RelayRequestManifest(
            method: "GET",
            path: "/v1/usage",
            authHeader: "Authorization",
            authScheme: "Bearer"
        ),
        extract: RelayExtractManifest(
            remaining: "coalesce(quota.remaining,remaining)",
            used: "coalesce(quota.used,subscription.monthly_usage_usd)",
            limit: "coalesce(quota.limit,subscription.monthly_limit_usd)",
            unit: "coalesce(quota.unit,unit,\"USD\")",
            accountLabel: "coalesce(planName,\"Sub2API\")"
        ),
        postprocessID: .sub2apiUsage
    )
}
