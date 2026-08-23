import Foundation

/// The value tree of an OpenStep property list — the format `project.pbxproj`
/// is still written in.
public indirect enum PlistValue: Sendable {
    case string(String)
    case array([PlistValue])
    case dictionary([String: PlistValue])

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var arrayValue: [PlistValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var dictionaryValue: [String: PlistValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> PlistValue? {
        dictionaryValue?[key]
    }

    /// Convenience for the common shape: an array of object identifiers.
    public var stringArray: [String] {
        arrayValue?.compactMap(\.stringValue) ?? []
    }
}

/// A parser for the old NeXT plist syntax.
///
/// Written by hand rather than shelling out to `plutil` for two reasons: the
/// tool must give the same answer on a Linux CI runner as on a developer's Mac,
/// and a hook that spawns a subprocess per check pays that cost on every write.
public enum OpenStepPlist {
    public static func parse(_ text: String) -> PlistValue? {
        var scanner = Scanner(characters: Array(text))
        scanner.skipIgnorable()
        guard let value = scanner.parseValue() else { return nil }
        return value
    }

    private struct Scanner {
        let characters: [Character]
        var index = 0

        init(characters: [Character]) {
            self.characters = characters
        }

        var isAtEnd: Bool { index >= characters.count }

        mutating func skipIgnorable() {
            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace {
                    index += 1
                    continue
                }
                // Xcode writes an object's name into a comment beside every
                // reference to it. They are decoration; the identifiers on
                // either side are the data.
                if character == "/", index + 1 < characters.count {
                    if characters[index + 1] == "*" {
                        index += 2
                        while index + 1 < characters.count,
                              !(characters[index] == "*" && characters[index + 1] == "/") {
                            index += 1
                        }
                        index = min(index + 2, characters.count)
                        continue
                    }
                    if characters[index + 1] == "/" {
                        while index < characters.count, characters[index] != "\n" { index += 1 }
                        continue
                    }
                }
                return
            }
        }

        mutating func parseValue() -> PlistValue? {
            skipIgnorable()
            guard !isAtEnd else { return nil }

            switch characters[index] {
            case "{": return parseDictionary()
            case "(": return parseArray()
            case "\"": return parseQuotedString().map(PlistValue.string)
            case "<": return parseData().map(PlistValue.string)
            default: return parseBareString().map(PlistValue.string)
            }
        }

        mutating func parseDictionary() -> PlistValue? {
            guard consume("{") else { return nil }
            var result: [String: PlistValue] = [:]

            while true {
                skipIgnorable()
                if consume("}") { return .dictionary(result) }
                guard let key = parseKey() else { return nil }
                skipIgnorable()
                guard consume("=") else { return nil }
                guard let value = parseValue() else { return nil }
                result[key] = value
                skipIgnorable()
                _ = consume(";")
                if isAtEnd { return .dictionary(result) }
            }
        }

        mutating func parseArray() -> PlistValue? {
            guard consume("(") else { return nil }
            var result: [PlistValue] = []

            while true {
                skipIgnorable()
                if consume(")") { return .array(result) }
                guard let value = parseValue() else { return nil }
                result.append(value)
                skipIgnorable()
                _ = consume(",")
                if isAtEnd { return .array(result) }
            }
        }

        mutating func parseKey() -> String? {
            skipIgnorable()
            guard !isAtEnd else { return nil }
            if characters[index] == "\"" { return parseQuotedString() }
            return parseBareString()
        }

        mutating func parseQuotedString() -> String? {
            guard consume("\"") else { return nil }
            var result = ""
            while index < characters.count {
                let character = characters[index]
                if character == "\\" , index + 1 < characters.count {
                    index += 1
                    let escaped = characters[index]
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    default: result.append(escaped)
                    }
                    index += 1
                    continue
                }
                if character == "\"" {
                    index += 1
                    return result
                }
                result.append(character)
                index += 1
            }
            return result
        }

        /// Binary blobs appear in a few old projects. Their contents are never
        /// needed here, so they are read past and reduced to a placeholder.
        mutating func parseData() -> String? {
            guard consume("<") else { return nil }
            while index < characters.count, characters[index] != ">" { index += 1 }
            _ = consume(">")
            return ""
        }

        mutating func parseBareString() -> String? {
            let terminators: Set<Character> = ["{", "}", "(", ")", "=", ";", ",", "\"", "<", ">"]
            var result = ""
            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace || terminators.contains(character) { break }
                result.append(character)
                index += 1
            }
            return result.isEmpty ? nil : result
        }

        mutating func consume(_ expected: Character) -> Bool {
            skipIgnorable()
            guard index < characters.count, characters[index] == expected else { return false }
            index += 1
            return true
        }
    }
}
