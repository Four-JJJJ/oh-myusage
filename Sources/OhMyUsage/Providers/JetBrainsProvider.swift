import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class JetBrainsProvider: UsageProvider, @unchecked Sendable {
    private let localJSONReader: any LocalJSONFileReading
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        localJSONReader: any LocalJSONFileReading = DefaultLocalJSONFileReader()
    ) {
        self.descriptor = descriptor
        self.localJSONReader = localJSONReader
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .jetbrains)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("JetBrains 官方来源当前仅支持本地配额缓存检测")
        }
        let path = try findLatestQuotaPath()
        guard let xml = localJSONReader.text(atPath: path) else {
            throw ProviderError.invalidResponse("failed to read JetBrains quota xml")
        }
        return try Self.parseSnapshot(xml: xml, descriptor: descriptor)
    }

    private func findLatestQuotaPath() throws -> String {
        let base = "\(NSHomeDirectory())/Library/Application Support/JetBrains"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base) else {
            throw ProviderError.missingCredential(base)
        }
        let productPrefixes = ["Aqua","AndroidStudio","CLion","DataGrip","DataSpell","GoLand","IdeaIC","IntelliJIdea","IntelliJIdeaCE","PhpStorm","PyCharm","PyCharmCE","Rider","RubyMine","RustRover","WebStorm","Writerside"]
        var best: (path: String, until: Date, ratio: Double)?
        for entry in entries {
            guard productPrefixes.contains(where: { entry.hasPrefix($0) }) else { continue }
            let path = "\(base)/\(entry)/options/AIAssistantQuotaManager2.xml"
            guard let xml = localJSONReader.text(atPath: path),
                  let parsed = try? Self.extractQuota(xml: xml) else { continue }
            let ratio = parsed.maximum > 0 ? parsed.current / parsed.maximum : 0
            if let currentBest = best {
                if parsed.until > currentBest.until || (parsed.until == currentBest.until && ratio > currentBest.ratio) {
                    best = (path, parsed.until, ratio)
                }
            } else {
                best = (path, parsed.until, ratio)
            }
        }
        guard let best else {
            throw ProviderError.missingCredential("AIAssistantQuotaManager2.xml")
        }
        return best.path
    }

    internal static func parseSnapshot(xml: String, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        let quota = try extractQuota(xml: xml)
        let remainingPercent = max(0, quota.available / quota.maximum * 100)
        let resetAt = quota.nextRefill ?? quota.until
        let windows = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-quota",
                title: "Quota",
                remainingPercent: remainingPercent,
                usedPercent: max(0, 100 - remainingPercent),
                resetAt: resetAt,
                kind: .custom
            )
        ]
        return UsageSnapshot(
            source: descriptor.id,
            status: remainingPercent <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remainingPercent,
            used: 100 - remainingPercent,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Used \(Int(quota.current.rounded())) / \(Int(quota.maximum.rounded()))",
            quotaWindows: windows,
            sourceLabel: "Local",
            accountLabel: nil,
            extras: [
                "used": String(format: "%.0f", quota.current),
                "remaining": String(format: "%.0f", quota.available)
            ],
            rawMeta: [:]
        )
    }

    fileprivate static func extractQuota(xml: String) throws -> (current: Double, maximum: Double, available: Double, until: Date, nextRefill: Date?) {
        guard let quotaInfo = optionJSON(xml: xml, name: "quotaInfo") as? [String: Any] else {
            throw ProviderError.invalidResponse("missing JetBrains quotaInfo")
        }
        let nextRefill = optionJSON(xml: xml, name: "nextRefill") as? [String: Any]
        let tariffQuota = quotaInfo["tariffQuota"] as? [String: Any]
        let topUpQuota = quotaInfo["topUpQuota"] as? [String: Any]
        let current = OfficialValueParser.double(quotaInfo["current"])
            ?? (OfficialValueParser.double(tariffQuota?["current"]) ?? 0) + (OfficialValueParser.double(topUpQuota?["current"]) ?? 0)
        let maximum = OfficialValueParser.double(quotaInfo["maximum"])
            ?? (OfficialValueParser.double(tariffQuota?["maximum"]) ?? 0) + (OfficialValueParser.double(topUpQuota?["maximum"]) ?? 0)
        var available = OfficialValueParser.double(quotaInfo["available"])
            ?? (OfficialValueParser.double(tariffQuota?["available"]) ?? 0) + (OfficialValueParser.double(topUpQuota?["available"]) ?? 0)
        if available == 0, current <= maximum {
            available = maximum - current
        }
        guard maximum > 0,
              let untilString = OfficialValueParser.string(quotaInfo["until"]),
              let until = OfficialValueParser.isoDate(untilString) else {
            throw ProviderError.invalidResponse("invalid JetBrains quota values")
        }
        let nextRefillDate = OfficialValueParser.string(nextRefill?["next"]).flatMap { OfficialValueParser.isoDate($0) }
        return (current, maximum, available, until, nextRefillDate)
    }

    private static func optionJSON(xml: String, name: String) -> Any? {
        let pattern = #"<option\b[^>]*\bname=""# + NSRegularExpression.escapedPattern(for: name) + #""[^>]*\bvalue="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, range: range),
              let valueRange = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        let decoded = xml[valueRange]
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&#13;", with: "\r")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        guard let data = decoded.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
