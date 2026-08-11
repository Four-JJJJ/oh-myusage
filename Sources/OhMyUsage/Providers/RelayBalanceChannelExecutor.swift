import Foundation
import OhMyUsageDomain

struct RelayBalanceChannelExecutor {
    let descriptor: ProviderDescriptor
    let credentialResolver: RelayCredentialResolver
    let recoveryPolicy: RelayRecoveryPolicy
    let httpClient: RelayHTTPClient

    func fetch(
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        manifest: RelayAdapterManifest,
        forceRefresh: Bool,
        browserAccessIntent: BrowserCredentialAccessIntent
    ) async throws -> AccountChannelResult {
        let requests = RelayRequestResolver.resolveBalanceRequests(manifest: manifest, relayConfig: relayConfig)
        let credentialMode = relayConfig.balanceCredentialMode ?? .manualPreferred
        let requestForCandidates = requests.first ?? RelayRequestResolver.resolveBalanceRequest(manifest: manifest, relayConfig: relayConfig)
        let primaryBrowserAccessIntent: BrowserCredentialAccessIntent =
            credentialMode == .browserOnly ? .interactiveImport : browserAccessIntent

        let savedCredential = credentialResolver.readSavedCredential(auth: relayConfig.balanceAuth)
        let hasMiniMaxAPIKey = manifest.id == "minimax"
            && savedCredential.map { !credentialResolver.looksLikeCookieHeader($0) } == true
        if manifest.id == "minimax",
           !hasMiniMaxAPIKey,
           requestForCandidates.userID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw ProviderError.unauthorizedDetail(
                "MiniMax needs GroupId before it can query balance with a Cookie. Fill User ID with the GroupId from the account request URL, for example /account/query_balance?GroupId=..."
            )
        }
        if !hasMiniMaxAPIKey,
           let requiredInputError = recoveryPolicy.relayRequiredInputError(manifest: manifest, request: requestForCandidates) {
            throw requiredInputError
        }

        let primaryCandidates: [RelayCredentialCandidate]
        switch credentialMode {
        case .manualPreferred:
            primaryCandidates = credentialResolver.resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: true,
                includeBrowserCredentials: false,
                includeExpiredSentinel: true,
                browserAccessIntent: primaryBrowserAccessIntent
            )
        case .browserPreferred:
            primaryCandidates = credentialResolver.resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: !forceRefresh,
                includeBrowserCredentials: forceRefresh,
                includeExpiredSentinel: !forceRefresh,
                browserAccessIntent: primaryBrowserAccessIntent
            )
        case .browserOnly:
            primaryCandidates = credentialResolver.resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: false,
                includeBrowserCredentials: true,
                includeExpiredSentinel: false,
                browserAccessIntent: primaryBrowserAccessIntent
            )
        }

        var firstFailure: ProviderError?
        if !primaryCandidates.isEmpty {
            do {
                return try await attemptBalanceFetch(
                    candidates: primaryCandidates,
                    requests: requests,
                    baseURL: baseURL,
                    relayConfig: relayConfig,
                    manifest: manifest
                )
            } catch let error as ProviderError {
                firstFailure = error
            }
        }

        let standardFallbackCandidates: [RelayCredentialCandidate]
        switch credentialMode {
        case .manualPreferred:
            standardFallbackCandidates = []
        case .browserPreferred:
            standardFallbackCandidates = forceRefresh
                ? credentialResolver.resolveBalanceCandidates(
                    baseURL: baseURL,
                    manifest: manifest,
                    relayConfig: relayConfig,
                    request: requestForCandidates,
                    strategies: manifest.authStrategies,
                    includeSavedCredentials: true,
                    includeBrowserCredentials: false,
                    includeExpiredSentinel: true,
                    browserAccessIntent: .background
                )
                : []
        case .browserOnly:
            standardFallbackCandidates = []
        }
        let fallbackDeduped = standardFallbackCandidates.filter { fallback in
            !primaryCandidates.contains(where: { $0.headers == fallback.headers || $0.source == fallback.source })
        }
        if !fallbackDeduped.isEmpty {
            do {
                return try await attemptBalanceFetch(
                    candidates: fallbackDeduped,
                    requests: requests,
                    baseURL: baseURL,
                    relayConfig: relayConfig,
                    manifest: manifest
                )
            } catch let error as ProviderError {
                firstFailure = error
            }
        }

        let missingSavedCredentialRecoveryTrigger = shouldAttemptMissingSavedCredentialBrowserRecovery(
            credentialMode: credentialMode,
            forceRefresh: forceRefresh,
            manifest: manifest,
            relayConfig: relayConfig,
            primaryCandidates: primaryCandidates,
            fallbackCandidates: fallbackDeduped
        ) ? "missingSavedCredential" : nil
        let recoveryTrigger = firstFailure.flatMap(recoveryPolicy.recoveryTrigger(for:)) ?? missingSavedCredentialRecoveryTrigger

        if let trigger = recoveryTrigger,
           recoveryPolicy.relaySupportsBrowserRecovery(manifest: manifest, channel: .balance),
           await recoveryPolicy.canAttemptBrowserRecovery(
            host: baseURL.host?.lowercased() ?? "",
            channel: .balance,
            forceRefresh: forceRefresh
           ) {
            let recoveryCandidates = credentialResolver.resolveBalanceCandidates(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                strategies: manifest.authStrategies,
                includeSavedCredentials: credentialMode != .browserOnly,
                includeBrowserCredentials: true,
                includeExpiredSentinel: false,
                browserAccessIntent: .authRecovery
            ).filter { fallback in
                !primaryCandidates.contains(where: { $0.headers == fallback.headers || $0.source == fallback.source }) &&
                !fallbackDeduped.contains(where: { $0.headers == fallback.headers || $0.source == fallback.source })
            }

            if recoveryCandidates.isEmpty {
                // Keep the original auth error instead of masking it with a
                // missing-credential error from an empty recovery attempt.
                await recoveryPolicy.markBrowserRecoveryFailure(
                    host: baseURL.host?.lowercased() ?? "",
                    channel: .balance
                )
            } else {
                do {
                    let recovered = try await attemptBalanceFetch(
                        candidates: recoveryCandidates,
                        requests: requests,
                        baseURL: baseURL,
                        relayConfig: relayConfig,
                        manifest: manifest,
                        recoveryTrigger: trigger
                    )
                    await recoveryPolicy.clearBrowserRecoveryFailure(
                        host: baseURL.host?.lowercased() ?? "",
                        channel: .balance
                    )
                    return recovered
                } catch let error as ProviderError {
                    firstFailure = error
                    await recoveryPolicy.markBrowserRecoveryFailure(
                        host: baseURL.host?.lowercased() ?? "",
                        channel: .balance
                    )
                }
            }
        }

        if primaryCandidates.isEmpty && fallbackDeduped.isEmpty {
            if let preflightError = recoveryPolicy.relayBalancePreflightError(
                baseURL: baseURL,
                manifest: manifest,
                relayConfig: relayConfig,
                request: requestForCandidates,
                credentialMode: credentialMode,
                primaryCandidates: primaryCandidates,
                fallbackCandidates: fallbackDeduped
            ) {
                throw preflightError
            }
            if manifest.id == "moonshot",
               let savedRaw = credentialResolver.readSavedCredential(auth: relayConfig.balanceAuth),
               credentialResolver.looksLikeMoonshotNonAuthCookieHeader(savedRaw) {
                throw ProviderError.unauthorizedDetail(
                    "moonshot cookie appears incomplete; paste the full Cookie header from an authenticated platform request"
                )
            }
        }

        if let firstFailure {
            throw recoveryPolicy.relayFriendlyBalanceError(
                firstFailure,
                baseURL: baseURL,
                manifest: manifest,
                request: requestForCandidates,
                credentialMode: credentialMode
            )
        }

        throw ProviderError.missingCredential(relayConfig.balanceAuth.keychainAccount ?? "\(descriptor.id)/system-token")
    }

    private func shouldAttemptMissingSavedCredentialBrowserRecovery(
        credentialMode: RelayCredentialMode,
        forceRefresh: Bool,
        manifest: RelayAdapterManifest,
        relayConfig: RelayProviderConfig,
        primaryCandidates: [RelayCredentialCandidate],
        fallbackCandidates: [RelayCredentialCandidate]
    ) -> Bool {
        guard credentialMode == .browserPreferred,
              !forceRefresh,
              primaryCandidates.isEmpty,
              fallbackCandidates.isEmpty,
              recoveryPolicy.relaySupportsBrowserRecovery(manifest: manifest, channel: .balance) else {
            return false
        }
        return credentialResolver.readSavedCredential(auth: relayConfig.balanceAuth) == nil
    }

    private func attemptBalanceFetch(
        candidates: [RelayCredentialCandidate],
        requests: [ResolvedRelayRequest],
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        manifest: RelayAdapterManifest,
        recoveryTrigger: String? = nil
    ) async throws -> AccountChannelResult {
        guard !candidates.isEmpty else {
            throw ProviderError.missingCredential(relayConfig.balanceAuth.keychainAccount ?? "\(descriptor.id)/system-token")
        }

        if manifest.id == "xiaomimimo-token-plan" {
            return try await attemptXiaomimimoTokenPlanFetch(
                candidates: candidates,
                baseURL: baseURL,
                relayConfig: relayConfig,
                request: requests.first ?? RelayRequestResolver.resolveBalanceRequest(manifest: manifest, relayConfig: relayConfig),
                recoveryTrigger: recoveryTrigger
            )
        }

        var lastError: ProviderError = .missingCredential(relayConfig.balanceAuth.keychainAccount ?? "\(descriptor.id)/system-token")
    candidateLoop: for candidate in candidates {
            var harvestedPlanType: String?
            if candidate.source == "savedBearerExpired" {
                throw ProviderError.unauthorizedDetail("saved bearer token expired")
            }
            for request in requests {
                guard requestIsCompatible(
                    request: request,
                    candidate: candidate,
                    manifest: manifest
                ) else {
                    continue
                }
                do {
                    let candidateHeaders = requestHeaders(
                        request: request,
                        candidate: candidate,
                        manifest: manifest
                    )
                    let root = try await httpClient.requestJSON(
                        url: RelayRequestResolver.relayURL(baseURL: baseURL, rawPath: request.path),
                        headers: candidateHeaders.merging(request.staticHeaders, uniquingKeysWith: { _, rhs in rhs }),
                        method: request.method,
                        bodyJSON: request.bodyJSON
                    )
                    if manifest.id == "xiaomimimo",
                       let extractedPlanType = RelayResponseInterpreter.extractXiaomimimoPlanType(from: root) {
                        harvestedPlanType = extractedPlanType
                    }

                    var extracted = try await RelayResponseInterpreter.extractAccountValues(
                        root: root,
                        baseURL: baseURL,
                        request: request,
                        manifest: manifest,
                        headers: candidateHeaders,
                        candidate: candidate,
                        supplementalPlanType: harvestedPlanType,
                        requestJSON: httpClient.requestJSON
                    )

                    if let persisted = candidate.persistedCredential {
                        _ = credentialResolver.persistTokenCandidate(persisted, auth: relayConfig.balanceAuth)
                    }
                    extracted.rawMeta["savedCredentialSource"] = candidate.source
                    if let recoveryTrigger {
                        extracted.recoveryMeta = recoveryPolicy.makeRecoveryMetadata(
                            trigger: recoveryTrigger,
                            source: candidate.source
                        )
                    }

                    return extracted
                } catch let error as ProviderError {
                    switch error {
                    case .invalidResponse:
                        lastError = error
                        continue
                    case .unauthorized, .unauthorizedDetail:
                        lastError = error
                        continue candidateLoop
                    default:
                        throw error
                    }
                }
            }
        }
        throw lastError
    }

    private func requestIsCompatible(
        request: ResolvedRelayRequest,
        candidate: RelayCredentialCandidate,
        manifest: RelayAdapterManifest
    ) -> Bool {
        if manifest.id == "minimax" {
            let isCodingPlanRequest = request.path.contains("/coding_plan/remains")
            let isBearer = candidate.source.lowercased().contains("bearer")
            return isCodingPlanRequest == isBearer
        }
        if manifest.id == "deepseek",
           let raw = candidate.persistedCredential?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let isPublicBalanceRequest = request.path.contains("api.deepseek.com/user/balance")
            return raw.lowercased().hasPrefix("sk-") == isPublicBalanceRequest
        }
        return true
    }

    private func requestHeaders(
        request: ResolvedRelayRequest,
        candidate: RelayCredentialCandidate,
        manifest: RelayAdapterManifest
    ) -> [String: String] {
        guard manifest.id == "minimax",
              request.path.contains("/coding_plan/remains"),
              let raw = candidate.persistedCredential else {
            return candidate.headers
        }
        var headers = candidate.headers
        headers.removeValue(forKey: "Cookie")
        headers["Authorization"] = "Bearer \(credentialResolver.normalizeBearerToken(raw))"
        return headers
    }

    private func attemptXiaomimimoTokenPlanFetch(
        candidates: [RelayCredentialCandidate],
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        request: ResolvedRelayRequest,
        recoveryTrigger: String? = nil
    ) async throws -> AccountChannelResult {
        var lastError: ProviderError = .missingCredential(relayConfig.balanceAuth.keychainAccount ?? "\(descriptor.id)/system-token")

        for candidate in candidates {
            if candidate.source == "savedBearerExpired" {
                throw ProviderError.unauthorizedDetail("saved bearer token expired")
            }

            do {
                let headers = candidate.headers.merging(request.staticHeaders, uniquingKeysWith: { _, rhs in rhs })
                let detailRoot = try await httpClient.requestJSON(
                    url: RelayRequestResolver.relayURL(baseURL: baseURL, rawPath: "/api/v1/tokenPlan/detail"),
                    headers: headers,
                    method: "GET",
                    bodyJSON: nil
                )
                let usageRoot = try await httpClient.requestJSON(
                    url: RelayRequestResolver.relayURL(baseURL: baseURL, rawPath: "/api/v1/tokenPlan/usage"),
                    headers: headers,
                    method: "GET",
                    bodyJSON: nil
                )

                var extracted = try RelayResponseInterpreter.extractXiaomimimoTokenPlanValues(
                    detailRoot: detailRoot,
                    usageRoot: usageRoot,
                    candidate: candidate
                )

                if let persisted = candidate.persistedCredential {
                    _ = credentialResolver.persistTokenCandidate(persisted, auth: relayConfig.balanceAuth)
                }
                extracted.rawMeta["savedCredentialSource"] = candidate.source
                if let recoveryTrigger {
                    extracted.recoveryMeta = recoveryPolicy.makeRecoveryMetadata(
                        trigger: recoveryTrigger,
                        source: candidate.source
                    )
                }

                return extracted
            } catch let error as ProviderError {
                switch error {
                case .invalidResponse:
                    lastError = error
                    continue
                case .unauthorized, .unauthorizedDetail:
                    lastError = error
                    continue
                default:
                    throw error
                }
            }
        }

        throw lastError
    }
}
