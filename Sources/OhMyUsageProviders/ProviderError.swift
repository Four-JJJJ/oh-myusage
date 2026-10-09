import Foundation

public enum ProviderError: Error, LocalizedError {
    case missingCredential(String)
    case unauthorized
    case unauthorizedDetail(String)
    case rateLimited
    case invalidResponse(String)
    case commandFailed(String)
    case timeout(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential(let account):
            return "Missing credential for \(account)"
        case .unauthorized:
            return "Unauthorized"
        case .unauthorizedDetail(let detail):
            return "Unauthorized: \(detail)"
        case .rateLimited:
            return "Rate limited"
        case .invalidResponse(let detail):
            return "Invalid response: \(detail)"
        case .commandFailed(let detail):
            return "Command failed: \(detail)"
        case .timeout(let detail):
            return "Timeout: \(detail)"
        case .unavailable(let detail):
            return detail
        }
    }
}

/// Transport metadata kept separate from the source-compatible ProviderError cases.
public struct ProviderRateLimitError: Error, LocalizedError, Sendable {
    public let retryNotBefore: Date
    public var errorDescription: String? { "Rate limited" }

    public init(retryNotBefore: Date) { self.retryNotBefore = retryNotBefore }

    public static func parseRetryAfter(_ value: String?, now: Date = Date()) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 {
            let deadline = now.addingTimeInterval(seconds)
            guard deadline.timeIntervalSinceReferenceDate.isFinite, deadline <= Date.distantFuture else { return nil }
            return deadline
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value), date >= now else { return nil }
        return date
    }
}
