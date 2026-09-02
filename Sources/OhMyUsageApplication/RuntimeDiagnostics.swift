import Foundation
import Darwin.Mach

package enum RuntimeDiagnosticsLimits {
    package static let snapshotNoteMaxLength = 384
    package static let localUsageTrendCacheMaxEntries = 24
    package static let localUsageParsedFileCacheMaxEntries = 256
    package static let localUsageParsedFileCacheMaxCachedValues = 32_768
    package static let usageAnalyticsCacheMaxEntries = 16
    package static let thirdPartyBalanceBaselineCacheMaxEntries = 24
    package static let localUsageTrendCacheEntryTTL: TimeInterval = 15 * 60
    package static let localUsageTrendFingerprintProbeInterval: TimeInterval = 60
    package static let usageAnalyticsCacheEntryTTL: TimeInterval = 15 * 60
    package static let usageAnalyticsFingerprintProbeInterval: TimeInterval = 60
    package static let localUsageTrendModelBreakdownCacheEntries = 0
    package static let localSessionSignalActiveSleepSeconds: TimeInterval = 15
    package static let localSessionSignalIdleSleepSeconds: TimeInterval = 60
    package static let menuClockIntervalSeconds: TimeInterval = 5
    package static let statusBarVisibleRefreshIntervalSeconds: TimeInterval = 60
    package static let settingsClockIntervalSeconds: TimeInterval = 15
    package static let claudePrefetchMaxConcurrent = 2
    package static let claudeSignalMaxTrackedFiles = 200
    package static let jsonlMaxLineBytes = 512 * 1024
    package static let jsonlMaxFileBytes = 64 * 1024 * 1024
}

package struct RuntimeMemoryDiagnostics: Equatable {
    package var residentSizeBytes: UInt64?
    package var snapshotCount: Int
    package var codexProfileCount: Int
    package var codexSlotCount: Int
    package var claudeProfileCount: Int
    package var claudeSlotCount: Int
    package var codexPrefetchAttemptedIdentityCount: Int
    package var codexPrefetchInFlightCount: Int
    package var claudePrefetchAttemptedIdentityCount: Int
    package var claudePrefetchInFlightCount: Int
    package var pollTaskCount: Int
    package var enabledProviderCount: Int
    package var providerErrorCount: Int
    package var consecutiveFailureTotal: Int

    package init(
        residentSizeBytes: UInt64?,
        snapshotCount: Int,
        codexProfileCount: Int,
        codexSlotCount: Int,
        claudeProfileCount: Int,
        claudeSlotCount: Int,
        codexPrefetchAttemptedIdentityCount: Int,
        codexPrefetchInFlightCount: Int,
        claudePrefetchAttemptedIdentityCount: Int,
        claudePrefetchInFlightCount: Int,
        pollTaskCount: Int,
        enabledProviderCount: Int,
        providerErrorCount: Int,
        consecutiveFailureTotal: Int
    ) {
        self.residentSizeBytes = residentSizeBytes
        self.snapshotCount = snapshotCount
        self.codexProfileCount = codexProfileCount
        self.codexSlotCount = codexSlotCount
        self.claudeProfileCount = claudeProfileCount
        self.claudeSlotCount = claudeSlotCount
        self.codexPrefetchAttemptedIdentityCount = codexPrefetchAttemptedIdentityCount
        self.codexPrefetchInFlightCount = codexPrefetchInFlightCount
        self.claudePrefetchAttemptedIdentityCount = claudePrefetchAttemptedIdentityCount
        self.claudePrefetchInFlightCount = claudePrefetchInFlightCount
        self.pollTaskCount = pollTaskCount
        self.enabledProviderCount = enabledProviderCount
        self.providerErrorCount = providerErrorCount
        self.consecutiveFailureTotal = consecutiveFailureTotal
    }
}

package enum RuntimeMemoryProbe {
    package static func residentSizeBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let status: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }

        guard status == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.resident_size)
    }
}
