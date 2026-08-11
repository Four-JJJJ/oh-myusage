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
