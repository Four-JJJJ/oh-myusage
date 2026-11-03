import Foundation
import os

/// `os_signpost` intervals for the paths whose cost decides responsiveness
/// and energy: launch, each provider fetch, and analytics scans. They are
/// near free when no tool is recording; `scripts/perf.sh trace` captures them
/// with Instruments so tuning decisions rest on measurements.
enum PerformanceSignposts {
    static let signposter = OSSignposter(subsystem: "OhMyUsage", category: "Performance")

    static func interval<T>(
        _ name: StaticString,
        _ label: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(label, privacy: .public)")
        defer { signposter.endInterval(name, state) }
        return try await operation()
    }

    static func event(_ name: StaticString, _ label: String = "") {
        signposter.emitEvent(name, "\(label, privacy: .public)")
    }
}
