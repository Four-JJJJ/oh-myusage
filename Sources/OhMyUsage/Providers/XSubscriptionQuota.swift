import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

/// The X Subscription shares one weekly included pool across Grok, Cursor, and Grok Bot.
/// Legacy Cursor plans keep separate monthly pools; this helper only recognizes the unified shape.
enum XSubscriptionQuota {
    static let scope = "x-subscription"

    static func isUnified(_ json: [String: Any]) -> Bool {
        if bool(json["isUnified"]) == true || bool(json["isUnifiedBillingUser"]) == true {
            return true
        }
        if let config = json["config"] as? [String: Any],
           bool(config["isUnifiedBillingUser"]) == true || bool(config["isUnified"]) == true {
            return true
        }
        if let brand = OfficialValueParser.string(json["billingBrand"])?.uppercased(),
           brand.contains("GROK") {
            return true
        }
        return false
    }

    /// Included usage consumed, 0...100. proto3 omits a genuine 0.
    static func includedUsedPercent(from sand: [String: Any]) -> Double {
        let raw = OfficialValueParser.double(sand["usagePercent"]) ?? 0
        return min(100, max(0, raw))
    }

    static func centAmount(_ value: Any?) -> Double? {
        if let object = value as? [String: Any] {
            return OfficialValueParser.double(object["val"])
        }
        return OfficialValueParser.double(value)
    }

    static func usdText(cents: Double) -> String {
        let dollars = cents / 100
        if dollars.rounded() == dollars {
            return "$\(Int(dollars))"
        }
        return String(format: "$%.2f", dollars)
    }

    static func parseTimestamp(_ raw: Any?) -> Date? {
        if let string = OfficialValueParser.string(raw) {
            if let date = OfficialValueParser.isoDate(string) {
                return date
            }
            if let number = Double(string) {
                return parseEpoch(number)
            }
        }
        if let number = OfficialValueParser.double(raw) {
            return parseEpoch(number)
        }
        return nil
    }

    private static func parseEpoch(_ number: Double) -> Date? {
        if number > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: number / 1000)
        }
        if number > 1_000_000_000 {
            return Date(timeIntervalSince1970: number)
        }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        return nil
    }
}
