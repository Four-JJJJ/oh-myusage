import Foundation

public enum JWTInspector {
    public static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    public static func email(_ token: String) -> String? {
        OfficialValueParser.string(payload(token)?["email"])
    }

    public static func subject(_ token: String) -> String? {
        OfficialValueParser.string(payload(token)?["sub"])
    }

    public static func expirationDate(_ token: String) -> Date? {
        guard let exp = OfficialValueParser.double(payload(token)?["exp"]) else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
