import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

struct TokenChannelResult {
    let remaining: Double?
    let used: Double?
    let limit: Double?
    let unit: String
    let note: String
    var rawMeta: [String: String]
    var recoveryMeta: [String: String] = [:]
}

struct RelayTokenChannelExecutor {
    let descriptor: ProviderDescriptor
    let credentialResolver: RelayCredentialResolver
    let recoveryPolicy: RelayRecoveryPolicy
    let httpClient: RelayHTTPClient

    func fetch(
        baseURL: URL,
        relayConfig: RelayProviderConfig,
        tokenRequest: RelayTokenRequestManifest,
        manifest: RelayAdapterManifest,
        forceRefresh: Bool,
        browserAccessIntent: BrowserCredentialAccessIntent
    ) async throws -> TokenChannelResult {
        let host = baseURL.host?.lowercased() ?? ""
        let credentialMode = relayConfig.balanceCredentialMode ?? .manualPreferred
        let primaryBrowserAccessIntent: BrowserCredentialAccessIntent =
            credentialMode == .browserOnly ? .interactiveImport : browserAccessIntent
        let primaryCandidates: [RelayRawTokenCandidate]
        switch credentialMode {
        case .manualPreferred:
            primaryCandidates = credentialResolver.resolveTokenCandidates(
                host: host,
                includeSavedCredentials: true,
                includeBrowserCredentials: false,
                browserAccessIntent: primaryBrowserAccessIntent
            )
        case .browserPreferred:
            primaryCandidates = credentialResolver.resolveTokenCandidates(
                host: host,
                includeSavedCredentials: !forceRefresh,
                includeBrowserCredentials: forceRefresh,
                browserAccessIntent: primaryBrowserAccessIntent
            )
        case .browserOnly:
            primaryCandidates = credentialResolver.resolveTokenCandidates(
                host: host,
                includeSavedCredentials: false,
                includeBrowserCredentials: true,
                browserAccessIntent: primaryBrowserAccessIntent
            )
        }

        var lastError: ProviderError = .missingCredential(descriptor.auth.keychainAccount ?? descriptor.id)
        func attempt(
            _ candidates: [RelayRawTokenCandidate],
            recoveryTrigger: String? = nil
        ) async throws -> TokenChannelResult? {
            guard !candidates.isEmpty else { return nil }
            for candidate in candidates {
                do {
                    let tokenUsage = try await httpClient.request(
                        url: RelayRequestResolver.relayURL(baseURL: baseURL, rawPath: tokenRequest.usagePath),
                        bearerToken: candidate.token,
                        type: OpenTokenUsageEnvelope.self
                    )

                    let subscription = try? await httpClient.request(
                        url: RelayRequestResolver.relayURL(baseURL: baseURL, rawPath: tokenRequest.subscriptionPath ?? ""),
                        bearerToken: candidate.token,
                        type: OpenBillingSubscription.self
                    )
                    let usage = try? await httpClient.request(
                        url: RelayRequestResolver.relayURL(baseURL: baseURL, rawPath: tokenRequest.billingUsagePath ?? ""),
                        bearerToken: candidate.token,
                        type: OpenBillingUsage.self
                    )

                    _ = credentialResolver.persistTokenCandidate(candidate.token, auth: descriptor.auth)

                    let unlimited = tokenUsage.data.unlimitedQuota
                    let remaining = unlimited ? nil : tokenUsage.data.totalAvailable
                    let used = tokenUsage.data.totalUsed
                    let softLimit = subscription?.softLimitUSD ?? tokenUsage.data.totalGranted
                    let hardLimit = subscription?.hardLimitUSD ?? softLimit
                    let limit = unlimited ? nil : max(tokenUsage.data.totalGranted, softLimit)

                    let note: String
                    if unlimited {
                        if let usage {
                            note = "Token unlimited | billing usage \(String(format: "%.2f", usage.totalUsage))"
                        } else {
                            note = "Token unlimited"
                        }
                    } else if let usage {
                        note = "Token remaining \(String(format: "%.2f", remaining ?? 0)) | billing usage \(String(format: "%.2f", usage.totalUsage))"
                    } else {
                        note = "Token remaining \(String(format: "%.2f", remaining ?? 0))"
                    }

                    var meta: [String: String] = [
                        "tokenName": tokenUsage.data.name,
                        "unlimitedQuota": String(unlimited),
                        "softLimitUsd": String(softLimit),
                        "hardLimitUsd": String(hardLimit),
                        "authSource": candidate.source,
                        "savedCredentialSource": candidate.source
                    ]
                    if let usage {
                        meta["billingTotalUsage"] = String(usage.totalUsage)
                    }
                    let recoveryMeta = recoveryTrigger.map {
                        recoveryPolicy.makeRecoveryMetadata(trigger: $0, source: candidate.source)
                    } ?? [:]

                    return TokenChannelResult(
                        remaining: remaining,
                        used: used,
                        limit: limit,
                        unit: "quota",
                        note: note,
                        rawMeta: meta,
                        recoveryMeta: recoveryMeta
                    )
                } catch let error as ProviderError {
                    switch error {
                    case .unauthorized, .unauthorizedDetail, .invalidResponse:
                        lastError = error
                        continue
                    default:
                        throw error
                    }
                }
            }
            return nil
        }

        if let result = try await attempt(primaryCandidates) {
            return result
        }

        let standardFallbackCandidates: [RelayRawTokenCandidate]
        switch credentialMode {
        case .manualPreferred:
            standardFallbackCandidates = []
        case .browserPreferred:
            standardFallbackCandidates = forceRefresh
                ? credentialResolver.resolveTokenCandidates(
                    host: host,
                    includeSavedCredentials: true,
                    includeBrowserCredentials: false,
                    browserAccessIntent: .background
                )
                : []
        case .browserOnly:
            standardFallbackCandidates = []
        }
        let fallbackDeduped = standardFallbackCandidates.filter { fallback in
            !primaryCandidates.contains(where: { $0.token == fallback.token })
        }

        if let result = try await attempt(fallbackDeduped) {
            return result
        }

        if let trigger = recoveryPolicy.recoveryTrigger(for: lastError),
           recoveryPolicy.relaySupportsBrowserRecovery(manifest: manifest, channel: .token),
           await recoveryPolicy.canAttemptBrowserRecovery(
                host: host,
                channel: .token,
                forceRefresh: forceRefresh
           ) {
            let recoveryCandidates = credentialResolver.resolveTokenCandidates(
                host: host,
                includeSavedCredentials: false,
                includeBrowserCredentials: true,
                browserAccessIntent: .authRecovery
            ).filter { fallback in
                !primaryCandidates.contains(where: { $0.token == fallback.token }) &&
                !fallbackDeduped.contains(where: { $0.token == fallback.token })
            }

            if let result = try await attempt(recoveryCandidates, recoveryTrigger: trigger) {
                await recoveryPolicy.clearBrowserRecoveryFailure(host: host, channel: .token)
                return result
            }
            await recoveryPolicy.markBrowserRecoveryFailure(host: host, channel: .token)
        }

        guard !(primaryCandidates.isEmpty && fallbackDeduped.isEmpty) else {
            throw recoveryPolicy.relayTokenPreflightError(
                baseURL: baseURL,
                credentialMode: credentialMode,
                manifest: manifest
            )
        }

        throw recoveryPolicy.relayFriendlyTokenError(lastError, baseURL: baseURL)
    }
}
