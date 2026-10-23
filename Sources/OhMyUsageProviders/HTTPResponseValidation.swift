import Foundation

/// Unified classification vocabulary for a rejected provider HTTP response.
///
/// `HTTPResponseValidation.validate` maps these onto the repository's existing
/// `ProviderError` / `ProviderRateLimitError` types, so callers and the
/// scheduling layer keep a single error system while tests and diagnostics can
/// reason about the class of the failure.
public enum HTTPResponseFailure: Error, Equatable, Sendable {
    /// 429, optionally carrying the parsed `Retry-After` hint in seconds.
    case rateLimited(retryAfterSeconds: TimeInterval?)
    /// 401 (or a caller-declared auth status) — the credential was rejected.
    case unauthorized
    /// 403 — the credential is valid but access to the endpoint is denied.
    case forbidden
    /// 408 and 5xx — server/transport failure worth retrying later.
    case serverFailure(statusCode: Int)
    /// Any other non-2xx status.
    case invalidStatus(statusCode: Int)
}

/// Shared HTTP status validation for provider integrations.
///
/// Replaces the per-provider "2xx check + 401/403/429/5xx mapping" blocks with
/// one classification that throws the existing `ProviderError` cases (plus
/// `ProviderRateLimitError` when a 429 carries a usable `Retry-After`).
public enum HTTPResponseValidation {
    /// `Retry-After` hints are capped so a misbehaving server cannot park a
    /// provider for hours.
    public static let retryAfterCeiling: TimeInterval = 3600

    public static func isSuccess(_ response: HTTPURLResponse) -> Bool {
        (200...299).contains(response.statusCode)
    }

    /// Parses the `Retry-After` header (delta-seconds, or HTTP-date) into a
    /// number of seconds from `now`, clamped to `retryAfterCeiling`.
    /// Returns nil when the header is missing or unparseable.
    public static func retryAfterSeconds(from response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
        guard let deadline = ProviderRateLimitError.parseRetryAfter(
            response.value(forHTTPHeaderField: "Retry-After"),
            now: now
        ) else {
            return nil
        }
        let seconds = deadline.timeIntervalSince(now)
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return min(seconds, retryAfterCeiling)
    }

    /// Classifies a non-2xx response. 2xx inputs are not a failure; callers
    /// that pass one get `.invalidStatus` only as a defensive fallback.
    public static func classify(
        _ response: HTTPURLResponse,
        tolerant403: Bool = false,
        unauthorizedStatusCodes: Set<Int> = [401, 403],
        now: Date = Date()
    ) -> HTTPResponseFailure {
        let statusCode = response.statusCode
        if statusCode == 429 {
            return .rateLimited(retryAfterSeconds: retryAfterSeconds(from: response, now: now))
        }
        if statusCode == 403 {
            if tolerant403 {
                return .invalidStatus(statusCode: statusCode)
            }
            if unauthorizedStatusCodes.contains(403) {
                return .forbidden
            }
        }
        if unauthorizedStatusCodes.contains(statusCode) {
            return .unauthorized
        }
        if statusCode == 408 || (500...599).contains(statusCode) {
            return .serverFailure(statusCode: statusCode)
        }
        return .invalidStatus(statusCode: statusCode)
    }

    /// Obvious-HTML detection for responses that should have been JSON: an
    /// HTML Content-Type, or a body that starts with an HTML document. Uses
    /// only conservative markers so a JSON body mentioning markup words is
    /// never mistaken for a page.
    public static func looksLikeHTML(_ response: HTTPURLResponse, body: Data? = nil) -> Bool {
        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("text/html") {
            return true
        }
        guard let body,
              let text = String(data: body, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !text.isEmpty else {
            return false
        }
        return text.hasPrefix("<!doctype html") || text.hasPrefix("<html")
    }

    /// Validates a provider HTTP response and throws the shared error mapping:
    ///
    /// - non-2xx → `ProviderError.unauthorized` / `.unauthorizedDetail`,
    ///   `ProviderRateLimitError` (429 with `Retry-After`) or
    ///   `ProviderError.rateLimited`, `ProviderError.timeout` (408/5xx), or
    ///   `ProviderError.invalidResponse` for every other status.
    /// - 2xx with `expectingJSON` and an HTML Content-Type/body →
    ///   `ProviderError.invalidResponse`.
    ///
    /// - Parameters:
    ///   - urlDescription: short endpoint label folded into default error
    ///     messages ("Cursor http 403"); pass an empty string for the bare
    ///     "http 403" form.
    ///   - body: response body, used for HTML detection and the
    ///     `unauthorizedMessage` hook.
    ///   - expectingJSON: reject 2xx responses that are obviously HTML.
    ///   - tolerant403: classify 403 as a generic invalid status instead of an
    ///     auth failure (endpoints where 403 means misconfiguration, not a
    ///     bad credential).
    ///   - unauthorizedStatusCodes: statuses treated as credential rejection.
    ///   - unauthorizedMessage: optional hook mapping an auth failure to a
    ///     user-facing detail message; a non-empty result throws
    ///     `.unauthorizedDetail`, nil throws plain `.unauthorized`.
    ///   - invalidResponseMessage: optional override for the generic
    ///     non-2xx `.invalidResponse` detail.
    ///   - now: reference date for `Retry-After` computation.
    public static func validate(
        _ response: HTTPURLResponse,
        urlDescription: String,
        body: Data? = nil,
        expectingJSON: Bool = true,
        tolerant403: Bool = false,
        unauthorizedStatusCodes: Set<Int> = [401, 403],
        unauthorizedMessage: ((_ statusCode: Int, _ body: Data?) -> String?)? = nil,
        invalidResponseMessage: ((_ statusCode: Int) -> String)? = nil,
        now: Date = Date()
    ) throws {
        if isSuccess(response) {
            if expectingJSON, looksLikeHTML(response, body: body) {
                throw ProviderError.invalidResponse(message("html response", urlDescription: urlDescription))
            }
            return
        }

        switch classify(
            response,
            tolerant403: tolerant403,
            unauthorizedStatusCodes: unauthorizedStatusCodes,
            now: now
        ) {
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds {
                throw ProviderRateLimitError(retryNotBefore: now.addingTimeInterval(retryAfterSeconds))
            }
            throw ProviderError.rateLimited
        case .unauthorized, .forbidden:
            if let message = unauthorizedMessage?(response.statusCode, body), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            throw ProviderError.unauthorized
        case .serverFailure(let statusCode):
            throw ProviderError.timeout(message("http \(statusCode)", urlDescription: urlDescription))
        case .invalidStatus(let statusCode):
            let detail = invalidResponseMessage?(statusCode)
                ?? message("http \(statusCode)", urlDescription: urlDescription)
            throw ProviderError.invalidResponse(detail)
        }
    }

    private static func message(_ detail: String, urlDescription: String) -> String {
        urlDescription.isEmpty ? detail : "\(urlDescription) \(detail)"
    }
}
