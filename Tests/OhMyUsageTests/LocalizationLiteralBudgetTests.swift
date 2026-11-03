import Foundation
import XCTest

/// Guards the migration of user-facing Chinese copy into `Localization.swift`.
///
/// Every Swift string literal under `Sources/` that contains a CJK character counts
/// against a single repository-wide budget (`Localization.swift` itself is exempt).
/// The budget is a total cap rather than per-file caps so copy can move between files
/// freely; it must only ever go down. When you migrate literals into `L10nKey`, lower
/// `baseline` to the new count reported by the failure message.
///
/// Literals that are not UI copy (parser matching strings for Chinese API responses,
/// regex patterns, fixture-like constants) legitimately stay inline and are part of
/// the budget.
final class LocalizationLiteralBudgetTests: XCTestCase {
    private static let baseline = 469

    func testCJKStringLiteralCountStaysWithinBudget() throws {
        let counts = try Self.cjkLiteralCountsBySourceFile()
        let total = counts.values.reduce(0, +)
        let topOffenders = counts
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(15)
            .map { "  \($0.value)\t\($0.key)" }
            .joined(separator: "\n")

        XCTAssertLessThanOrEqual(
            total,
            Self.baseline,
            """
            Found \(total) CJK string literals outside Localization.swift (budget \(Self.baseline)). \
            Move new user-facing copy into L10nKey instead of inline zh/en literals.
            Top files:
            \(topOffenders)
            """
        )
        if total < Self.baseline {
            print("LocalizationLiteralBudgetTests: \(total) CJK literals remain; lower baseline from \(Self.baseline) to \(total).")
        }
    }

    func testScannerCountsLiteralsAndSkipsComments() {
        let source = #"""
        // 注释里的中文不计入
        /* 块注释 /* 嵌套 */ 也不计入 */
        let a = "中文"
        let b = viewModel.language == .zhHans ? "启用 \(name)" : "Enable \(name)"
        let c = #"原始 "字符串""#
        let d = """
            多行中文
            """
        let e = "English only \("插值里的中文")"
        let f = "\u{4E2D}"
        """#
        // a, b (zh branch), c, d, and the literal nested inside e's interpolation.
        XCTAssertEqual(Self.cjkLiteralCount(in: source), 5)
    }

    // MARK: - Scanner

    private static func cjkLiteralCountsBySourceFile() throws -> [String: Int] {
        let rootURL = packageRepositoryRootURL()
        let sourcesURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil)
        )
        var counts: [String: Int] = [:]
        for case let fileURL as URL in enumerator
        where fileURL.pathExtension == "swift" && fileURL.lastPathComponent != "Localization.swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let count = cjkLiteralCount(in: source)
            if count > 0 {
                let relativePath = fileURL.standardizedFileURL.path
                    .replacingOccurrences(of: rootURL.standardizedFileURL.path + "/", with: "")
                counts[relativePath] = count
            }
        }
        return counts
    }

    static func cjkLiteralCount(in source: String) -> Int {
        var scanner = SwiftLiteralScanner(source: Array(source.unicodeScalars))
        return scanner.literals().filter { literal in
            literal.unicodeScalars.contains(where: isCJK)
        }.count
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, // CJK symbols and punctuation
             0x3400...0x4DBF, // CJK unified ideographs extension A
             0x4E00...0x9FFF, // CJK unified ideographs
             0xF900...0xFAFF, // CJK compatibility ideographs
             0xFF00...0xFFEF: // Half/full-width forms (full-width punctuation)
            return true
        default:
            return false
        }
    }
}

/// Minimal Swift lexer that extracts string literal contents (including literals nested in
/// interpolations, raw `#"..."#` strings and multi-line `"""` strings) while skipping
/// line and nested block comments. Interpolated expressions themselves are not part of the
/// enclosing literal's text.
private struct SwiftLiteralScanner {
    let source: [Unicode.Scalar]
    var index = 0
    var collected: [String] = []

    init(source: [Unicode.Scalar]) {
        self.source = source
    }

    mutating func literals() -> [String] {
        while index < source.count {
            if matches("//") {
                skipLineComment()
            } else if matches("/*") {
                skipBlockComment()
            } else if source[index] == "#" || source[index] == "\"" {
                var cursor = index
                var hashes = 0
                while cursor < source.count, source[cursor] == "#" {
                    hashes += 1
                    cursor += 1
                }
                if cursor < source.count, source[cursor] == "\"" {
                    index = cursor
                    readString(hashes: hashes)
                } else {
                    index = max(cursor, index + 1)
                }
            } else {
                index += 1
            }
        }
        return collected
    }

    private func matches(_ token: String, at position: Int? = nil) -> Bool {
        let start = position ?? index
        let scalars = Array(token.unicodeScalars)
        guard start + scalars.count <= source.count else { return false }
        for offset in 0..<scalars.count where source[start + offset] != scalars[offset] {
            return false
        }
        return true
    }

    private mutating func skipLineComment() {
        while index < source.count, source[index] != "\n" {
            index += 1
        }
    }

    private mutating func skipBlockComment() {
        var depth = 0
        repeat {
            if matches("/*") {
                depth += 1
                index += 2
            } else if matches("*/") {
                depth -= 1
                index += 2
            } else {
                index += 1
            }
        } while depth > 0 && index < source.count
    }

    /// Reads a literal whose opening quote is at `index`, appending its text to `collected`.
    private mutating func readString(hashes: Int) {
        let isMultiline = matches("\"\"\"")
        let delimiter = (isMultiline ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
        let escape = "\\" + String(repeating: "#", count: hashes)
        index += isMultiline ? 3 : 1
        var text = String.UnicodeScalarView()

        while index < source.count {
            if matches(escape) {
                let afterEscape = index + escape.unicodeScalars.count
                if afterEscape < source.count, source[afterEscape] == "(" {
                    index = afterEscape + 1
                    skipInterpolation()
                } else {
                    index = afterEscape + 1
                }
                continue
            }
            if matches(delimiter) {
                index += delimiter.unicodeScalars.count
                break
            }
            text.append(source[index])
            index += 1
        }
        collected.append(String(text))
    }

    /// Skips a balanced interpolation body starting just after `\(`; literals inside are collected.
    private mutating func skipInterpolation() {
        var depth = 1
        while index < source.count, depth > 0 {
            let scalar = source[index]
            if scalar == "\"" {
                readString(hashes: 0)
                continue
            }
            if scalar == "(" {
                depth += 1
            } else if scalar == ")" {
                depth -= 1
            }
            index += 1
        }
    }
}
