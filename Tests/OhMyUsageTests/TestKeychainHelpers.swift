import Foundation
import OhMyUsageProviders
@testable import OhMyUsage

func makeTestKeychain(fileManager: FileManager = .default) -> KeychainService {
    KeychainService(storageURL: makeTestKeychainStorageURL(fileManager: fileManager))
}

func makeTestKeychainStorageURL(fileManager: FileManager = .default) -> URL {
    fileManager.temporaryDirectory
        .appendingPathComponent("OhMyUsageTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("keychain.json")
}

/// `TokenCredentialStoring` stub whose writes always fail (used to exercise
/// vault write failure paths).
final class FailingTokenCredentialStore: TokenCredentialStoring, @unchecked Sendable {
    func readToken(service: String, account: String) -> String? {
        nil
    }

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool {
        false
    }

    @discardableResult
    func deleteToken(service: String, account: String) -> Bool {
        true
    }
}

/// Isolated `UserDefaults` domain for tests that touch migration markers.
/// Call `removeTestDefaults(named:)` when the test finishes.
func makeTestDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "OhMyUsageTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return (UserDefaults.standard, "")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

func removeTestDefaults(named suiteName: String) {
    guard !suiteName.isEmpty else { return }
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
}
