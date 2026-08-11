import Foundation

struct RelayHTTPClient {
    let session: URLSession

    func requestJSON(url: URL, headers: [String: String], method: String?, bodyJSON: String?) async throws -> Any {
        var req = URLRequest(url: url)
        let normalizedMethod = (method ?? "GET").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        req.httpMethod = normalizedMethod.isEmpty ? "GET" : normalizedMethod
        req.timeoutInterval = 15
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if let bodyJSON {
            let trimmedBody = bodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBody.isEmpty, req.httpMethod != "GET" {
                req.httpBody = trimmedBody.data(using: .utf8)
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            throw ProviderError.timeout(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            if let message = extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            if url.host?.contains("xiaomimimo.com") == true {
                throw ProviderError.unauthorizedDetail("xiaomimimo login expired; paste a fresh Cookie or switch to Browser First")
            }
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        if http.statusCode == 408 || (500...599).contains(http.statusCode) {
            throw ProviderError.timeout("http \(http.statusCode)")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            if looksLikeAuthenticationHTMLResponse(data) {
                throw ProviderError.invalidResponse("auth page html response")
            }
            throw ProviderError.invalidResponse("account balance JSON decode failed")
        }
    }

    func request<T: Decodable>(url: URL, bearerToken: String, type: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }

        if http.statusCode == 401 {
            if let message = extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderError.invalidResponse("decode failed for \(url.path)")
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = root["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = root["error"] as? String {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let errorObject = root["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let details = root["details"] as? String {
            return details.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func looksLikeAuthenticationHTMLResponse(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !text.isEmpty else {
            return false
        }

        if text.hasPrefix("<!doctype html") || text.hasPrefix("<html") {
            return true
        }

        return text.contains("<form") ||
            text.contains("login") ||
            text.contains("sign in") ||
            text.contains("signin") ||
            text.contains("auth")
    }
}
