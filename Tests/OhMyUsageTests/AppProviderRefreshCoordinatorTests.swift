import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

@MainActor
final class AppProviderRefreshCoordinatorTests: XCTestCase {
    func testDisplayedProvidersForStartupRefreshOnlyIncludesMissingStaleOrEmptySnapshots() {
        var freshProvider = ProviderDescriptor.defaultOfficialGemini()
        freshProvider.id = "fresh"
        freshProvider.enabled = true
        freshProvider.pollIntervalSec = 300

        var staleProvider = ProviderDescriptor.defaultOfficialGemini()
        staleProvider.id = "stale"
        staleProvider.enabled = true
        staleProvider.pollIntervalSec = 300

        var missingProvider = ProviderDescriptor.defaultOfficialGemini()
        missingProvider.id = "missing"
        missingProvider.enabled = true

        var emptyProvider = ProviderDescriptor.defaultOfficialGemini()
        emptyProvider.id = "empty"
        emptyProvider.enabled = true

        var disabledProvider = ProviderDescriptor.defaultOfficialGemini()
        disabledProvider.id = "disabled"
        disabledProvider.enabled = false

        let now = Date()
        let snapshots: [String: UsageSnapshot] = [
            // Updated 10s ago with a 300s poll interval: fresh enough to keep.
            freshProvider.id: Self.startupSnapshot(source: freshProvider.id, updatedAt: now.addingTimeInterval(-10)),
            // Updated 400s ago: stale, needs a startup refresh.
            staleProvider.id: Self.startupSnapshot(source: staleProvider.id, updatedAt: now.addingTimeInterval(-400)),
            // Empty placeholder (e.g. previous offline failure): always refresh.
            emptyProvider.id: UsageSnapshot(
                source: emptyProvider.id,
                status: .error,
                fetchHealth: .unreachable,
                valueFreshness: .empty,
                remaining: nil,
                used: nil,
                limit: nil,
                unit: "%",
                updatedAt: now.addingTimeInterval(-5),
                note: "offline",
                sourceLabel: "Official"
            )
        ]

        let providers = makeCoordinator().displayedProvidersForStartupRefresh(
            providers: [freshProvider, staleProvider, missingProvider, emptyProvider, disabledProvider],
            snapshots: snapshots,
            now: now
        )

        XCTAssertEqual(
            Set(providers.map(\.id)),
            ["stale", "missing", "empty"],
            "Startup refresh must be limited to displayed providers that are missing, stale, or empty"
        )
    }

    func testFetchFailureRetainsPreviousSnapshotAsCachedFallback() async throws {
        var descriptor = ProviderDescriptor.makeOpenRelay(
            name: "Failing Relay",
            baseURL: "https://failing-retention.test"
        )
        descriptor.id = "failing-relay"
        descriptor.enabled = true

        let stateBox = CoordinatorRefreshStateBox()
        let previousUpdatedAt = Date().addingTimeInterval(-120)
        stateBox.state.snapshots[descriptor.id] = UsageSnapshot(
            source: descriptor.id,
            status: .ok,
            remaining: 77,
            used: 23,
            limit: 100,
            unit: "%",
            updatedAt: previousUpdatedAt,
            note: "ok",
            sourceLabel: "Test"
        )

        let coordinator = AppProviderRefreshCoordinator(
            providerFactory: FailingProviderFactory(),
            notifications: NotificationService()
        )

        await coordinator.refreshProvider(
            descriptor: descriptor,
            forceRefresh: false,
            getState: { stateBox.state },
            setState: { stateBox.state = $0 },
            beforeRefresh: { _ in },
            transformFetchedSnapshot: { _, fetched in fetched },
            postOfficialRefresh: { _, _ in },
            persistBaselineEntries: { _ in },
            afterRefresh: {},
            notifyStatusBarDisplayConfigChanged: {},
            text: { _ in "" },
            localizedText: { zhHans, _ in zhHans },
            language: { .en },
            boundedSnapshot: { $0 }
        )

        let retained = try XCTUnwrap(stateBox.state.snapshots[descriptor.id], "Network failure must not clear the previous snapshot")
        XCTAssertEqual(retained.remaining, 77)
        XCTAssertEqual(retained.used, 23)
        XCTAssertEqual(retained.limit, 100)
        XCTAssertEqual(retained.valueFreshness, .cachedFallback)
        XCTAssertEqual(retained.fetchHealth, .unreachable)
    }

    func testRefreshProviderPersistsSnapshotAfterSuccessfulFetch() async throws {
        var descriptor = ProviderDescriptor.defaultOfficialGemini()
        descriptor.id = "persist-hook-provider"
        descriptor.enabled = true
        descriptor.family = .thirdParty

        let stateBox = CoordinatorRefreshStateBox()
        let recorder = CoordinatorPersistRecorder()
        let coordinator = AppProviderRefreshCoordinator(
            providerFactory: StaticProviderFactory(),
            notifications: NotificationService()
        )

        await coordinator.refreshProvider(
            descriptor: descriptor,
            forceRefresh: false,
            getState: { stateBox.state },
            setState: { stateBox.state = $0 },
            beforeRefresh: { _ in },
            transformFetchedSnapshot: { _, fetched in fetched },
            postOfficialRefresh: { _, _ in },
            persistBaselineEntries: { _ in },
            persistSnapshot: { descriptor, snapshot in
                recorder.record(providerID: descriptor.id, remaining: snapshot.remaining)
            },
            afterRefresh: {},
            notifyStatusBarDisplayConfigChanged: {},
            text: { _ in "" },
            localizedText: { zhHans, _ in zhHans },
            language: { .en },
            boundedSnapshot: { $0 }
        )

        let events = recorder.snapshot()
        XCTAssertEqual(events, ["persist-hook-provider:42"])
        XCTAssertEqual(stateBox.state.snapshots[descriptor.id]?.remaining, 42)
    }

    private static func startupSnapshot(source: String, updatedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            source: source,
            status: .ok,
            remaining: 50,
            used: 50,
            limit: 100,
            unit: "%",
            updatedAt: updatedAt,
            note: "ok",
            sourceLabel: "Test"
        )
    }

    func testRefreshDisplayedStatusBarProvidersSkipsDisabledAndDeduplicatesSameID() async throws {
        var first = ProviderDescriptor.defaultOfficialCodex()
        first.id = "first"
        first.enabled = true
        var disabled = ProviderDescriptor.defaultOfficialClaude()
        disabled.id = "disabled"
        disabled.enabled = false
        var second = ProviderDescriptor.defaultOfficialGemini()
        second.id = "second"
        second.enabled = true
        var duplicateFirst = ProviderDescriptor.defaultOfficialCodex()
        duplicateFirst.id = "first"
        duplicateFirst.enabled = true

        let recorder = CoordinatorRefreshRecorder()
        let coordinator = makeCoordinator()

        coordinator.refreshDisplayedStatusBarProviders(
            providers: [first, disabled, second, duplicateFirst],
            forceRefresh: true
        ) { descriptor, forceRefresh in
            await recorder.record(providerID: descriptor.id, forceRefresh: forceRefresh)
        }

        try await waitUntil {
            await recorder.snapshot().count == 2
        }
        let events = await recorder.snapshot()
        XCTAssertEqual(Set(events), ["first:true", "second:true"])
    }

    func testRefreshDisplayedStatusBarProvidersDoesNotBlockOtherProvidersWhenOneRefreshIsStillRunning() async throws {
        var first = ProviderDescriptor.defaultOfficialCodex()
        first.id = "first"
        first.enabled = true
        var second = ProviderDescriptor.defaultOfficialClaude()
        second.id = "second"
        second.enabled = true

        let refreshGate = CoordinatorBlockingRefreshGate()
        let coordinator = makeCoordinator()

        coordinator.refreshDisplayedStatusBarProviders(
            providers: [first, second],
            forceRefresh: false
        ) { descriptor, forceRefresh in
            await refreshGate.refresh(providerID: descriptor.id, forceRefresh: forceRefresh)
        }

        try await waitUntil {
            let events = await refreshGate.snapshot()
            return Set(events) == ["first:false", "second:false"]
        }

        await refreshGate.releaseAll()
    }

    func testRunExclusiveRefreshJoinsInFlightWorkForSameProviderID() async throws {
        let gate = CoordinatorBlockingRefreshGate()
        let coordinator = makeCoordinator()
        let callCount = ExclusiveRefreshCallCounter()

        let first = Task { @MainActor in
            await coordinator.runExclusiveRefresh(providerID: "same") {
                await callCount.increment()
                await gate.refresh(providerID: "same", forceRefresh: false)
            }
        }
        try await waitUntil {
            await callCount.value() == 1
        }

        let second = Task { @MainActor in
            await coordinator.runExclusiveRefresh(providerID: "same") {
                await callCount.increment()
                await gate.refresh(providerID: "same", forceRefresh: true)
            }
        }

        // Second call must join the first; action body must not run twice.
        try await Task.sleep(nanoseconds: 50_000_000)
        let overlappingCount = await callCount.value()
        XCTAssertEqual(overlappingCount, 1)

        await gate.releaseAll()
        await first.value
        await second.value
        let finalCount = await callCount.value()
        XCTAssertEqual(finalCount, 1)
    }

    func testRunExclusiveRefreshAllowsConcurrentWorkForDifferentProviderIDs() async throws {
        let gate = CoordinatorBlockingRefreshGate()
        let coordinator = makeCoordinator()

        let first = Task { @MainActor in
            await coordinator.runExclusiveRefresh(providerID: "first") {
                await gate.refresh(providerID: "first", forceRefresh: false)
            }
        }
        let second = Task { @MainActor in
            await coordinator.runExclusiveRefresh(providerID: "second") {
                await gate.refresh(providerID: "second", forceRefresh: false)
            }
        }

        try await waitUntil {
            let events = await gate.snapshot()
            return Set(events) == ["first:false", "second:false"]
        }

        await gate.releaseAll()
        await first.value
        await second.value
    }

    func testRefreshProviderDeduplicatesInFlightFetchesForSameProviderID() async throws {
        var descriptor = ProviderDescriptor.defaultOfficialGemini()
        descriptor.id = "dedupe-provider"
        descriptor.enabled = true
        descriptor.family = .thirdParty
        let providerID = descriptor.id

        let fetchGate = CoordinatorFetchGate()
        let factory = CountingProviderFactory(gate: fetchGate)
        let coordinator = AppProviderRefreshCoordinator(
            providerFactory: factory,
            notifications: NotificationService()
        )
        let stateBox = CoordinatorRefreshStateBox()

        let first = Task { @MainActor in
            await coordinator.refreshProvider(
                descriptor: descriptor,
                forceRefresh: false,
                getState: { stateBox.state },
                setState: { stateBox.state = $0 },
                beforeRefresh: { _ in },
                transformFetchedSnapshot: { _, fetched in fetched },
                postOfficialRefresh: { _, _ in },
                persistBaselineEntries: { _ in },
                afterRefresh: {},
                notifyStatusBarDisplayConfigChanged: {},
                text: { _ in "" },
                localizedText: { zhHans, _ in zhHans },
                language: { .en },
                boundedSnapshot: { $0 }
            )
        }

        try await waitUntil {
            await fetchGate.fetchCount() == 1
        }

        let second = Task { @MainActor in
            await coordinator.refreshProvider(
                descriptor: descriptor,
                forceRefresh: true,
                getState: { stateBox.state },
                setState: { stateBox.state = $0 },
                beforeRefresh: { _ in },
                transformFetchedSnapshot: { _, fetched in fetched },
                postOfficialRefresh: { _, _ in },
                persistBaselineEntries: { _ in },
                afterRefresh: {},
                notifyStatusBarDisplayConfigChanged: {},
                text: { _ in "" },
                localizedText: { zhHans, _ in zhHans },
                language: { .en },
                boundedSnapshot: { $0 }
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let overlappingFetchCount = await fetchGate.fetchCount()
        XCTAssertEqual(overlappingFetchCount, 1, "Overlapping forceRefresh should await existing in-flight refresh instead of fetching again")

        await fetchGate.release()
        await first.value
        await second.value
        let finalFetchCount = await fetchGate.fetchCount()
        XCTAssertEqual(finalFetchCount, 1)
        XCTAssertEqual(stateBox.state.snapshots[providerID]?.remaining, 42)
    }

    private func makeCoordinator() -> AppProviderRefreshCoordinator {
        AppProviderRefreshCoordinator(
            providerFactory: UnusedProviderFactory(),
            notifications: NotificationService()
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        predicate: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for coordinator refresh state")
    }
}

private struct UnusedProviderFactory: ProviderFactorying {
    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        fatalError("UnusedProviderFactory should not be called in displayed-refresh tests")
    }
}

private actor CoordinatorRefreshRecorder {
    private var events: [String] = []

    func record(providerID: String, forceRefresh: Bool) {
        events.append("\(providerID):\(forceRefresh)")
    }

    func snapshot() -> [String] {
        events
    }
}

private actor CoordinatorBlockingRefreshGate {
    private var events: [String] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func refresh(providerID: String, forceRefresh: Bool) async {
        events.append("\(providerID):\(forceRefresh)")
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func releaseAll() {
        let continuations = continuations
        self.continuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func snapshot() -> [String] {
        events
    }
}

@MainActor
private final class CoordinatorRefreshStateBox {
    var state = ProviderStateStore()
}

private actor ExclusiveRefreshCallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private actor CoordinatorFetchGate {
    private var count = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func beginFetch() async {
        count += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func release() {
        let continuations = continuations
        self.continuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func fetchCount() -> Int {
        count
    }
}

private struct CountingProviderFactory: ProviderFactorying {
    let gate: CoordinatorFetchGate

    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        CountingUsageProvider(descriptor: descriptor, gate: gate)
    }
}

private struct CountingUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    let gate: CoordinatorFetchGate

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        await gate.beginFetch()
        return UsageSnapshot(
            source: descriptor.id,
            status: .ok,
            remaining: 42,
            used: 8,
            limit: 50,
            unit: "%",
            updatedAt: Date(),
            note: "counting",
            sourceLabel: "Test"
        )
    }
}

private struct StaticProviderFactory: ProviderFactorying {
    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        StaticUsageProvider(descriptor: descriptor)
    }
}

private struct StaticUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        UsageSnapshot(
            source: descriptor.id,
            status: .ok,
            remaining: 42,
            used: 8,
            limit: 50,
            unit: "%",
            updatedAt: Date(),
            note: "static",
            sourceLabel: "Test"
        )
    }
}

private struct FailingProviderFactory: ProviderFactorying {
    func makeProvider(for descriptor: ProviderDescriptor) -> UsageProvider {
        FailingUsageProvider(descriptor: descriptor)
    }
}

private struct FailingUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        throw ProviderError.timeout("simulated network timeout")
    }
}

@MainActor
private final class CoordinatorPersistRecorder {
    private var events: [String] = []

    func record(providerID: String, remaining: Double?) {
        let formatted = remaining.map { String(Int($0)) } ?? "nil"
        events.append("\(providerID):\(formatted)")
    }

    func snapshot() -> [String] {
        events
    }
}
