import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

@MainActor
final class AppViewModelRelayDraftDiagnosticsTests: XCTestCase {
    func testImportRelayDraftFromBrowserUsesBrowserPreferredCredentialMode() async {
        var provider = ProviderDescriptor.makeOpenRelay(
            name: "Relay Import",
            baseURL: "https://relay-import.dev"
        )
        provider.id = "relay-browser-import"
        let recorder = RelayDraftDescriptorRecorder()
        let viewModel = AppViewModel(
            testingConfig: AppConfig(providers: [provider]),
            appUpdateService: NoopRelayDraftDiagnosticsAppUpdateService(),
            providerFactory: RelayDraftDiagnosticsProviderFactory(
                recorder: recorder,
                snapshot: Self.sampleSnapshot(source: provider.id)
            )
        )
        let draft = RelaySettingsDraft(provider: provider)

        let result = await viewModel.importRelayDraftFromBrowser(draft)

        XCTAssertTrue(result.success)
        let descriptor = recorder.lastDescriptor()
        XCTAssertEqual(descriptor?.relayConfig?.balanceCredentialMode, .browserPreferred)
    }

    private static func sampleSnapshot(source: String) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: 88,
            used: 12,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "ok",
            sourceLabel: "Relay"
        )
    }
}

private struct RelayDraftDiagnosticsProviderFactory: ProviderFactorying {
    let recorder: RelayDraftDescriptorRecorder
    let snapshot: UsageSnapshot

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        recorder.record(descriptor)
        return RelayDraftDiagnosticsUsageProvider(descriptor: descriptor, snapshot: snapshot)
    }
}

private struct RelayDraftDiagnosticsUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let snapshot: UsageSnapshot

    func fetch() async throws -> UsageSnapshot {
        snapshot
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        snapshot
    }
}

private final class RelayDraftDescriptorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: ProviderDescriptor?

    func record(_ descriptor: ProviderDescriptor) {
        lock.lock()
        self.descriptor = descriptor
        lock.unlock()
    }

    func lastDescriptor() -> ProviderDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        return descriptor
    }
}

private actor NoopRelayDraftDiagnosticsAppUpdateService: AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        throw ProviderError.unavailable("unused")
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        throw ProviderError.unavailable("unused")
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL) throws {}
}
