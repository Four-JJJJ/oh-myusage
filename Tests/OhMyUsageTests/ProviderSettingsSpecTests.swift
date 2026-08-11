import XCTest
@testable import OhMyUsage

final class ProviderSettingsSpecTests: XCTestCase {
    func testTraeSpecUsesAuthorizationCredentialAndAmountToggle() {
        let spec = ProviderSettingsSpec.resolve(for: ProviderDescriptor.defaultOfficialTrae())

        XCTAssertEqual(spec.providerType, .trae)
        XCTAssertEqual(spec.credentialFields.map(\.kind), [.traeAuthorization])
        XCTAssertTrue(spec.showsQuotaDisplayPreference)
        XCTAssertTrue(spec.showsTraeValueDisplayMode)
    }

    func testOpenCodeGoSpecUsesWorkspaceAndCookieCredentials() {
        let spec = ProviderSettingsSpec.resolve(for: ProviderDescriptor.defaultOfficialOpenCodeGo())

        XCTAssertEqual(spec.providerType, .opencodeGo)
        XCTAssertEqual(spec.credentialFields.map(\.kind), [.opencodeWorkspaceID, .opencodeManualCookie])
        XCTAssertEqual(spec.supportedSourceModes, [.auto, .web])
        XCTAssertEqual(spec.supportedWebModes, [.disabled, .autoImport, .manual])
    }

    func testOpenRouterAPISpecUsesBearerCredential() {
        let spec = ProviderSettingsSpec.resolve(for: ProviderDescriptor.defaultOfficialOpenRouterAPI())

        XCTAssertEqual(spec.credentialFields.map(\.kind), [.bearerToken])
        XCTAssertEqual(spec.credentialFields.first?.storageTarget, .providerToken)
    }

    func testKimiSpecAcceptsCodingPlanAPIKey() {
        let spec = ProviderSettingsSpec.resolve(for: ProviderDescriptor.defaultOfficialKimi())

        XCTAssertEqual(spec.credentialFields.map(\.kind), [.bearerToken])
        XCTAssertEqual(spec.credentialFields.first?.storageTarget, .providerToken)
    }

    func testClaudeSpecUsesManualCookieCredential() {
        let spec = ProviderSettingsSpec.resolve(for: ProviderDescriptor.defaultOfficialClaude())

        XCTAssertEqual(spec.credentialFields.map(\.kind), [.manualCookie])
        XCTAssertEqual(spec.credentialFields.first?.storageTarget, .officialManualCookie)
    }

    func testAutoAPIProviderSpecHasNoCredentialFields() {
        let spec = ProviderSettingsSpec.resolve(for: ProviderDescriptor.defaultOfficialGemini())

        XCTAssertEqual(spec.supportedSourceModes, [.auto, .api])
        XCTAssertEqual(spec.supportedWebModes, [.disabled])
        XCTAssertTrue(spec.credentialFields.isEmpty)
    }
}
