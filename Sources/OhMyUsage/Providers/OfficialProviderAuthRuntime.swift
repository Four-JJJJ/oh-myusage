import Foundation

struct OfficialOAuthRefreshResponse {
    let accessToken: String
    let json: [String: Any]
}

struct OfficialProviderAuthRequestResult<State, Response> {
    let state: State
    let response: Response
    let didRefresh: Bool
}

enum OfficialProviderAuthRuntime {
    static func urlEncodedFormData(_ fields: [String: String]) -> Data? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return fields
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    static func requestOAuthRefresh(
        session: URLSession,
        request: URLRequest,
        invalidResponseMessage: String,
        missingAccessTokenMessage: String,
        httpErrorMessage: (Int) -> String,
        unauthorizedStatusCodes: Set<Int> = [400, 401]
    ) async throws -> OfficialOAuthRefreshResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse(invalidResponseMessage)
        }
        if unauthorizedStatusCodes.contains(http.statusCode) {
            throw ProviderError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse(httpErrorMessage(http.statusCode))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = OfficialValueParser.string(json["access_token"]) else {
            throw ProviderError.invalidResponse(missingAccessTokenMessage)
        }
        return OfficialOAuthRefreshResponse(
            accessToken: accessToken,
            json: json
        )
    }

    static func requestWithExpiringCredentialRefresh<State, Response>(
        initialState: State,
        shouldRefresh: (State) -> Bool,
        request: (State) async throws -> Response,
        refresh: (State) async throws -> State
    ) async throws -> OfficialProviderAuthRequestResult<State, Response> {
        var state = initialState
        var didRefresh = false

        if shouldRefresh(state) {
            state = try await refresh(state)
            didRefresh = true
        }

        do {
            return OfficialProviderAuthRequestResult(
                state: state,
                response: try await request(state),
                didRefresh: didRefresh
            )
        } catch let error as ProviderError {
            guard case .unauthorized = error else {
                throw error
            }
            state = try await refresh(state)
            return OfficialProviderAuthRequestResult(
                state: state,
                response: try await request(state),
                didRefresh: true
            )
        }
    }

    static func updateJSONObjectFile(
        path: String,
        mutate: (inout [String: Any]) -> Void
    ) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }

        mutate(&json)

        guard let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else {
            return
        }
        try? encoded.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
