import XCTest
import OhMyUsageProviders

final class HTTPResponseValidationTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeResponse(
        statusCode: Int,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/api")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    // MARK: - Status classification

    func testValidateAccepts2xxJSONResponse() throws {
        let response = makeResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
        XCTAssertNoThrow(
            try HTTPResponseValidation.validate(response, urlDescription: "Test", body: Data(#"{"ok":true}"#.utf8))
        )
    }

    func testValidateMaps401ToUnauthorized() {
        let response = makeResponse(statusCode: 401)
        assertThrows(.unauthorized) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test")
        }
    }

    func testValidateMaps403ToUnauthorizedByDefault() {
        let response = makeResponse(statusCode: 403)
        assertThrows(.unauthorized) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test")
        }
    }

    func testValidateTolerant403FallsThroughToInvalidResponse() {
        let response = makeResponse(statusCode: 403)
        assertThrows(.invalidResponse("Test http 403")) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test", tolerant403: true)
        }
    }

    func testValidateTolerant403WithEmptyDescriptionKeepsBareMessage() {
        let response = makeResponse(statusCode: 403)
        assertThrows(.invalidResponse("http 403")) {
            try HTTPResponseValidation.validate(response, urlDescription: "", tolerant403: true)
        }
    }

    func testValidateMaps429WithoutRetryAfterToRateLimited() {
        let response = makeResponse(statusCode: 429)
        assertThrows(.rateLimited) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test", now: referenceDate)
        }
    }

    func testValidateMaps429WithRetryAfterToProviderRateLimitError() throws {
        let response = makeResponse(statusCode: 429, headers: ["Retry-After": "30"])
        XCTAssertThrowsError(
            try HTTPResponseValidation.validate(response, urlDescription: "Test", now: referenceDate)
        ) { error in
            guard let limited = error as? ProviderRateLimitError else {
                return XCTFail("Expected ProviderRateLimitError, got \(error)")
            }
            XCTAssertEqual(limited.retryNotBefore, referenceDate.addingTimeInterval(30))
        }
    }

    func testValidateMaps408And5xxToTimeout() {
        for statusCode in [408, 500, 503] {
            let response = makeResponse(statusCode: statusCode)
            assertThrows(.timeout("Test http \(statusCode)")) {
                try HTTPResponseValidation.validate(response, urlDescription: "Test")
            }
        }
    }

    func testValidateMapsOtherNon2xxToInvalidResponse() {
        let response = makeResponse(statusCode: 404)
        assertThrows(.invalidResponse("Test http 404")) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test")
        }
    }

    func testValidateSupportsCustomInvalidResponseMessage() {
        let response = makeResponse(statusCode: 404)
        assertThrows(.invalidResponse("refresh http 404")) {
            try HTTPResponseValidation.validate(
                response,
                urlDescription: "Test",
                invalidResponseMessage: { "refresh http \($0)" }
            )
        }
    }

    func testValidateSupportsCustomUnauthorizedStatusCodes() {
        let response = makeResponse(statusCode: 400)
        assertThrows(.unauthorized) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test", unauthorizedStatusCodes: [400, 401])
        }
        // Without the custom set, 400 is a generic invalid status.
        assertThrows(.invalidResponse("Test http 400")) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test")
        }
    }

    func testValidateUnauthorizedMessageHookProducesDetail() {
        let response = makeResponse(statusCode: 401)
        assertThrows(.unauthorizedDetail("token expired")) {
            try HTTPResponseValidation.validate(
                response,
                urlDescription: "Test",
                unauthorizedMessage: { _, _ in "token expired" }
            )
        }
        // An empty message falls back to plain unauthorized.
        assertThrows(.unauthorized) {
            try HTTPResponseValidation.validate(
                response,
                urlDescription: "Test",
                unauthorizedMessage: { _, _ in "" }
            )
        }
    }

    // MARK: - HTML detection

    func testValidateRejectsHTMLContentTypeOn2xx() {
        let response = makeResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"])
        assertThrows(.invalidResponse("Test html response")) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test", body: Data(#"<html><body>x"#.utf8))
        }
    }

    func testValidateRejectsHTMLBodyOn2xx() {
        let response = makeResponse(statusCode: 200)
        assertThrows(.invalidResponse("Test html response")) {
            try HTTPResponseValidation.validate(response, urlDescription: "Test", body: Data("<!DOCTYPE html><html>".utf8))
        }
    }

    func testValidateAcceptsJSONBodyMentioningHTMLishWords() throws {
        // Conservative markers: a JSON payload containing the word "auth"
        // must not be mistaken for an HTML page.
        let response = makeResponse(statusCode: 200)
        XCTAssertNoThrow(
            try HTTPResponseValidation.validate(
                response,
                urlDescription: "Test",
                body: Data(#"{"author":"ada","login":"x"}"#.utf8)
            )
        )
    }

    func testValidateSkipsHTMLCheckWhenNotExpectingJSON() throws {
        let response = makeResponse(statusCode: 200, headers: ["Content-Type": "text/html"])
        XCTAssertNoThrow(
            try HTTPResponseValidation.validate(
                response,
                urlDescription: "Test",
                body: Data("<html>".utf8),
                expectingJSON: false
            )
        )
    }

    func testLooksLikeHTMLUsesContentTypeOrBodyPrefix() {
        XCTAssertTrue(HTTPResponseValidation.looksLikeHTML(makeResponse(statusCode: 200, headers: ["Content-Type": "TEXT/HTML"])))
        XCTAssertTrue(HTTPResponseValidation.looksLikeHTML(makeResponse(statusCode: 200), body: Data("  <html lang=\"en\">".utf8)))
        XCTAssertFalse(HTTPResponseValidation.looksLikeHTML(makeResponse(statusCode: 200), body: Data(#"{"ok":true}"#.utf8)))
        XCTAssertFalse(HTTPResponseValidation.looksLikeHTML(makeResponse(statusCode: 200), body: nil))
    }

    // MARK: - Retry-After parsing

    func testRetryAfterSecondsParsesDeltaSeconds() {
        XCTAssertEqual(
            HTTPResponseValidation.retryAfterSeconds(
                from: makeResponse(statusCode: 429, headers: ["Retry-After": "60"]),
                now: referenceDate
            ),
            60
        )
    }

    func testRetryAfterSecondsParsesHTTPDate() {
        let deadline = referenceDate.addingTimeInterval(120)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let response = makeResponse(statusCode: 429, headers: ["Retry-After": formatter.string(from: deadline)])
        XCTAssertEqual(
            HTTPResponseValidation.retryAfterSeconds(from: response, now: referenceDate),
            120
        )
    }

    func testRetryAfterSecondsCapsAtCeiling() {
        XCTAssertEqual(HTTPResponseValidation.retryAfterCeiling, 3600)
        XCTAssertEqual(
            HTTPResponseValidation.retryAfterSeconds(
                from: makeResponse(statusCode: 429, headers: ["Retry-After": "999999"]),
                now: referenceDate
            ),
            3600
        )
    }

    func testRetryAfterSecondsReturnsNilForInvalidValues() {
        for header in ["", "abc", "-5", "nan"] {
            XCTAssertNil(
                HTTPResponseValidation.retryAfterSeconds(
                    from: makeResponse(statusCode: 429, headers: ["Retry-After": header]),
                    now: referenceDate
                ),
                "Unexpected value for header \(header)"
            )
        }
        XCTAssertNil(
            HTTPResponseValidation.retryAfterSeconds(
                from: makeResponse(statusCode: 429),
                now: referenceDate
            )
        )
    }

    func testRetryAfterSecondsReturnsNilForPastHTTPDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let past = formatter.string(from: referenceDate.addingTimeInterval(-60))
        XCTAssertNil(
            HTTPResponseValidation.retryAfterSeconds(
                from: makeResponse(statusCode: 429, headers: ["Retry-After": past]),
                now: referenceDate
            )
        )
    }

    // MARK: - classify

    func testClassifyCoversFailureVocabulary() {
        XCTAssertEqual(
            HTTPResponseValidation.classify(makeResponse(statusCode: 401), now: referenceDate),
            .unauthorized
        )
        XCTAssertEqual(
            HTTPResponseValidation.classify(makeResponse(statusCode: 403), now: referenceDate),
            .forbidden
        )
        XCTAssertEqual(
            HTTPResponseValidation.classify(makeResponse(statusCode: 403), tolerant403: true, now: referenceDate),
            .invalidStatus(statusCode: 403)
        )
        XCTAssertEqual(
            HTTPResponseValidation.classify(makeResponse(statusCode: 429, headers: ["Retry-After": "30"]), now: referenceDate),
            .rateLimited(retryAfterSeconds: 30)
        )
        XCTAssertEqual(
            HTTPResponseValidation.classify(makeResponse(statusCode: 429), now: referenceDate),
            .rateLimited(retryAfterSeconds: nil)
        )
        XCTAssertEqual(
            HTTPResponseValidation.classify(makeResponse(statusCode: 503), now: referenceDate),
            .serverFailure(statusCode: 503)
        )
        XCTAssertEqual(
            HTTPResponseValidation.classify(makeResponse(statusCode: 400), unauthorizedStatusCodes: [400, 401], now: referenceDate),
            .unauthorized
        )
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: ProviderError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard let actual = error as? ProviderError else {
                return XCTFail("Expected ProviderError \(expected), got \(error)", file: file, line: line)
            }
            XCTAssertEqual(actual.errorDescription, expected.errorDescription, file: file, line: line)
        }
    }
}
