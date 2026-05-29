import XCTest
@testable import OhMyUsage

final class RelayDescriptorPreviewBuilderTests: XCTestCase {
    func testBuildNormalizesBaseURLAndPreservesExistingNameWhenDraftNameBlank() {
        let builder = RelayDescriptorPreviewBuilder()
        var provider = ProviderDescriptor.makeOpenRelay(
            name: "Relay Existing",
            baseURL: "https://relay-preview.example.com/root"
        )
        provider.id = "relay-preview-builder"
        let providers = [provider]
        let draft = RelaySettingsDraft(
            providerID: provider.id,
            name: "   ",
            baseURL: "relay-preview.example.com/path?query=1",
            preferredAdapterID: "generic-newapi",
            balanceCredentialMode: .manualPreferred,
            tokenUsageEnabled: true,
            accountEnabled: true,
            authHeader: "Authorization",
            authScheme: "Bearer",
            userID: "",
            userIDHeader: "New-Api-User",
            endpointPath: "/api/user/self",
            remainingJSONPath: "data.quota",
            usedJSONPath: "",
            limitJSONPath: "",
            successJSONPath: "",
            unit: "USD",
            quotaDisplayMode: .remaining,
            showExpirationTimeInMenuBar: false
        )

        let preview = builder.build(draft: draft, providers: providers)

        XCTAssertEqual(preview?.name, "Relay Existing")
        XCTAssertEqual(preview?.baseURL, "https://relay-preview.example.com")
        XCTAssertEqual(preview?.relayConfig?.baseURL, "https://relay-preview.example.com")
        XCTAssertEqual(preview?.relayConfig?.adapterID, "generic-newapi")
        XCTAssertEqual(preview?.relayConfig?.showExpirationTimeInMenuBar, false)
    }
}
