import Foundation
import OhMyUsageProviders

struct OfficialProfileSnapshotRetryResult<State, Response> {
    var state: State
    var response: Response
    var didRefresh: Bool
}

enum OfficialProfileSnapshotRuntime {
    static func requestData(
        session: URLSession,
        request: URLRequest,
        invalidResponseMessage: String,
        decodeErrorMessage: String? = nil,
        unauthorizedStatusCodes: Set<Int> = [401, 403],
        rateLimitedStatusCodes: Set<Int> = [429],
        httpErrorMessage: (Int) -> String = { "http \($0)" }
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse(invalidResponseMessage)
        }
        if unauthorizedStatusCodes.contains(http.statusCode) {
            throw ProviderError.unauthorized
        }
        if rateLimitedStatusCodes.contains(http.statusCode) {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse(httpErrorMessage(http.statusCode))
        }
        return (data, http)
    }

    static func requestJSON(
        session: URLSession,
        request: URLRequest,
        invalidResponseMessage: String,
        decodeErrorMessage: String,
        unauthorizedStatusCodes: Set<Int> = [401, 403],
        rateLimitedStatusCodes: Set<Int> = [429],
        httpErrorMessage: (Int) -> String = { "http \($0)" }
    ) async throws -> ([String: Any], HTTPURLResponse) {
        let (data, http) = try await requestData(
            session: session,
            request: request,
            invalidResponseMessage: invalidResponseMessage,
            unauthorizedStatusCodes: unauthorizedStatusCodes,
            rateLimitedStatusCodes: rateLimitedStatusCodes,
            httpErrorMessage: httpErrorMessage
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse(decodeErrorMessage)
        }
        return (json, http)
    }

    static func requestWithUnauthorizedRefresh<State, Response>(
        initialState: State,
        request: (State) async throws -> Response,
        refresh: (State) async throws -> State?
    ) async throws -> OfficialProfileSnapshotRetryResult<State, Response> {
        do {
            let response = try await request(initialState)
            return OfficialProfileSnapshotRetryResult(
                state: initialState,
                response: response,
                didRefresh: false
            )
        } catch let error as ProviderError {
            guard case .unauthorized = error,
                  let refreshedState = try await refresh(initialState) else {
                throw error
            }
            let response = try await request(refreshedState)
            return OfficialProfileSnapshotRetryResult(
                state: refreshedState,
                response: response,
                didRefresh: true
            )
        }
    }

    static func mutateJSONObjectString(
        _ rawJSON: String,
        invalidResponseMessage: String,
        writingOptions: JSONSerialization.WritingOptions = [.prettyPrinted],
        mutate: (inout [String: Any]) -> Void
    ) throws -> String {
        guard let sourceData = rawJSON.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: sourceData)) as? [String: Any] else {
            throw ProviderError.invalidResponse(invalidResponseMessage)
        }

        mutate(&root)

        guard let encoded = try? JSONSerialization.data(withJSONObject: root, options: writingOptions),
              let updatedRawJSON = String(data: encoded, encoding: .utf8) else {
            throw ProviderError.invalidResponse(invalidResponseMessage)
        }

        return updatedRawJSON
    }
}
