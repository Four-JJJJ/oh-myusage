import Foundation
import OSLog
import OhMyUsageProviders

/// Outcome of one successful OAuth credential refresh through the shared
/// desktop refresh pipeline.
struct OAuthRefreshPipelineResult {
    /// The refreshed, parse-verified normalized OAuth JSON. This value stays
    /// authoritative even when the write-backs below failed: the token server
    /// has already accepted the refresh, so callers must keep using it.
    let refreshedRawJSON: String

    /// Credential file paths whose merge write-back failed. Failures are
    /// logged and never fail the refresh itself.
    let fileWriteFailures: [String]

    /// Whether the app-vault write-back succeeded. Failures are logged and
    /// never fail the refresh itself.
    let vaultWriteSucceeded: Bool
}

/// Shared Codex / Claude desktop OAuth refresh pipeline.
///
/// Unifies the isomorphic chain both desktop auth services previously
/// hand-wrote per provider: refresh request construction → response field
/// extraction → in-memory JSON merge → parse verification → credential JSON
/// file merge write-back → vault write-back.
///
/// Observability contract: credential file / vault write-back failures are
/// logged (default sink: os_log, injectable for tests) and reported in the
/// result, but they never fail an otherwise successful refresh — the token
/// server already accepted the refresh, so the refreshed credential remains
/// authoritative in memory and in the returned value. A failing refresh
/// request still throws, and a credential without a refresh token still
/// returns nil, exactly like the previous per-service implementations.
struct OAuthRefreshPipeline: Sendable {
    enum WriteBackError: LocalizedError {
        case fileDecodeFailed(path: String)
        case fileEncodeFailed(path: String)

        var errorDescription: String? {
            switch self {
            case .fileDecodeFailed(let path):
                return "unable to decode a JSON object at \(path)"
            case .fileEncodeFailed(let path):
                return "unable to encode the merged JSON object for \(path)"
            }
        }
    }

    /// Per-provider configuration: everything that differs between the Codex
    /// and Claude desktop refresh flows (endpoint, request body, field
    /// mapping, writing options, canonical parse verification).
    struct Configuration: @unchecked Sendable {
        /// Log label ("Codex" / "Claude").
        let label: String
        /// Vault tier this provider persists the refreshed JSON into.
        let vaultProvider: OAuthImportProvider
        /// Builds the OAuth token refresh request for a refresh token.
        let makeRefreshRequest: (_ refreshToken: String) throws -> URLRequest
        /// `ProviderError` message used when the refreshed JSON cannot be
        /// decoded or re-encoded.
        let invalidRefreshedJSONMessage: String
        /// Writing options applied to both the in-memory merge and each file
        /// merge write-back.
        let writingOptions: JSONSerialization.WritingOptions
        /// Extracts the refreshed fields from the token response and merges
        /// them into the given JSON object. Applied once in memory and again
        /// for every on-disk merge write-back.
        let mergeRefreshedFields: (
            _ response: OfficialOAuthRefreshResponse,
            _ now: Date,
            _ json: inout [String: Any]
        ) -> Void
        /// Parse-verifies the merged JSON with the provider's canonical parser.
        let verifyRefreshedJSON: (_ rawJSON: String) throws -> Void
    }

    /// Injectable credential-file IO seam (read/decode/encode/write failures
    /// must be observable instead of silently swallowed).
    struct FileIO: @unchecked Sendable {
        let read: (_ path: String) throws -> Data
        let write: (_ data: Data, _ path: String) throws -> Void

        static let `default` = FileIO(
            read: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
            write: { data, path in
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        )
    }

    /// Default observability sink, matching the repo's os_log style
    /// (see `LocalUsageHistoryRepository`).
    static let standardLog: @Sendable (String) -> Void = { message in
        Logger(subsystem: "OhMyUsage", category: "OAuthRefreshPipeline")
            .notice("\(message, privacy: .public)")
    }

    let configuration: Configuration
    let log: @Sendable (String) -> Void

    init(
        configuration: Configuration,
        log: @escaping @Sendable (String) -> Void = OAuthRefreshPipeline.standardLog
    ) {
        self.configuration = configuration
        self.log = log
    }

    /// Runs the shared refresh chain.
    ///
    /// - Returns nil when `refreshToken` is absent or blank — the same
    ///   "nothing to refresh" semantics the per-service implementations had.
    /// - Throws when the refresh request fails (network / HTTP / missing
    ///   access token) or the refreshed JSON cannot be parsed; the pipeline
    ///   then performs no write-backs at all.
    /// - Write-back failures are logged and surfaced in the result; the
    ///   refresh itself still counts as successful.
    func refreshCredential(
        session: URLSession,
        rawJSON: String,
        refreshToken: String?,
        filePaths: [String],
        vault: OfficialOAuthVaultStore,
        fileIO: FileIO = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) async throws -> OAuthRefreshPipelineResult? {
        guard let refreshToken = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty else {
            return nil
        }

        let request = try configuration.makeRefreshRequest(refreshToken)
        let refresh = try await OfficialProviderAuthRuntime.requestOAuthRefresh(
            session: session,
            request: request,
            invalidResponseMessage: "refresh invalid response",
            missingAccessTokenMessage: "missing refresh access_token",
            httpErrorMessage: { "refresh http \($0)" }
        )

        let refreshedRawJSON = try OfficialProfileSnapshotRuntime.mutateJSONObjectString(
            rawJSON,
            invalidResponseMessage: configuration.invalidRefreshedJSONMessage,
            writingOptions: configuration.writingOptions
        ) { root in
            configuration.mergeRefreshedFields(refresh, now(), &root)
        }
        try configuration.verifyRefreshedJSON(refreshedRawJSON)

        var fileWriteFailures: [String] = []
        for path in filePaths {
            do {
                try mergeWriteRefreshedCredential(
                    response: refresh,
                    toFile: path,
                    fileIO: fileIO,
                    now: now
                )
            } catch {
                fileWriteFailures.append(path)
                log("\(configuration.label): failed to merge the refreshed OAuth credential into \(path): \(error.localizedDescription)")
            }
        }

        let vaultWriteSucceeded = vault.saveOAuthJSON(
            provider: configuration.vaultProvider,
            rawJSON: refreshedRawJSON
        )
        if !vaultWriteSucceeded {
            log("\(configuration.label): failed to store the refreshed OAuth credential in the app vault; local credential files remain the fallback")
        }

        return OAuthRefreshPipelineResult(
            refreshedRawJSON: refreshedRawJSON,
            fileWriteFailures: fileWriteFailures,
            vaultWriteSucceeded: vaultWriteSucceeded
        )
    }

    /// Reads the JSON object at `path`, merges the refreshed fields into it,
    /// and writes it back atomically. Mirrors the merge semantics of
    /// `OfficialProviderAuthRuntime.updateJSONObjectFile`, but reports
    /// decode / encode / IO failures instead of silently swallowing them.
    private func mergeWriteRefreshedCredential(
        response: OfficialOAuthRefreshResponse,
        toFile path: String,
        fileIO: FileIO,
        now: @escaping @Sendable () -> Date
    ) throws {
        let data = try fileIO.read(path)
        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw WriteBackError.fileDecodeFailed(path: path)
        }

        configuration.mergeRefreshedFields(response, now(), &json)

        guard let encoded = try? JSONSerialization.data(
            withJSONObject: json,
            options: configuration.writingOptions
        ) else {
            throw WriteBackError.fileEncodeFailed(path: path)
        }

        try fileIO.write(encoded, path)
    }
}
