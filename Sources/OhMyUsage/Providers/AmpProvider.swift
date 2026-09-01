import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class AmpProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    private let localJSONReader: any LocalJSONFileReading
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        localJSONReader: any LocalJSONFileReading = DefaultLocalJSONFileReader()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.localJSONReader = localJSONReader
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .amp)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Amp 官方来源当前仅支持 API 检测")
        }

        let apiKey = try resolveAPIKey()
        var request = URLRequest(url: URL(string: "https://ampcode.com/api/internal")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["method": "userDisplayBalanceInfo", "params": [:]])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Amp non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Amp http \(http.statusCode)")
        }
        return try Self.parseSnapshot(data: data, descriptor: descriptor)
    }

    private func resolveAPIKey() throws -> String {
        let path = "\(NSHomeDirectory())/.local/share/amp/secrets.json"
        guard let json = localJSONReader.dictionary(atPath: path),
              let value = OfficialValueParser.string(json["apiKey@https://ampcode.com/"]) else {
            throw ProviderError.missingCredential(path)
        }
        return value
    }

    internal static func parseSnapshot(data: Data, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = root["ok"] as? Bool, ok,
              let result = root["result"] as? [String: Any],
              let displayText = OfficialValueParser.string(result["displayText"]) else {
            throw ProviderError.invalidResponse("Amp response missing displayText")
        }

        let freeMatch = displayText.regexCaptures(pattern: #"\$([0-9][0-9,]*(?:\.[0-9]+)?)\/\$([0-9][0-9,]*(?:\.[0-9]+)?) remaining"#)
        let rateMatch = displayText.regexCaptures(pattern: #"replenishes \+\$([0-9][0-9,]*(?:\.[0-9]+)?)\/hour"#)
        let creditsMatch = displayText.regexCaptures(pattern: #"Individual credits: \$([0-9][0-9,]*(?:\.[0-9]+)?) remaining"#)

        var windows: [UsageQuotaWindow] = []
        var extras: [String: String] = [:]

        if freeMatch.count >= 3,
           let remainingDollars = parseMoney(freeMatch[1]),
           let totalDollars = parseMoney(freeMatch[2]), totalDollars > 0 {
            let remainingPercent = remainingDollars / totalDollars * 100
            let hourlyRate = rateMatch.count >= 2 ? parseMoney(rateMatch[1]) : nil
            let usedDollars = max(0, totalDollars - remainingDollars)
            let resetAt = (hourlyRate ?? 0) > 0 && usedDollars > 0
                ? Date().addingTimeInterval((usedDollars / (hourlyRate ?? 1)) * 3600)
                : nil
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-free",
                    title: "Free",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: resetAt,
                    kind: .custom
                )
            )
            extras["freeRemaining"] = String(format: "%.2f", remainingDollars)
            extras["freeTotal"] = String(format: "%.2f", totalDollars)
        }

        if creditsMatch.count >= 2, let credits = parseMoney(creditsMatch[1]) {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-credits",
                    title: "Credits",
                    remainingPercent: credits > 0 ? 100 : 0,
                    usedPercent: credits > 0 ? 0 : 100,
                    resetAt: nil,
                    kind: .credits
                )
            )
            extras["creditsBalance"] = String(format: "%.2f", credits)
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("could not parse Amp balance text")
        }

        let plan = windows.contains(where: { $0.title == "Free" }) ? "Free" : "Credits"
        let remaining = windows.map(\.remainingPercent).min() ?? 0
        extras["planType"] = plan
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Plan \(plan) | " + windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: nil,
            extras: extras,
            rawMeta: [:]
        )
    }

    private static func parseMoney(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: ""))
    }
}

private extension String {
    func regexCaptures(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return [] }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: self) else { return nil }
            return String(self[range])
        }
    }
}
