import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class AppProviderCredentialCoordinatorTests: XCTestCase {
    func testSaveCredentialProviderTokenNormalizesAndPersistsCredential() {
        let coordinator = AppProviderCredentialCoordinator()
        var descriptor = ProviderDescriptor.defaultOpenAilinyu()
        descriptor.auth = AuthConfig(
            kind: .bearer,
            keychainService: "service",
            keychainAccount: "account"
        )
        var captured: (value: String, service: String, account: String)?

        let outcome = coordinator.saveCredential(
            field: .providerToken(descriptor),
            value: " token ",
            providers: [],
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
        XCTAssertEqual(
            outcome,
            AppCredentialMutationOutcome(didPersistCredential: true, shouldBumpLookupVersion: true)
        )
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
        XCTAssertEqual(
            outcome,
            AppCredentialMutationOutcome(didPersistCredential: true, shouldBumpLookupVersion: true)
        )
    }

    func testSaveCredentialOfficialManualCookieRejectsBlankInput() {
        let coordinator = AppProviderCredentialCoordinator()
        let providers = [ProviderDescriptor.defaultOfficialOllamaCloud()]

        let outcome = coordinator.saveCredential(
            field: .officialManualCookie(providerID: providers[0].id),
            value: "   ",
            providers: providers,
            normalize: { value, _ in value },
            saveCredential: { _, _, _ in
                XCTFail("blank input should not persist")
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
}
