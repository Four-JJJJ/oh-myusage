import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class DragonProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor

    init(descriptor: ProviderDescriptor) {
        self.descriptor = descriptor
    }

    func fetch() async throws -> UsageSnapshot {
        throw ProviderError.unavailable("Dragon provider reserved for v2. Add browser auth_token + /api/v1 adapter next.")
    }
}
