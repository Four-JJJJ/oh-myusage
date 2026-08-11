import OhMyUsageApplication
import OhMyUsageDomain
import OhMyUsageFeatures
import OhMyUsagePresentation

/// Pure Usage composition root for layered targets.
///
/// Responsibilities stop at Usage feature descriptors / refresh requests / summary view state.
/// Executable menu-bar host dependency wiring belongs in `AppCompositionFactory` /
/// `AppDependencyGraph` inside the `OhMyUsage` executable. This module must not import
/// `OhMyUsage` or claim complete runtime integration.
public struct OhMyUsageCompositionRoot: Sendable {
    public let featureAssembly: UsageFeatureAssembly

    public init(featureAssembly: UsageFeatureAssembly = UsageFeatureAssembly()) {
        self.featureAssembly = featureAssembly
    }

    public func makeUsageFeatureDescriptor(
        providerID: UsageProviderIdentity,
        title: String,
        defaultForceRefresh: Bool = false
    ) -> UsageFeatureDescriptor {
        featureAssembly.makeUsageFeatureDescriptor(
            providerID: providerID,
            title: title,
            defaultForceRefresh: defaultForceRefresh
        )
    }

    public func makeUsageRefreshRequest(
        for descriptor: UsageFeatureDescriptor,
        forceRefresh: Bool? = nil
    ) -> UsageRefreshRequest {
        featureAssembly.makeRefreshRequest(for: descriptor, forceRefresh: forceRefresh)
    }

    public func makeUsageRefreshRequest(
        providerID: UsageProviderIdentity,
        forceRefresh: Bool = false
    ) -> UsageRefreshRequest {
        featureAssembly.makeRefreshRequest(providerID: providerID, forceRefresh: forceRefresh)
    }

    public func makeUsageSummaryViewState(
        for descriptor: UsageFeatureDescriptor,
        snapshot: UsageQuotaSnapshot
    ) -> UsageProviderSummaryViewState {
        featureAssembly.makeSummaryViewState(for: descriptor, snapshot: snapshot)
    }

    public func makeUsageSummaryViewState(
        providerID: UsageProviderIdentity,
        title: String,
        snapshot: UsageQuotaSnapshot
    ) -> UsageProviderSummaryViewState {
        featureAssembly.makeSummaryViewState(
            providerID: providerID,
            title: title,
            snapshot: snapshot
        )
    }
}
