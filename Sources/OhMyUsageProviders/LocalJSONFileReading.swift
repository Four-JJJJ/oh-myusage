import Foundation

/// Provider-side port for reading local JSON/text config files.
public protocol LocalJSONFileReading: Sendable {
    func dictionary(atPath path: String) -> [String: Any]?
    func text(atPath path: String) -> String?
}
