import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

enum MiniMaxCodingPlanParser {
    static func parse(
        root: Any,
        request: ResolvedRelayRequest,
        candidate: RelayCredentialCandidate
    ) throws -> AccountChannelResult {
        guard let body = root as? [String: Any] else {
            throw ProviderError.invalidResponse("MiniMax coding plan response is not an object")
        }
        if let baseResponse = body["base_resp"] as? [String: Any],
           let statusCode = OfficialValueParser.int(baseResponse["status_code"]),
           statusCode != 0 {
            let message = OfficialValueParser.string(baseResponse["status_msg"]) ?? "code \(statusCode)"
            throw ProviderError.invalidResponse("MiniMax coding plan \(message)")
        }
        let remains = (body["model_remains"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        guard let general = remains.first(where: {
            OfficialValueParser.string($0["model_name"])?.lowercased() == "general"
        }) else {
            throw ProviderError.invalidResponse("missing MiniMax general coding plan quota")
        }

        var windows: [UsageQuotaWindow] = []
        if let remaining = OfficialValueParser.double(general["current_interval_remaining_percent"]) {
            windows.append(
                UsageQuotaWindow(
                    id: "minimax-coding-plan-5h",
                    title: "5h",
                    remainingPercent: min(100, max(0, remaining)),
                    usedPercent: min(100, max(0, 100 - remaining)),
                    resetAt: normalizedEpochDate(general["end_time"]),
                    kind: .session
                )
            )
        }
        if OfficialValueParser.int(general["current_weekly_status"]) == 1,
           let remaining = OfficialValueParser.double(general["current_weekly_remaining_percent"]) {
            windows.append(
                UsageQuotaWindow(
                    id: "minimax-coding-plan-weekly",
                    title: "Weekly",
                    remainingPercent: min(100, max(0, remaining)),
                    usedPercent: min(100, max(0, 100 - remaining)),
                    resetAt: normalizedEpochDate(general["weekly_end_time"]),
                    kind: .weekly
                )
            )
        }
        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("missing MiniMax coding plan windows")
        }
        let remaining = windows.map(\.remainingPercent).min() ?? 0
        return AccountChannelResult(
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            accountLabel: nil,
            planType: "Coding Plan",
            quotaWindows: windows,
            note: windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            rawMeta: [
                "endpointPath": request.path,
                "requestMethod": request.method,
                "authSource": candidate.source
            ]
        )
    }

    private static func normalizedEpochDate(_ value: Any?) -> Date? {
        guard let raw = OfficialValueParser.double(value), raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1000 : raw)
    }

}
