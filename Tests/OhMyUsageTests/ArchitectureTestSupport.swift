import Foundation

/// Repository root derived from this file's compile-time location, so architecture and
/// boundary tests resolve `Package.swift` / `Sources` fixtures regardless of the working
/// directory the test runner was launched from.
///
/// This file lives at `<repo>/Tests/OhMyUsageTests/ArchitectureTestSupport.swift`, so the
/// repository root is three `deletingLastPathComponent()` hops up from `#filePath`.
func packageRepositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // OhMyUsageTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}

struct PackageManifestTarget: Equatable {
    enum Kind: String {
        case regular
        case executable
        case test
    }

    let name: String
    let kind: Kind
    let dependencies: Set<String>
}

enum PackageManifestParsingError: Error, CustomStringConvertible {
    case missingClosingDelimiter(String)
    case missingTargetName(String)

    var description: String {
        switch self {
        case .missingClosingDelimiter(let context):
            return "Missing closing delimiter while parsing \(context)"
        case .missingTargetName(let body):
            return "Missing target name while parsing target block: \(body)"
        }
    }
}

func packageManifestTargets() throws -> [String: PackageManifestTarget] {
    let rootURL = packageRepositoryRootURL()
    let packageURL = rootURL.appendingPathComponent("Package.swift")
    let manifest = try String(contentsOf: packageURL, encoding: .utf8)
    let targets = try packageManifestTargets(in: manifest)
    return Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
}

func packageManifestTargets(in manifest: String) throws -> [PackageManifestTarget] {
    let declarations: [(prefix: String, kind: PackageManifestTarget.Kind)] = [
        (".target(", .regular),
        (".executableTarget(", .executable),
        (".testTarget(", .test)
    ]
    var targets: [PackageManifestTarget] = []
    var searchIndex = manifest.startIndex

    while searchIndex < manifest.endIndex {
        let nextDeclaration = declarations.compactMap { declaration -> (range: Range<String.Index>, kind: PackageManifestTarget.Kind)? in
            guard let range = manifest.range(of: declaration.prefix, range: searchIndex..<manifest.endIndex) else {
                return nil
            }
            return (range, declaration.kind)
        }
        .min { $0.range.lowerBound < $1.range.lowerBound }

        guard let nextDeclaration else {
            break
        }

        let openingParenthesis = manifest.index(before: nextDeclaration.range.upperBound)
        guard let closingParenthesis = closingDelimiterIndex(
            in: manifest,
            openingDelimiter: openingParenthesis,
            open: "(",
            close: ")"
        ) else {
            throw PackageManifestParsingError.missingClosingDelimiter("target declaration")
        }

        let bodyStart = manifest.index(after: openingParenthesis)
        let body = String(manifest[bodyStart..<closingParenthesis])
        guard let name = firstQuotedArgument(named: "name", in: body) else {
            throw PackageManifestParsingError.missingTargetName(body)
        }
        let dependencies = try dependencyNames(inTargetBody: body)
        targets.append(PackageManifestTarget(name: name, kind: nextDeclaration.kind, dependencies: dependencies))
        searchIndex = manifest.index(after: closingParenthesis)
    }

    return targets
}

func dependencyNames(inTargetBody body: String) throws -> Set<String> {
    guard let dependenciesLabel = body.range(of: "dependencies:"),
          let openingBracket = body[dependenciesLabel.upperBound...].firstIndex(of: "[") else {
        return []
    }
    guard let closingBracket = closingDelimiterIndex(
        in: body,
        openingDelimiter: openingBracket,
        open: "[",
        close: "]"
    ) else {
        throw PackageManifestParsingError.missingClosingDelimiter("target dependencies")
    }

    let literalStart = body.index(after: openingBracket)
    let literal = String(body[literalStart..<closingBracket])
    let dependencyEntries = splitTopLevelCommaSeparated(literal)
    return Set(dependencyEntries.compactMap { firstQuotedString(in: $0) })
}

func firstQuotedArgument(named argumentName: String, in text: String) -> String? {
    guard let argumentRange = text.range(of: "\(argumentName):") else {
        return nil
    }
    return firstQuotedString(in: String(text[argumentRange.upperBound...]))
}

func firstQuotedString(in text: String) -> String? {
    guard let openingQuote = text.firstIndex(of: "\"") else {
        return nil
    }
    let valueStart = text.index(after: openingQuote)
    guard let closingQuote = text[valueStart...].firstIndex(of: "\"") else {
        return nil
    }
    return String(text[valueStart..<closingQuote])
}

func closingDelimiterIndex(
    in text: String,
    openingDelimiter: String.Index,
    open: Character,
    close: Character
) -> String.Index? {
    var depth = 0
    var isInsideString = false
    var previousCharacter: Character?
    var index = openingDelimiter

    while index < text.endIndex {
        let character = text[index]
        if character == "\"" && previousCharacter != "\\" {
            isInsideString.toggle()
        } else if !isInsideString {
            if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        previousCharacter = character
        index = text.index(after: index)
    }

    return nil
}

func splitTopLevelCommaSeparated(_ text: String) -> [String] {
    var entries: [String] = []
    var current = ""
    var parenthesisDepth = 0
    var bracketDepth = 0
    var isInsideString = false
    var previousCharacter: Character?

    for character in text {
        if character == "\"" && previousCharacter != "\\" {
            isInsideString.toggle()
            current.append(character)
        } else if !isInsideString && character == "," && parenthesisDepth == 0 && bracketDepth == 0 {
            entries.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            current = ""
        } else {
            if !isInsideString {
                if character == "(" {
                    parenthesisDepth += 1
                } else if character == ")" {
                    parenthesisDepth -= 1
                } else if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth -= 1
                }
            }
            current.append(character)
        }
        previousCharacter = character
    }

    let finalEntry = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !finalEntry.isEmpty {
        entries.append(finalEntry)
    }
    return entries
}

func importedModuleNames(in source: String) -> Set<String> {
    Set(source.split(whereSeparator: \.isNewline).compactMap { rawLine in
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("//") else { return nil }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let importIndex = tokens.firstIndex(of: "import"),
              tokens.indices.contains(importIndex + 1) else {
            return nil
        }
        let importKindTokens = Set(["class", "enum", "func", "protocol", "struct", "typealias", "var"])
        let moduleIndex = importIndex + (importKindTokens.contains(tokens[importIndex + 1]) ? 2 : 1)
        guard tokens.indices.contains(moduleIndex) else { return nil }
        return tokens[moduleIndex].split(separator: ".").first.map(String.init)
    })
}

func importedImportSpecifiers(in source: String) -> Set<String> {
    Set(source.split(whereSeparator: \.isNewline).compactMap { rawLine in
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("//") else { return nil }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let importIndex = tokens.firstIndex(of: "import"),
              tokens.indices.contains(importIndex + 1) else {
            return nil
        }
        let importKindTokens = Set(["class", "enum", "func", "protocol", "struct", "typealias", "var"])
        let moduleIndex = importIndex + (importKindTokens.contains(tokens[importIndex + 1]) ? 2 : 1)
        guard tokens.indices.contains(moduleIndex) else { return nil }
        return tokens[moduleIndex]
    })
}

func swiftFiles(in directoryURL: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        return []
    }

    return try enumerator.compactMap { item in
        guard let url = item as? URL, url.pathExtension == "swift" else {
            return nil
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        return values.isRegularFile == true ? url : nil
    }
}

func isModuleMarkerFile(_ url: URL) -> Bool {
    url.lastPathComponent.hasSuffix("Module.swift")
}

func relativePath(for url: URL, rootURL: URL) -> String {
    let rootPath = rootURL.standardizedFileURL.path
    let filePath = url.standardizedFileURL.path
    guard filePath.hasPrefix(rootPath) else {
        return filePath
    }
    return String(filePath.dropFirst(rootPath.count + 1))
}
