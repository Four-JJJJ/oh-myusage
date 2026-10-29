import Foundation
import OhMyUsageProviders
import XCTest
@testable import OhMyUsage

final class CursorSafeStorageTests: XCTestCase {
    private static let sampleJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyfDEyMyIsImV4cCI6NDEwMjQ0NDgwMH0.c2lnbmF0dXJl"

    func testPlainTokenIsReturnedUnchangedWithoutReadingKeychain() {
        let recorder = CursorSafeStorageRecorder()
        let storage = CursorSafeStorage(
            readPassword: {
                recorder.recordPasswordRead()
                return ""
            },
            decrypt: { _, _ in nil }
        )

        XCTAssertEqual(storage.resolveToken("  plain-token\n"), "plain-token")
        XCTAssertEqual(recorder.passwordReadCount, 0)
        XCTAssertEqual(recorder.decryptCount, 0)
    }

    func testEncryptedValueDecryptsToJWTUsingKeychainPassphrase() {
        let recorder = CursorSafeStorageRecorder()
        let jwt = Self.sampleJWT
        let storage = CursorSafeStorage(
            readPassword: { "keychain-passphrase" },
            decrypt: { payload, passphrase in
                recorder.recordDecrypt(payload: payload, passphrase: passphrase)
                return jwt
            }
        )
        let encrypted = CursorSafeStorage.encryptedValuePrefix + "djEwY2lwaGVydGV4dA=="

        XCTAssertTrue(CursorSafeStorage.isEncrypted(encrypted))
        XCTAssertEqual(storage.resolveToken(encrypted), jwt)
        XCTAssertEqual(recorder.decryptPayloads, ["djEwY2lwaGVydGV4dA=="])
        XCTAssertEqual(recorder.decryptPassphrases, ["keychain-passphrase"])
    }

    func testEncryptedValueWithoutKeychainPassphraseResolvesToNil() {
        let storage = CursorSafeStorage(
            readPassword: { throw ProviderError.missingCredential(CursorSafeStorage.keychainService) },
            decrypt: { _, _ in Self.sampleJWT }
        )
        let encrypted = CursorSafeStorage.encryptedValuePrefix + "djEwY2lwaGVydGV4dA=="

        XCTAssertNil(storage.resolveToken(encrypted))
    }

    func testEncryptedValueWithFailingDecryptorResolvesToNil() {
        let storage = CursorSafeStorage(
            readPassword: { "keychain-passphrase" },
            decrypt: { _, _ in nil }
        )
        let encrypted = CursorSafeStorage.encryptedValuePrefix + "not-valid-base64!!"

        XCTAssertNil(storage.resolveToken(encrypted))
    }

    func testDecryptedPlaintextSurroundingJWTIsTrimmedToTheToken() {
        let plaintext = "  cursor-session: \(Self.sampleJWT)  "

        XCTAssertEqual(CursorSafeStorage.token(from: plaintext), Self.sampleJWT)
    }

    func testNonJWTPlaintextIsReturnedTrimmed() {
        XCTAssertEqual(CursorSafeStorage.token(from: "  opaque-refresh-token  "), "opaque-refresh-token")
        XCTAssertNil(CursorSafeStorage.token(from: "   "))
    }
}

private final class CursorSafeStorageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var passwordReads = 0
    private var decryptPayloadList: [String] = []
    private var decryptPassphraseList: [String] = []

    var passwordReadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return passwordReads
    }

    var decryptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return decryptPayloadList.count
    }

    var decryptPayloads: [String] {
        lock.lock()
        defer { lock.unlock() }
        return decryptPayloadList
    }

    var decryptPassphrases: [String] {
        lock.lock()
        defer { lock.unlock() }
        return decryptPassphraseList
    }

    func recordPasswordRead() {
        lock.lock()
        defer { lock.unlock() }
        passwordReads += 1
    }

    func recordDecrypt(payload: String, passphrase: String) {
        lock.lock()
        defer { lock.unlock() }
        decryptPayloadList.append(payload)
        decryptPassphraseList.append(passphrase)
    }
}
