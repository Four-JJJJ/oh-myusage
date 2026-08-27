import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class AppProviderCredentialCoordinatorTests: XCTestCase {
    func testSaveTokenNormalizesAndPersistsCredential() {
        let coordinator = AppProviderCredentialCoordinator()
        var descriptor = ProviderDescriptor.defaultOpenAilinyu()
        descriptor.auth = AuthConfig(
            kind: .bearer,
            keychainService: "service",
            keychainAccount: "account"
        )
        var captured: (value: String, service: String, account: String)?

        let outcome = coordinator.saveToken(
            " token ",
            descriptor: descriptor,
            normalize: { token, _ in token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() },
            saveCredential: { value, service, account in
                captured = (value, service, account)
                return true
            }
        )

        XCTAssertEqual(captured?.value, "TOKEN")
        XCTAssertEqual(captured?.service, "service")
        XCTAssertEqual(captured?.account, "account")
        XCTAssertEqual(
            outcome,
            AppCredentialMutationOutcome(
                didPersistCredential: true,
                shouldBumpLookupVersion: true
            )
        )
    }

    func testSaveOfficialManualCookieRejectsBlankInput() {
        let coordinator = AppProviderCredentialCoordinator()
        let providers = [ProviderDescriptor.defaultOfficialOllamaCloud()]

        let outcome = coordinator.saveOfficialManualCookie(
            "   ",
            providerID: providers[0].id,
            providers: providers,
            saveCredential: { _, _, _ in
                XCTFail("blank input should not persist")
                return false
            }
        )

        XCTAssertEqual(outcome, .none)
    }

    func testInvalidateLookupCacheRequestsVersionBump() {
        let coordinator = AppProviderCredentialCoordinator()
        var invalidated = false

        let outcome = coordinator.invalidateLookupCache {
            invalidated = true
        }

        XCTAssertTrue(invalidated)
        XCTAssertEqual(
            outcome,
            AppCredentialMutationOutcome(
                didPersistCredential: false,
                shouldBumpLookupVersion: true
            )
        )
    }

    // MARK: - 单一保存入口 saveCredential(field:...)

    func testSaveCredentialProviderTokenWritesDescriptorAuthSlot() {
        let coordinator = AppProviderCredentialCoordinator()
        var descriptor = ProviderDescriptor.defaultOpenAilinyu()
        descriptor.auth = AuthConfig(
            kind: .bearer,
            keychainService: "svc-token",
            keychainAccount: "acct-token"
        )
        var captured: (value: String, service: String, account: String)?

        let outcome = coordinator.saveCredential(
            field: .providerToken(descriptor),
            value: "abc",
            providers: [],
            normalize: { value, _ in value },
            saveCredential: { value, service, account in
                captured = (value, service, account)
                return true
            }
        )

        XCTAssertEqual(captured?.service, "svc-token")
        XCTAssertEqual(captured?.account, "acct-token")
        XCTAssertEqual(captured?.value, "abc")
        XCTAssertEqual(outcome, AppCredentialMutationOutcome(didPersistCredential: true, shouldBumpLookupVersion: true))
    }

    func testSaveCredentialAuthTokenWritesAuthSlot() {
        let coordinator = AppProviderCredentialCoordinator()
        let auth = AuthConfig(kind: .bearer, keychainService: "svc-auth", keychainAccount: "acct-auth")
        var captured: (value: String, service: String, account: String)?

        let outcome = coordinator.saveCredential(
            field: .authToken(auth),
            value: "xyz",
            providers: [],
            normalize: { value, _ in value },
            saveCredential: { value, service, account in
                captured = (value, service, account)
                return true
            }
        )

        XCTAssertEqual(captured?.service, "svc-auth")
        XCTAssertEqual(captured?.account, "acct-auth")
        XCTAssertEqual(captured?.value, "xyz")
        XCTAssertEqual(outcome, AppCredentialMutationOutcome(didPersistCredential: true, shouldBumpLookupVersion: true))
    }

    func testSaveCredentialOfficialManualCookieUsesDefaultServiceAndManualCookieAccount() {
        let coordinator = AppProviderCredentialCoordinator()
        let providers = [ProviderDescriptor.defaultOfficialOllamaCloud()]
        let expectedAccount = providers[0].officialConfig?.manualCookieAccount
        var captured: (value: String, service: String, account: String)?

        let outcome = coordinator.saveCredential(
            field: .officialManualCookie(providerID: providers[0].id),
            value: " session=abc ",
            providers: providers,
            normalize: { value, _ in value },
            saveCredential: { value, service, account in
                captured = (value, service, account)
                return true
            }
        )

        XCTAssertEqual(captured?.service, KeychainService.defaultServiceName)
        XCTAssertEqual(captured?.account, expectedAccount)
        XCTAssertEqual(captured?.value, "session=abc")
        XCTAssertEqual(outcome, AppCredentialMutationOutcome(didPersistCredential: true, shouldBumpLookupVersion: true))
    }

    func testSaveCredentialSkipsWhenKeychainSlotMissing() {
        let coordinator = AppProviderCredentialCoordinator()
        var descriptor = ProviderDescriptor.defaultOpenAilinyu()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: nil, keychainAccount: nil)

        let outcome = coordinator.saveCredential(
            field: .providerToken(descriptor),
            value: "abc",
            providers: [],
            normalize: { value, _ in value },
            saveCredential: { _, _, _ in
                XCTFail("missing keychain slot should not persist")
                return false
            }
        )

        XCTAssertEqual(outcome, .none)
    }

    func testSaveCredentialOfficialManualCookieRejectsNonOfficialProvider() {
        let coordinator = AppProviderCredentialCoordinator()
        let providers = [ProviderDescriptor.defaultOpenAilinyu()]

        let outcome = coordinator.saveCredential(
            field: .officialManualCookie(providerID: providers[0].id),
            value: "session=abc",
            providers: providers,
            normalize: { value, _ in value },
            saveCredential: { _, _, _ in
                XCTFail("non-official provider should not persist manual cookie")
                return false
            }
        )

        XCTAssertEqual(outcome, .none)
    }

    // MARK: - wrapper 与单一入口行为一致

    func testLegacyWrappersMatchSaveCredentialEntry() {
        let coordinator = AppProviderCredentialCoordinator()
        var descriptor = ProviderDescriptor.defaultOpenAilinyu()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: "svc", keychainAccount: "acct")
        let providers = [ProviderDescriptor.defaultOfficialOllamaCloud()]
        let normalize: (String, AuthKind) -> String = { value, _ in value }

        var legacyCaptured: (String, String, String)?
        let legacyOutcome = coordinator.saveToken(
            "v",
            descriptor: descriptor,
            normalize: normalize,
            saveCredential: { value, service, account in
                legacyCaptured = (value, service, account)
                return true
            }
        )
        var unifiedCaptured: (String, String, String)?
        let unifiedOutcome = coordinator.saveCredential(
            field: .providerToken(descriptor),
            value: "v",
            providers: [],
            normalize: normalize,
            saveCredential: { value, service, account in
                unifiedCaptured = (value, service, account)
                return true
            }
        )
        XCTAssertEqual(legacyOutcome, unifiedOutcome)
        XCTAssertEqual(legacyCaptured?.0, unifiedCaptured?.0)
        XCTAssertEqual(legacyCaptured?.1, unifiedCaptured?.1)
        XCTAssertEqual(legacyCaptured?.2, unifiedCaptured?.2)

        var legacyCookieCaptured: (String, String, String)?
        let legacyCookieOutcome = coordinator.saveOfficialManualCookie(
            "v",
            providerID: providers[0].id,
            providers: providers,
            saveCredential: { value, service, account in
                legacyCookieCaptured = (value, service, account)
                return true
            }
        )
        var unifiedCookieCaptured: (String, String, String)?
        let unifiedCookieOutcome = coordinator.saveCredential(
            field: .officialManualCookie(providerID: providers[0].id),
            value: "v",
            providers: providers,
            normalize: normalize,
            saveCredential: { value, service, account in
                unifiedCookieCaptured = (value, service, account)
                return true
            }
        )
        XCTAssertEqual(legacyCookieOutcome, unifiedCookieOutcome)
        XCTAssertEqual(legacyCookieCaptured?.0, unifiedCookieCaptured?.0)
        XCTAssertEqual(legacyCookieCaptured?.1, unifiedCookieCaptured?.1)
        XCTAssertEqual(legacyCookieCaptured?.2, unifiedCookieCaptured?.2)
    }
}
