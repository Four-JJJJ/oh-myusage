import Foundation
import OhMyUsageDomain

struct RelayRawTokenCandidate {
    let token: String
    let source: String
}

struct RelayCredentialCandidate {
    let headers: [String: String]
    let source: String
    let persistedCredential: String?
}

struct RelayCredentialResolver {
    let descriptor: ProviderDescriptor
    let keychain: KeychainService
    let browserCredentialService: BrowserCredentialService

    func resolveTokenCandidates(
        host: String,
        includeSavedCredentials: Bool,
        includeBrowserCredentials: Bool,
        browserAccessIntent: BrowserCredentialAccessIntent
    ) -> [RelayRawTokenCandidate] {
        var output: [RelayRawTokenCandidate] = []

        func append(token: String?, source: String) {
            guard let token else { return }
            let trimmed = normalizeBearerToken(token)
            guard !trimmed.isEmpty else { return }
            guard !isExpiredJWT(trimmed) else { return }
            if output.contains(where: { $0.token == trimmed }) {
                return
            }
            output.append(RelayRawTokenCandidate(token: trimmed, source: source))
        }

        if includeSavedCredentials,
           let service = descriptor.auth.keychainService,
           let account = descriptor.auth.keychainAccount {
            append(token: keychain.readToken(service: service, account: account), source: "saved")
        }

        if includeBrowserCredentials {
            for candidate in browserCredentialService.detectBearerTokenCandidates(
                host: host,
                accessIntent: browserAccessIntent
            ) {
                append(token: candidate.value, source: candidate.source)
            }
        }

        return output
    }

    func resolveBalanceCandidates(
        baseURL: URL,
        manifest: RelayAdapterManifest,
        relayConfig: RelayProviderConfig,
        request: ResolvedRelayRequest,
        strategies: [RelayAuthStrategy],
        includeSavedCredentials: Bool,
        includeBrowserCredentials: Bool,
        includeExpiredSentinel: Bool,
        browserAccessIntent: BrowserCredentialAccessIntent
    ) -> [RelayCredentialCandidate] {
        let host = baseURL.host?.lowercased() ?? ""
        var candidates: [RelayCredentialCandidate] = []
        let savedRaw = readSavedCredential(auth: relayConfig.balanceAuth)
        let savedBearer = savedRaw.flatMap { raw in
            looksLikeCookieHeader(raw) ? nil : normalizeBearerToken(raw)
        }
        let savedBearerExpired = savedBearer.map { isExpiredJWT($0) || isRefreshJWT($0) } ?? false

        func append(_ candidate: RelayCredentialCandidate?) {
            guard let candidate else { return }
            if candidates.contains(where: { $0.headers == candidate.headers }) {
                return
            }
            candidates.append(candidate)
        }

        for strategy in strategies {
            switch strategy.kind {
            case .savedBearer:
                guard includeSavedCredentials else { continue }
                guard savedBearerExpired == false else { continue }
                append(savedBearer.map {
                    buildHeaderCandidate(
                        request: request,
                        header: request.authHeader ?? "Authorization",
                        scheme: request.authScheme ?? "Bearer",
                        rawValue: $0,
                        source: "savedBearer",
                        persistedCredential: $0
                    )
                })
            case .browserBearer:
                guard includeBrowserCredentials else { continue }
                for detected in browserCredentialService.detectBearerTokenCandidates(
                    host: host,
                    accessIntent: browserAccessIntent
                ) {
                    let normalized = normalizeBearerToken(detected.value)
                    guard !normalized.isEmpty,
                          !isExpiredJWT(normalized),
                          !isRefreshJWT(normalized) else { continue }
                    append(buildHeaderCandidate(
                        request: request,
                        header: request.authHeader ?? "Authorization",
                        scheme: request.authScheme ?? "Bearer",
                        rawValue: normalized,
                        source: "browserBearer:\(detected.source)",
                        persistedCredential: normalized
                    ))
                }
            case .savedCookieHeader:
                guard includeSavedCredentials else { continue }
                if let savedRaw,
                   looksLikeCookieHeader(savedRaw) {
                    if manifest.id == "moonshot",
                       looksLikeMoonshotNonAuthCookieHeader(savedRaw) {
                        continue
                    }
                    append(
                        RelayCredentialCandidate(
                            headers: buildHeaders(
                                request: request,
                                authHeader: "Cookie",
                                authValue: savedRaw
                            ),
                            source: "savedCookieHeader",
                            persistedCredential: savedRaw
                        )
                    )
                }
            case .browserCookieHeader:
                guard includeBrowserCredentials else { continue }
                if let detected = browserCredentialService.detectCookieHeader(
                    host: host,
                    accessIntent: browserAccessIntent
                ) {
                    let resolvedCookie = completeBrowserCookieHeaderIfNeeded(
                        detected,
                        host: host,
                        manifest: manifest,
                        browserAccessIntent: browserAccessIntent
                    )
                    append(RelayCredentialCandidate(
                        headers: buildHeaders(
                            request: request,
                            authHeader: "Cookie",
                            authValue: resolvedCookie.value
                        ),
                        source: "browserCookieHeader:\(resolvedCookie.source)",
                        persistedCredential: resolvedCookie.value
                    ))
                }
            case .namedCookie:
                guard includeBrowserCredentials else { continue }
                let name = strategy.cookieName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { continue }
                if let detected = browserCredentialService.detectNamedCookie(
                    name: name,
                    host: host,
                    accessIntent: browserAccessIntent
                ) {
                    append(RelayCredentialCandidate(
                        headers: buildHeaders(
                            request: request,
                            authHeader: "Cookie",
                            authValue: detected.value
                        ),
                        source: "namedCookie:\(detected.source)",
                        persistedCredential: detected.value
                    ))
                }
            case .customHeader:
                guard includeSavedCredentials else { continue }
                guard savedBearerExpired == false else { continue }
                append(savedBearer.map {
                    buildHeaderCandidate(
                        request: request,
                        header: request.authHeader ?? "Authorization",
                        scheme: request.authScheme,
                        rawValue: $0,
                        source: "customHeader",
                        persistedCredential: $0
                    )
                })
            }
        }

        if candidates.isEmpty, includeExpiredSentinel, savedBearerExpired {
            candidates.append(
                RelayCredentialCandidate(
                    headers: [:],
                    source: "savedBearerExpired",
                    persistedCredential: nil
                )
            )
        }

        if includeBrowserCredentials,
           manifest.id == "deepseek",
           let cookieDetected = browserCredentialService.detectCookieHeader(
                host: host,
                accessIntent: browserAccessIntent
           ) {
            let bearerCandidates = candidates.filter { candidate in
                candidate.headers.keys.contains { $0.caseInsensitiveCompare("Authorization") == .orderedSame } &&
                candidate.headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }) == false
            }
            for candidate in bearerCandidates {
                var headers = candidate.headers
                headers["Cookie"] = cookieDetected.value
                append(
                    RelayCredentialCandidate(
                        headers: headers,
                        source: "\(candidate.source)+cookie:\(cookieDetected.source)",
                        persistedCredential: candidate.persistedCredential
                    )
                )
            }
        }

        return candidates
    }

    func persistTokenCandidate(_ token: String, auth: AuthConfig) -> Bool {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return false
        }
        return keychain.saveToken(token, service: service, account: account)
    }

    func readSavedCredential(auth: AuthConfig) -> String? {
        guard let service = auth.keychainService,
              let account = auth.keychainAccount else {
            return nil
        }
        return keychain.readToken(service: service, account: account)
    }

    func normalizeBearerToken(_ value: String) -> String {
        KimiProvider.normalizeToken(value)
    }

    func looksLikeCookieHeader(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("Bearer ") || trimmed.hasPrefix("bearer ") {
            return false
        }
        return trimmed.contains("=")
    }

    func looksLikeMoonshotNonAuthCookieHeader(_ value: String) -> Bool {
        let cookieNames = parseCookieNames(value).map { $0.lowercased() }
        guard !cookieNames.isEmpty else { return false }

        let knownNonAuthNames: Set<String> = [
            "ingresscookie",
            "_ga",
            "_gid",
            "_gat",
            "_clck",
            "_clsk",
            "_ga_z0zten03pz"
        ]
        let authIndicators = ["session", "sess", "auth", "token", "jwt", "login", "user", "uid", "moonshot", "kimi"]

        if cookieNames.contains(where: { name in
            authIndicators.contains(where: { name.contains($0) })
        }) {
            return false
        }

        return cookieNames.allSatisfy { name in
            knownNonAuthNames.contains(name) ||
            name.hasPrefix("_ga_") ||
            name.hasPrefix("_cl")
        }
    }

    func parseCookieNames(_ value: String) -> [String] {
        value
            .split(separator: ";")
            .compactMap { item in
                let pair = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pair.isEmpty,
                      let equalsIndex = pair.firstIndex(of: "=") else {
                    return nil
                }
                return String(pair[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private func completeBrowserCookieHeaderIfNeeded(
        _ detected: BrowserDetectedCredential,
        host: String,
        manifest: RelayAdapterManifest,
        browserAccessIntent: BrowserCredentialAccessIntent
    ) -> BrowserDetectedCredential {
        guard isXiaomimimoManifest(manifest),
              cookieHeaderContains(detected.value, name: "api-platform_serviceToken"),
              !cookieHeaderContains(detected.value, name: "userId"),
              host.caseInsensitiveCompare("xiaomimimo.com") != .orderedSame,
              let parentDetected = browserCredentialService.detectCookieHeader(
                host: "xiaomimimo.com",
                accessIntent: browserAccessIntent
              ) else {
            return detected
        }

        let merged = mergeCookieHeaders(primary: detected.value, fallback: parentDetected.value)
        guard cookieHeaderContains(merged, name: "api-platform_serviceToken"),
              cookieHeaderContains(merged, name: "userId") else {
            return detected
        }

        return BrowserDetectedCredential(
            value: merged,
            source: "\(detected.source)+\(parentDetected.source)"
        )
    }

    private func isXiaomimimoManifest(_ manifest: RelayAdapterManifest) -> Bool {
        manifest.id == "xiaomimimo" || manifest.id == "xiaomimimo-token-plan"
    }

    private func cookieHeaderContains(_ header: String, name: String) -> Bool {
        parseCookieNames(header).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func mergeCookieHeaders(primary: String, fallback: String) -> String {
        var output = cookiePairs(from: primary)
        var existingNames = Set(output.map { $0.name.lowercased() })

        for pair in cookiePairs(from: fallback) where !existingNames.contains(pair.name.lowercased()) {
            output.append(pair)
            existingNames.insert(pair.name.lowercased())
        }

        return output.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private func cookiePairs(from header: String) -> [(name: String, value: String)] {
        header
            .split(separator: ";")
            .compactMap { item in
                let pair = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pair.isEmpty,
                      let equalsIndex = pair.firstIndex(of: "=") else {
                    return nil
                }
                let name = String(pair[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = pair.index(after: equalsIndex)
                let value = String(pair[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return (name: name, value: value)
            }
    }

    func isExpiredJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        guard let payloadData = KimiJWT.decodeBase64URL(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              payload["exp"] != nil else {
            return false
        }
        return KimiJWT.isExpired(token)
    }

    func isRefreshJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = decodeBase64URL(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return false
        }
        let tokenType = (payload["typ"] as? String)
            ?? (payload["token_type"] as? String)
            ?? (payload["tokenType"] as? String)
        return tokenType?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("refresh") == .orderedSame
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized)
    }

    func buildHeaderCandidate(
        request: ResolvedRelayRequest,
        header: String,
        scheme: String?,
        rawValue: String,
        source: String,
        persistedCredential: String?
    ) -> RelayCredentialCandidate {
        let authValue: String
        let trimmedScheme = scheme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedScheme.isEmpty || header.caseInsensitiveCompare("Cookie") == .orderedSame {
            authValue = rawValue
        } else {
            authValue = "\(trimmedScheme) \(rawValue)"
        }
        return RelayCredentialCandidate(
            headers: buildHeaders(request: request, authHeader: header, authValue: authValue),
            source: source,
            persistedCredential: persistedCredential
        )
    }

    func buildHeaders(
        request: ResolvedRelayRequest,
        authHeader: String,
        authValue: String
    ) -> [String: String] {
        var headers = request.staticHeaders
        headers[authHeader] = authValue
        if let userID = request.userID {
            headers[request.userIDHeader] = userID
        }
        return headers
    }
}
