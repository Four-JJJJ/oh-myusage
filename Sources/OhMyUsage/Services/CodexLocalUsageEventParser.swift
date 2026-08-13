import Foundation

enum CodexLocalUsageEventParser {
    static func parseCompletedEvent(from body: String, fallbackEventAt: Date) -> ParsedTokenEvent? {
        let firstNonWhitespace = body.unicodeScalars.first {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        if firstNonWhitespace == "{" || firstNonWhitespace == "[" {
            if let event = parseCompletedJSONEvent(from: body, fallbackEventAt: fallbackEventAt) {
                return event
            }
            return parseCompletedLogfmtEvent(from: body, fallbackEventAt: fallbackEventAt)
        }
        return parseCompletedLogfmtEvent(from: body, fallbackEventAt: fallbackEventAt)
    }

    static func parseCodexSSEMetadata(from body: String) -> ParsedCodexSSEMetadata? {
        let firstNonWhitespace = body.unicodeScalars.first {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        if firstNonWhitespace == "{" || firstNonWhitespace == "[" {
            if let metadata = parseCodexSSEMetadataJSON(from: body) {
                return metadata
            }
            return parseCodexSSEMetadataLogfmt(from: body)
        }
        return parseCodexSSEMetadataLogfmt(from: body)
    }

    static func sessionTokenComponents(from usage: [String: Any]) -> TokenComponents? {
        tokenComponents(from: usage, inputIncludesCache: true)
    }

    static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            return trimmed(value)
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    static func parseISODate(_ raw: String?) -> Date? {
        guard let raw = trimmed(raw) else { return nil }
        if let date = isoFormatterWithFractional.date(from: raw) {
            return date
        }
        return isoFormatterBasic.date(from: raw)
    }

    static func normalizedModelID(_ raw: String?) -> String {
        trimmed(raw) ?? "unknown"
    }

    private static func parseCompletedJSONEvent(from body: String, fallbackEventAt: Date) -> ParsedTokenEvent? {
        guard let data = body.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let event = root["event"] as? [String: Any]
        let eventName = stringValue(event?["name"])
            ?? stringValue(root["event_name"])
            ?? stringValue(root["name"])
        let eventKind = stringValue(event?["kind"])
            ?? stringValue(root["event_kind"])
            ?? stringValue(root["kind"])
        guard eventName == "codex.sse_event", eventKind == "response.completed" else {
            return nil
        }

        let tokenContainers: [[String: Any]] = [
            event,
            (event?["usage"] as? [String: Any]),
            root,
            (root["usage"] as? [String: Any]),
            ((event?["response"] as? [String: Any])?["usage"] as? [String: Any]),
            ((root["response"] as? [String: Any])?["usage"] as? [String: Any])
        ].compactMap { $0 }

        var parsedComponents = TokenComponents()
        var totalTokens = 0
        for container in tokenContainers {
            if let components = tokenComponents(from: container, inputIncludesCache: true),
               components.totalTokens > 0 {
                parsedComponents = components
                totalTokens = components.totalTokens
                break
            }
        }
        guard totalTokens > 0 else { return nil }

        let response = event?["response"] as? [String: Any]
        let rootResponse = root["response"] as? [String: Any]
        let rootUser = root["user"] as? [String: Any]
        let eventUser = event?["user"] as? [String: Any]
        let modelID = normalizedModelID(
            stringValue(event?["model"])
                ?? stringValue(response?["model"])
                ?? stringValue(root["model"])
                ?? stringValue(rootResponse?["model"])
        )
        let eventAt = parseISODate(
            stringValue(event?["timestamp"])
                ?? stringValue(root["event.timestamp"])
                ?? stringValue(root["timestamp"])
                ?? stringValue(root["event_timestamp"])
        ) ?? fallbackEventAt
        let accountID = normalizedAccountID(
            stringValue(eventUser?["account_id"])
                ?? stringValue(eventUser?["accountId"])
                ?? stringValue(rootUser?["account_id"])
                ?? stringValue(rootUser?["accountId"])
                ?? stringValue(root["user.account_id"])
                ?? stringValue(root["account_id"])
                ?? stringValue(root["accountId"])
        )
        let email = normalizedEmail(
            stringValue(eventUser?["email"])
                ?? stringValue(rootUser?["email"])
                ?? stringValue(root["user.email"])
                ?? stringValue(root["email"])
        )

        let signature = buildSignature(
            source: "json",
            responseID: stringValue(response?["id"]) ?? stringValue(rootResponse?["id"]) ?? stringValue(root["response_id"]),
            conversationID: stringValue((root["conversation"] as? [String: Any])?["id"]) ?? stringValue(root["conversation.id"]) ?? stringValue(root["conversation_id"]),
            threadID: stringValue((root["thread"] as? [String: Any])?["id"]) ?? stringValue(root["thread.id"]) ?? stringValue(root["thread_id"]),
            turnID: stringValue((root["turn"] as? [String: Any])?["id"]) ?? stringValue(root["turn.id"]) ?? stringValue(root["turn_id"]),
            submissionID: stringValue((root["submission"] as? [String: Any])?["id"]) ?? stringValue(root["submission.id"]) ?? stringValue(root["submission_id"]),
            eventTimestamp: stringValue(event?["timestamp"]) ?? stringValue(root["event.timestamp"]) ?? stringValue(root["event_timestamp"]),
            modelID: modelID,
            totalTokens: totalTokens,
            fallbackEventAt: eventAt,
            fallbackBody: body
        )

        return ParsedTokenEvent(
            signature: signature,
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: totalTokens,
            inputTokens: parsedComponents.inputTokens,
            outputTokens: parsedComponents.outputTokens,
            cacheReadTokens: parsedComponents.cacheReadTokens,
            cacheWriteTokens: parsedComponents.cacheWriteTokens,
            accountID: accountID,
            email: email
        )
    }

    private static func parseCodexSSEMetadataJSON(from body: String) -> ParsedCodexSSEMetadata? {
        guard let data = body.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let event = root["event"] as? [String: Any]
        let eventName = stringValue(event?["name"])
            ?? stringValue(root["event_name"])
            ?? stringValue(root["name"])
        guard eventName == "codex.sse_event" else {
            return nil
        }

        let kind = normalizedIdentityField(
            stringValue(event?["kind"])
                ?? stringValue(root["event_kind"])
                ?? stringValue(root["kind"])
        )
        let rootUser = root["user"] as? [String: Any]
        let eventUser = event?["user"] as? [String: Any]
        let accountID = normalizedAccountID(
            stringValue(eventUser?["account_id"])
                ?? stringValue(eventUser?["accountId"])
                ?? stringValue(rootUser?["account_id"])
                ?? stringValue(rootUser?["accountId"])
                ?? stringValue(root["user.account_id"])
                ?? stringValue(root["account_id"])
                ?? stringValue(root["accountId"])
        )
        let email = normalizedEmail(
            stringValue(eventUser?["email"])
                ?? stringValue(rootUser?["email"])
                ?? stringValue(root["user.email"])
                ?? stringValue(root["email"])
        )
        let conversationID = normalizedConversationID(
            stringValue((root["conversation"] as? [String: Any])?["id"])
                ?? stringValue(root["conversation.id"])
                ?? stringValue(root["conversation_id"])
        )

        return ParsedCodexSSEMetadata(
            kind: kind,
            conversationID: conversationID,
            accountID: accountID,
            email: email
        )
    }

    private static func parseCompletedLogfmtEvent(from body: String, fallbackEventAt: Date) -> ParsedTokenEvent? {
        let fields = parseLogfmtFields(body)
        let eventName = normalizedIdentityField(fields["event.name"])
        let eventKind = normalizedIdentityField(fields["event.kind"])
        guard eventName == "codex.sse_event", eventKind == "response.completed" else {
            return nil
        }

        let tokenComponents = tokenComponents(from: fields, inputIncludesCache: true) ?? TokenComponents()
        let totalTokens = tokenComponents.totalTokens
        guard totalTokens > 0 else {
            return nil
        }

        let modelID = normalizedModelID(fields["model"] ?? fields["slug"])

        let eventAt = parseISODate(fields["event.timestamp"]) ?? fallbackEventAt
        let accountID = normalizedAccountID(
            fields["user.account_id"]
                ?? fields["user.accountId"]
                ?? fields["account_id"]
                ?? fields["accountId"]
        )
        let email = normalizedEmail(fields["user.email"] ?? fields["email"])

        let signature = buildSignature(
            source: "logfmt",
            responseID: fields["response.id"] ?? fields["event.id"],
            conversationID: fields["conversation.id"],
            threadID: fields["thread.id"],
            turnID: fields["turn.id"],
            submissionID: fields["submission.id"],
            eventTimestamp: fields["event.timestamp"],
            modelID: modelID,
            totalTokens: totalTokens,
            fallbackEventAt: eventAt,
            fallbackBody: body
        )

        return ParsedTokenEvent(
            signature: signature,
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: totalTokens,
            inputTokens: tokenComponents.inputTokens,
            outputTokens: tokenComponents.outputTokens,
            cacheReadTokens: tokenComponents.cacheReadTokens,
            cacheWriteTokens: tokenComponents.cacheWriteTokens,
            accountID: accountID,
            email: email
        )
    }

    private static func parseCodexSSEMetadataLogfmt(from body: String) -> ParsedCodexSSEMetadata? {
        let fields = parseLogfmtFields(body)
        let eventName = normalizedIdentityField(fields["event.name"])
        guard eventName == "codex.sse_event" else {
            return nil
        }

        let kind = normalizedIdentityField(fields["event.kind"])
        let accountID = normalizedAccountID(
            fields["user.account_id"]
                ?? fields["user.accountId"]
                ?? fields["account_id"]
                ?? fields["accountId"]
        )
        let email = normalizedEmail(fields["user.email"] ?? fields["email"])
        let conversationID = normalizedConversationID(
            fields["conversation.id"] ?? fields["conversation_id"]
        )

        return ParsedCodexSSEMetadata(
            kind: kind,
            conversationID: conversationID,
            accountID: accountID,
            email: email
        )
    }

    private static func buildSignature(
        source: String,
        responseID: String?,
        conversationID: String?,
        threadID: String?,
        turnID: String?,
        submissionID: String?,
        eventTimestamp: String?,
        modelID: String,
        totalTokens: Int,
        fallbackEventAt: Date,
        fallbackBody: String
    ) -> String {
        var components: [String] = ["source=\(source)"]

        if let responseID = trimmed(responseID) {
            components.append("response=\(responseID)")
        }
        if let conversationID = trimmed(conversationID) {
            components.append("conversation=\(conversationID)")
        }
        if let threadID = trimmed(threadID) {
            components.append("thread=\(threadID)")
        }
        if let turnID = trimmed(turnID) {
            components.append("turn=\(turnID)")
        }
        if let submissionID = trimmed(submissionID) {
            components.append("submission=\(submissionID)")
        }
        if let eventTimestamp = trimmed(eventTimestamp) {
            components.append("eventAt=\(eventTimestamp)")
        } else {
            components.append("eventAt=\(Int(fallbackEventAt.timeIntervalSince1970))")
        }

        components.append("model=\(modelID)")
        components.append("tokens=\(totalTokens)")

        if components.count <= 4 {
            components.append("hash=\(stableHash(of: fallbackBody))")
        }

        return components.joined(separator: "|")
    }

    private static func stableHash(of text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func parseLogfmtFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        fields.reserveCapacity(32)

        let scalars = Array(text.unicodeScalars)
        var index = 0

        func isWhitespace(_ scalar: UnicodeScalar) -> Bool {
            CharacterSet.whitespacesAndNewlines.contains(scalar)
        }

        while index < scalars.count {
            while index < scalars.count, isWhitespace(scalars[index]) {
                index += 1
            }
            guard index < scalars.count else { break }

            let keyStart = index
            while index < scalars.count,
                  !isWhitespace(scalars[index]),
                  scalars[index] != "=" {
                index += 1
            }

            guard index < scalars.count, scalars[index] == "=" else {
                while index < scalars.count, !isWhitespace(scalars[index]) {
                    index += 1
                }
                continue
            }

            let key = String(String.UnicodeScalarView(scalars[keyStart..<index]))
            index += 1
            if key.isEmpty {
                continue
            }

            var value = ""
            if index < scalars.count, scalars[index] == "\"" {
                index += 1
                var escaped = false
                while index < scalars.count {
                    let scalar = scalars[index]
                    index += 1
                    if escaped {
                        value.unicodeScalars.append(scalar)
                        escaped = false
                        continue
                    }
                    if scalar == "\\" {
                        escaped = true
                        continue
                    }
                    if scalar == "\"" {
                        break
                    }
                    value.unicodeScalars.append(scalar)
                }
                if escaped {
                    value.append("\\")
                }
            } else {
                let valueStart = index
                while index < scalars.count, !isWhitespace(scalars[index]) {
                    index += 1
                }
                value = String(String.UnicodeScalarView(scalars[valueStart..<index]))
            }

            if fields[key] == nil {
                fields[key] = value
            }
        }

        return fields
    }

    private static func tokenComponents(
        from container: [String: Any],
        inputIncludesCache: Bool
    ) -> TokenComponents? {
        let cacheRead = firstInt(
            in: container,
            keys: [
                "cached_token_count",
                "cached_tokens",
                "cached_input_tokens",
                "cache_read_input_tokens"
            ]
        )
        let cacheWrite = firstInt(
            in: container,
            keys: [
                "cache_creation_input_tokens",
                "cache_creation_tokens",
                "cache_write_tokens"
            ]
        )
        let rawInput = firstInt(
            in: container,
            keys: [
                "input_token_count",
                "input_tokens",
                "prompt_tokens"
            ]
        )
        let output = resolvedOutputTokens(
            rawOutput: firstInt(
                in: container,
                keys: [
                    "output_token_count",
                    "output_tokens",
                    "completion_tokens"
                ]
            ),
            reasoning: firstInt(
                in: container,
                keys: [
                    "reasoning_token_count",
                    "reasoning_tokens",
                    "reasoning_output_tokens"
                ]
            ),
            tool: firstInt(
                in: container,
                keys: [
                    "tool_token_count",
                    "tool_tokens"
                ]
            )
        )
        let total = firstInt(
            in: container,
            keys: [
                "total_tokens",
                "total_token_count"
            ]
        )

        return buildTokenComponents(
            rawInput: rawInput,
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            total: total,
            inputIncludesCache: inputIncludesCache
        )
    }

    private static func tokenComponents(
        from fields: [String: String],
        inputIncludesCache: Bool
    ) -> TokenComponents? {
        let cacheRead = firstInt(
            in: fields,
            keys: [
                "cached_token_count",
                "cached_tokens",
                "cached_input_tokens",
                "cache_read_input_tokens"
            ]
        )
        let cacheWrite = firstInt(
            in: fields,
            keys: [
                "cache_creation_input_tokens",
                "cache_creation_tokens",
                "cache_write_tokens"
            ]
        )
        let rawInput = firstInt(
            in: fields,
            keys: [
                "input_token_count",
                "input_tokens",
                "prompt_tokens"
            ]
        )
        let output = resolvedOutputTokens(
            rawOutput: firstInt(
                in: fields,
                keys: [
                    "output_token_count",
                    "output_tokens",
                    "completion_tokens"
                ]
            ),
            reasoning: firstInt(
                in: fields,
                keys: [
                    "reasoning_token_count",
                    "reasoning_tokens",
                    "reasoning_output_tokens"
                ]
            ),
            tool: firstInt(
                in: fields,
                keys: [
                    "tool_token_count",
                    "tool_tokens"
                ]
            )
        )
        let total = firstInt(
            in: fields,
            keys: [
                "total_tokens",
                "total_token_count"
            ]
        )

        return buildTokenComponents(
            rawInput: rawInput,
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            total: total,
            inputIncludesCache: inputIncludesCache
        )
    }

    private static func buildTokenComponents(
        rawInput: Int?,
        output: Int,
        cacheRead: Int?,
        cacheWrite: Int?,
        total: Int?,
        inputIncludesCache: Bool
    ) -> TokenComponents? {
        let cacheRead = max(0, cacheRead ?? 0)
        let cacheWrite = max(0, cacheWrite ?? 0)
        let rawInput = max(0, rawInput ?? 0)
        let input = inputIncludesCache && rawInput >= cacheRead
            ? rawInput - cacheRead
            : rawInput
        let componentsTotal = input + max(0, output) + cacheRead + cacheWrite
        let explicitTotal = max(0, total ?? 0)
        guard componentsTotal > 0 || explicitTotal > 0 else { return nil }
        return TokenComponents(
            inputTokens: input,
            outputTokens: max(0, output),
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            totalTokens: explicitTotal > 0 ? explicitTotal : componentsTotal
        )
    }

    private static func resolvedOutputTokens(rawOutput: Int?, reasoning: Int?, tool: Int?) -> Int {
        let output = max(0, rawOutput ?? 0)
        let reasoning = max(0, reasoning ?? 0)
        let tool = max(0, tool ?? 0)
        if output > 0 {
            return output
        }
        return reasoning + tool
    }

    private static func firstInt(in container: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = intValue(container[key]) {
                return value
            }
        }
        return nil
    }

    private static func firstInt(in fields: [String: String], keys: [String]) -> Int? {
        for key in keys {
            if let value = intValue(fields[key]) {
                return value
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? String {
            return intValue(value)
        }
        return nil
    }

    private static func intValue(_ value: String?) -> Int? {
        guard let value = trimmed(value) else { return nil }
        if let integer = Int(value) { return integer }
        if let double = Double(value) { return Int(double.rounded()) }
        return nil
    }

    nonisolated(unsafe) private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoFormatterBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func normalizedAccountID(_ raw: String?) -> String? {
        guard var value = normalizedIdentityField(raw)?.lowercased() else { return nil }
        if value.hasPrefix("tenant:account:") {
            value = String(value.dropFirst("tenant:account:".count))
        }
        if value.hasPrefix("account:") {
            value = String(value.dropFirst("account:".count))
        }
        return trimmed(value)
    }

    private static func normalizedEmail(_ raw: String?) -> String? {
        normalizedIdentityField(raw)?.lowercased()
    }

    private static func normalizedConversationID(_ raw: String?) -> String? {
        normalizedIdentityField(raw)?.lowercased()
    }

    private static func normalizedIdentityField(_ raw: String?) -> String? {
        guard var value = trimmed(raw) else { return nil }

        if value.hasPrefix("\\\"") && value.hasSuffix("\\\"") && value.count >= 4 {
            value = String(value.dropFirst(2).dropLast(2))
        }
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }

        value = value.replacingOccurrences(of: "\\\"", with: "\"")
        value = value.replacingOccurrences(of: "\\\\", with: "\\")

        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }

        return trimmed(value)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
