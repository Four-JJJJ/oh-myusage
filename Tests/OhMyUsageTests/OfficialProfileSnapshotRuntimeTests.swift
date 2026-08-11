import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class OfficialProfileSnapshotRuntimeTests: XCTestCase {
    func testRequestWithUnauthorizedRefreshRetriesWithRefreshedState() async throws {
        var requestInputs: [Int] = []

        let result = try await OfficialProfileSnapshotRuntime.requestWithUnauthorizedRefresh(
            initialState: 1,
            request: { value in
                requestInputs.append(value)
                if value == 1 {
                    throw ProviderError.unauthorized
                }
                return "ok-\(value)"
            },
            refresh: { value in
                XCTAssertEqual(value, 1)
                return 2
            }
        )

        XCTAssertEqual(requestInputs, [1, 2])
        XCTAssertEqual(result.state, 2)
        XCTAssertEqual(result.response, "ok-2")
        XCTAssertTrue(result.didRefresh)
    }

    func testMutateJSONObjectStringUpdatesRootObject() throws {
        let updated = try OfficialProfileSnapshotRuntime.mutateJSONObjectString(
            #"{"token":"old"}"#,
            invalidResponseMessage: "invalid"
        ) { root in
            root["token"] = "new"
            root["refreshed"] = true
        }

        let data = try XCTUnwrap(updated.data(using: .utf8))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["token"] as? String, "new")
        XCTAssertEqual(root["refreshed"] as? Bool, true)
    }
}
