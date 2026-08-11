import Foundation

public enum RelayJSONExpressionEvaluator {
    public static func numericValue(for expression: String, in root: Any) -> Double? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("div("), trimmed.hasSuffix(")") {
            let arguments = splitArguments(String(trimmed.dropFirst(4).dropLast()))
            guard arguments.count == 2,
                  let numerator = numericValue(for: arguments[0], in: root),
                  let denominator = numericValue(for: arguments[1], in: root),
                  denominator != 0 else {
                return nil
            }
            return numerator / denominator
        }

        if trimmed.hasPrefix("sum("), trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst(4).dropLast())
            let numbers = values(at: inner, in: root).compactMap(coerceDouble)
            guard !numbers.isEmpty else { return nil }
            return numbers.reduce(0, +)
        }

        if trimmed.hasPrefix("coalesce("), trimmed.hasSuffix(")") {
            for argument in splitArguments(String(trimmed.dropFirst(9).dropLast())) {
                if let value = numericValue(for: argument, in: root) {
                    return value
                }
            }
            return nil
        }

        if trimmed.hasPrefix("add("), trimmed.hasSuffix(")") {
            let arguments = splitArguments(String(trimmed.dropFirst(4).dropLast()))
            guard !arguments.isEmpty else { return nil }
            var total: Double = 0
            var found = false
            for argument in arguments {
                if let value = numericValue(for: argument, in: root) {
                    total += value
                    found = true
                }
            }
            return found ? total : nil
        }

        if let literal = Double(trimmed) {
            return literal
        }

        return value(at: trimmed, in: root).flatMap(coerceDouble)
    }

    public static func stringValue(for expression: String, in root: Any) -> String? {
        stringValue(for: expression, in: root, allowBareLiteral: true)
    }

    private static func stringValue(
        for expression: String,
        in root: Any,
        allowBareLiteral: Bool
    ) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("coalesce("), trimmed.hasSuffix(")") {
            for argument in splitArguments(String(trimmed.dropFirst(9).dropLast())) {
                if let value = stringValue(for: argument, in: root, allowBareLiteral: false),
                   !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        if let value = value(at: trimmed, in: root) {
            if let string = value as? String {
                let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    return normalized
                }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }

        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return allowBareLiteral ? trimmed : nil
    }

    public static func boolValue(for expression: String, in root: Any) -> Bool? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("coalesce("), trimmed.hasSuffix(")") {
            for argument in splitArguments(String(trimmed.dropFirst(9).dropLast())) {
                if let value = boolValue(for: argument, in: root) {
                    return value
                }
            }
            return nil
        }
        return value(at: trimmed, in: root).flatMap(coerceBool) ?? coerceBool(trimmed)
    }

    public static func value(at path: String, in root: Any) -> Any? {
        let steps = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard !steps.isEmpty else { return nil }
        var current: Any? = root
        for step in steps {
            if let index = Int(step), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
                continue
            }
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[step]
        }
        return current
    }

    public static func values(at path: String, in root: Any) -> [Any] {
        let steps = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard !steps.isEmpty else { return [] }
        return collectValues(current: root, steps: steps, index: 0)
    }

    public static func firstNestedNumericValue(for keys: [String], in root: Any) -> Double? {
        for key in keys {
            if let value = firstNestedValue(matchingKey: key, in: root),
               let number = coerceDouble(value) {
                return number
            }
        }
        return nil
    }

    public static func firstNestedStringValue(for keys: [String], in root: Any) -> String? {
        for key in keys {
            if let value = firstNestedValue(matchingKey: key, in: root) {
                if let string = value as? String {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                } else if let number = value as? NSNumber {
                    return number.stringValue
                }
            }
        }
        return nil
    }

    public static func firstNestedValue(matchingKey key: String, in root: Any) -> Any? {
        if let dict = root as? [String: Any] {
            if let direct = dict[key] {
                return direct
            }
            for value in dict.values {
                if let nested = firstNestedValue(matchingKey: key, in: value) {
                    return nested
                }
            }
            return nil
        }

        if let array = root as? [Any] {
            for value in array {
                if let nested = firstNestedValue(matchingKey: key, in: value) {
                    return nested
                }
            }
        }

        return nil
    }

    public static func coerceDouble(_ value: Any) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    public static func coerceBool(_ value: Any) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1", "yes", "ok", "success":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    public static func splitArguments(_ input: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in input {
            switch character {
            case "(":
                depth += 1
                current.append(character)
            case ")":
                depth = max(0, depth - 1)
                current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(character)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            parts.append(tail)
        }
        return parts
    }

    private static func collectValues(current: Any, steps: [String], index: Int) -> [Any] {
        guard index < steps.count else { return [current] }
        let step = steps[index]

        if step == "*" {
            guard let array = current as? [Any] else { return [] }
            return array.flatMap { collectValues(current: $0, steps: steps, index: index + 1) }
        }

        if let i = Int(step), let array = current as? [Any], array.indices.contains(i) {
            return collectValues(current: array[i], steps: steps, index: index + 1)
        }

        guard let dict = current as? [String: Any], let next = dict[step] else {
            return []
        }
        return collectValues(current: next, steps: steps, index: index + 1)
    }
}
