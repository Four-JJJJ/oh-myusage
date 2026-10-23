import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

extension RelayResponseInterpreter {
    // DeepSeek's platform session endpoint reports auth failures as HTTP 200 with a
    // business code instead of an HTTP error. API keys (sk-...) are always rejected
    // there; surface that as invalidResponse so the executor falls through to the
    // api.deepseek.com balance probe, and treat real session tokens as expired so
    // browser recovery can re-import a fresh login.
    static func deepseekBusinessError(root: Any, candidate: RelayCredentialCandidate) -> ProviderError? {
        guard let dict = root as? [String: Any] else { return nil }
        let topLevelCode = (dict["code"] as? NSNumber)?.intValue
        let nestedCode = (dict["data"] as? [String: Any]).flatMap { ($0["code"] as? NSNumber)?.intValue }
        guard let code = topLevelCode ?? nestedCode, code == 40002 || code == 40003 else {
            return nil
        }
        let rawMessage = (dict["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = rawMessage.isEmpty ? "code \(code)" : rawMessage
        if candidate.persistedCredential?.hasPrefix("sk-") == true {
            return .invalidResponse("deepseek session endpoint rejected API key (\(message))")
        }
        return .unauthorizedDetail("DeepSeek login missing or expired (\(message))")
    }
}
