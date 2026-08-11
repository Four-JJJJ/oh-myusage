import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class RelayJSONExpressionEvaluatorTests: XCTestCase {
    func testNumericExpressionsSupportCoalesceSumAddAndDiv() {
        let root: [String: Any] = [
            "data": [
                "items": [
                    ["remaining": 1.5],
                    ["remaining": "2.5"],
                    ["ignored": "x"]
                ],
                "used": 3,
                "limit": 10
            ]
        ]

        XCTAssertEqual(
            RelayJSONExpressionEvaluator.numericValue(for: "sum(data.items.*.remaining)", in: root),
            4
        )
        XCTAssertEqual(
            RelayJSONExpressionEvaluator.numericValue(for: "add(data.used,div(data.limit,2),missing.path)", in: root),
            8
        )
        XCTAssertEqual(
            RelayJSONExpressionEvaluator.numericValue(for: "coalesce(data.missing,data.used)", in: root),
            3
        )
        XCTAssertNil(
            RelayJSONExpressionEvaluator.numericValue(for: "div(data.used,0)", in: root)
        )
    }

    func testStringAndBoolExpressionsSupportLiteralsAndCoalesce() {
        let root: [String: Any] = [
            "data": [
                "name": "  Alice  ",
                "count": 7,
                "enabled": "ok",
                "disabled": "no"
            ]
        ]

        XCTAssertEqual(
            RelayJSONExpressionEvaluator.stringValue(for: "data.name", in: root),
            "Alice"
        )
        XCTAssertEqual(
            RelayJSONExpressionEvaluator.stringValue(for: "\"CNY\"", in: root),
            "CNY"
        )
        XCTAssertEqual(
            RelayJSONExpressionEvaluator.stringValue(for: "coalesce(data.missing,data.count)", in: root),
            "7"
        )
        XCTAssertEqual(
            RelayJSONExpressionEvaluator.boolValue(for: "data.enabled", in: root),
            true
        )
        XCTAssertEqual(
            RelayJSONExpressionEvaluator.boolValue(for: "data.disabled", in: root),
            false
        )
    }

    func testNestedRecursiveLookupAndWildcardValues() {
        let root: [String: Any] = [
            "data": [
                "profile": [
                    "wallet": [
                        "availableBalance": "42.5"
                    ]
                ],
                "items": [
                    ["cost": 1],
                    ["cost": 2],
                    ["cost": 3]
                ]
            ]
        ]

        XCTAssertEqual(
            RelayJSONExpressionEvaluator.firstNestedNumericValue(
                for: ["missing", "availableBalance"],
                in: root
            ),
            42.5
        )
        XCTAssertEqual(
            RelayJSONExpressionEvaluator.values(at: "data.items.*.cost", in: root).count,
            3
        )
        XCTAssertEqual(
            RelayJSONExpressionEvaluator.numericValue(for: "sum(data.items.*.cost)", in: root),
            6
        )
    }
}
