import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

@MainActor
final class AppProviderRefreshCoordinatorTests: XCTestCase {
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
