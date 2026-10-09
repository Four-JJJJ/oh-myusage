import Foundation
import OhMyUsageDomain
import OhMyUsageProviders
import XCTest
@testable import OhMyUsage

final class RelayResponseInterpreterFailureTests: XCTestCase {
    func testDisplayConversionPropagatesCancellationAndRateLimit() async throws {
        let deadline = Date(timeIntervalSince1970: 2_000_000_000)
        for failure: Error in [CancellationError(), ProviderRateLimitError(retryNotBefore: deadline)] {
            do {
                _ = try await interpret { _, _, _, _ in throw failure }
                XCTFail("Conversion must not swallow cancellation or a retry deadline")
            } catch let limited as ProviderRateLimitError {
                XCTAssertEqual(limited.retryNotBefore, deadline)
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
        }
    }

    func testOrdinaryDisplayFailureKeepsQuotaWithoutLeakingErrorDetail() async throws {
        let result = try await interpret { _, _, _, _ in
            throw ProviderError.unavailable("secret-placeholder-not-for-diagnostics")
        }
        XCTAssertEqual(result.remaining, 100)
        XCTAssertEqual(result.unit, "quota")
        XCTAssertEqual(result.rawMeta["quotaDisplayStatusError"], "display conversion unavailable")
    }

    private func interpret(requestJSON: @escaping RelayResponseInterpreter.JSONRequest) async throws -> AccountChannelResult {
        let manifest = RelayAdapterRegistry.genericManifest
        let request = ResolvedRelayRequest(
            method: "GET", path: "/api/user/self", bodyJSON: nil, staticHeaders: [:],
            userID: nil, userIDHeader: "New-Api-User", authHeader: nil, authScheme: nil,
            successExpression: nil, remainingExpression: "data.quota", usedExpression: nil,
            limitExpression: nil, unitExpression: nil, accountLabelExpression: nil
        )
        return try await RelayResponseInterpreter.extractAccountValues(
            root: ["data": ["quota": 100]], baseURL: URL(string: "https://example.test")!,
            request: request, manifest: manifest, headers: [:],
            candidate: RelayCredentialCandidate(headers: [:], source: "fixture", persistedCredential: nil),
            requestJSON: requestJSON
        )
    }
}
