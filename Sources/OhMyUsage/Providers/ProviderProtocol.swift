import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch() async throws -> UsageSnapshot
    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot
}

extension UsageProvider {
    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await fetch()
    }
}

struct UsageProviderFetchingAdapter: UsageProviderFetching {
    private let provider: any UsageProvider
    let providerID: UsageProviderIdentity

    init(provider: any UsageProvider) {
        guard let providerID = UsageProviderIdentity(provider.descriptor.id) else {
            preconditionFailure("Provider descriptor id must not be empty")
        }
        self.provider = provider
        self.providerID = providerID
    }

    func fetchUsageSnapshot(forceRefresh: Bool) async throws -> UsageQuotaSnapshot {
        let snapshot = try await provider.fetch(forceRefresh: forceRefresh)
        return UsageQuotaSnapshot(
            used: Self.usedValue(from: snapshot),
            limit: snapshot.limit,
            capturedAtUnixSeconds: snapshot.updatedAt.timeIntervalSince1970
        )
    }

    private static func usedValue(from snapshot: UsageSnapshot) -> Double {
        if let used = snapshot.used {
            return used
        }
        if let limit = snapshot.limit, let remaining = snapshot.remaining {
            return max(0, limit - remaining)
        }
        return 0
    }
}
