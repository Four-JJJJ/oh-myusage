import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

struct CodexProfileSnapshotResult {
    var snapshot: UsageSnapshot
    var refreshedAuthJSON: String?
}

actor CodexProfileSnapshotService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(
        profile: CodexAccountProfile,
        descriptor: ProviderDescriptor
    ) async throws -> CodexProfileSnapshotResult {
        var authJSON = profile.authJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload = try CodexAccountProfileStore.parseAuthJSON(authJSON)
        var refreshedAuthJSON: String?
        var usageData: Data
        var usageResponse: HTTPURLResponse

        do {
            (usageData, usageResponse) = try await requestUsage(payload: payload)
        } catch let error as ProviderError {
            guard case .unauthorized = error,
                  let refreshed = try await refreshAuthJSONIfNeeded(rawAuthJSON: authJSON, payload: payload) else {
                throw error
            }
            authJSON = refreshed.rawAuthJSON
            payload = refreshed.payload
            if authJSON != profile.authJSON.trimmingCharacters(in: .whitespacesAndNewlines) {
                refreshedAuthJSON = authJSON
            }
            (usageData, usageResponse) = try await requestUsage(payload: payload)
        }

        var snapshot = try CodexProvider.parseUsageSnapshot(
            data: usageData,
            response: usageResponse,
            descriptor: descriptor,
            sourceLabel: "Profile",
            accountLabel: profile.accountEmail
        )

        if let accountId = payload.accountId, !accountId.isEmpty {
            snapshot.rawMeta["codex.accountId"] = accountId
            snapshot.rawMeta["codex.teamId"] = accountId
        }
        if let subject = payload.accountSubject, !subject.isEmpty {
            snapshot.rawMeta["codex.subject"] = subject
        }
        if let email = payload.accountEmail, !email.isEmpty {
            snapshot.rawMeta["codex.accountLabel"] = email
            snapshot.accountLabel = email
        }
        snapshot.rawMeta["codex.credentialFingerprint"] = payload.credentialFingerprint
        let identity = CodexIdentity.from(payload: payload)
        snapshot.rawMeta["codex.tenantKey"] = identity.tenantKey
        snapshot.rawMeta["codex.principalKey"] = identity.principalKey
        snapshot.rawMeta["codex.identityKey"] = identity.identityKey

        return CodexProfileSnapshotResult(
            snapshot: snapshot,
            refreshedAuthJSON: refreshedAuthJSON
        )
    }

    private func requestUsage(payload: CodexParsedAuthPayload) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(payload.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = payload.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        return try await OfficialProfileSnapshotRuntime.requestData(
            session: session,
            request: request,
            invalidResponseMessage: "non-http response"
        )
    }

    private func refreshAuthJSONIfNeeded(
        rawAuthJSON: String,
        payload: CodexParsedAuthPayload
    ) async throws -> (payload: CodexParsedAuthPayload, rawAuthJSON: String)? {
        guard let refreshToken = payload.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OfficialProviderAuthRuntime.urlEncodedFormData([
            "grant_type": "refresh_token",
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "refresh_token": refreshToken,
        ])

        let refresh = try await OfficialProviderAuthRuntime.requestOAuthRefresh(
            session: session,
            request: request,
            invalidResponseMessage: "refresh invalid response",
            missingAccessTokenMessage: "missing refresh access_token",
            httpErrorMessage: { "refresh http \($0)" }
        )

        let resolvedRefreshToken = OfficialValueParser.string(refresh.json["refresh_token"]) ?? payload.refreshToken
        let resolvedIDToken = OfficialValueParser.string(refresh.json["id_token"]) ?? payload.idToken
        let resolvedAccountID = OfficialValueParser.string(
            refresh.json["account_id"] ?? refresh.json["accountId"]
        ) ?? payload.accountId

        let updatedRawAuthJSON = try OfficialProfileSnapshotRuntime.mutateJSONObjectString(
            rawAuthJSON,
            invalidResponseMessage: "invalid refreshed auth json",
            writingOptions: [.prettyPrinted, .sortedKeys]
        ) { root in
            var tokens = (root["tokens"] as? [String: Any]) ?? root
            tokens["access_token"] = refresh.accessToken
            tokens["refresh_token"] = resolvedRefreshToken
            tokens["id_token"] = resolvedIDToken
            tokens["account_id"] = resolvedAccountID
            if root["tokens"] != nil {
                root["tokens"] = tokens
            } else {
                root = tokens
            }
            root["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        }

        let refreshedPayload = try CodexAccountProfileStore.parseAuthJSON(updatedRawAuthJSON)
        return (payload: refreshedPayload, rawAuthJSON: updatedRawAuthJSON)
    }
}
