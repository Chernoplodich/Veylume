import Foundation
import NaturalLanguage

public struct ReplacementRule: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var source: String
    public var replacement: String
    public var wholeWord: Bool
    public var caseSensitive: Bool
    public init(id: UUID = UUID(), source: String, replacement: String, wholeWord: Bool = true, caseSensitive: Bool = false) {
        self.id = id; self.source = source; self.replacement = replacement; self.wholeWord = wholeWord; self.caseSensitive = caseSensitive
    }
}
public struct DictionaryDocument: Codable, Sendable {
    public var version = 1
    public var terms: [String] = []
    public var replacements: [ReplacementRule] = []
    public init() {}
    public func validate() throws {
        guard version == 1, terms.count <= 500, replacements.count <= 500,
              terms.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }),
              replacements.allSatisfy({ !$0.source.isEmpty && $0.source.utf8.count <= 1024 && $0.replacement.utf8.count <= 4096 }) else { throw ValidationError.dictionary }
    }
}
public enum ValidationError: Error, Equatable { case dictionary, language, unsafeArtifact, integrity, noSpace, incomplete, keychain, database, unsupportedSchema }
public enum TextFinalizer {
    public static func apply(_ text: String, rules: [ReplacementRule]) -> String {
        let ordered = rules.enumerated().sorted {
            $0.element.source.count == $1.element.source.count ? $0.offset < $1.offset : $0.element.source.count > $1.element.source.count
        }.map(\.element)
        var output = "", cursor = text.startIndex
        while cursor < text.endIndex {
            var match: (ReplacementRule, Range<String.Index>)?
            for rule in ordered where !rule.source.isEmpty {
                let options: String.CompareOptions = rule.caseSensitive ? [.anchored, .literal] : [.anchored, .caseInsensitive]
                guard let range = text.range(of: rule.source, options: options, range: cursor..<text.endIndex), range.lowerBound == cursor else { continue }
                if rule.wholeWord {
                    let before = cursor > text.startIndex ? text[text.index(before: cursor)] : nil
                    let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
                    if before.map(isWord) == true || after.map(isWord) == true { continue }
                }
                match = (rule, range); break
            }
            if let (rule, range) = match { output += rule.replacement; cursor = range.upperBound }
            else { output.append(text[cursor]); cursor = text.index(after: cursor) }
        }
        return output
    }
    private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
    public static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word); tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).filter { text[$0].contains { $0.isLetter || $0.isNumber } }.count
    }
    /// Strip CSI, OSC, DCS/APC/PM/SOS, their C1 forms, then flatten separators.
    /// This payload can be pasted into a prompt; the app never submits it.
    public static func consolePayload(_ text: String) -> String {
        enum State { case normal, escape, csi, string, stringEscape }
        var state = State.normal, result = ""
        for scalar in text.unicodeScalars {
            let n = scalar.value
            switch state {
            case .normal:
                if n == 0x1B { state = .escape }
                else if n == 0x9B { state = .csi }
                else if [0x90, 0x98, 0x9D, 0x9E, 0x9F].contains(n) { state = .string }
                else if [9, 10, 11, 12, 13, 0x85, 0x2028, 0x2029].contains(n) { result.append(" ") }
                else if n >= 0x20 && !(0x7F...0x9F).contains(n) { result.unicodeScalars.append(scalar) }
            case .escape:
                if n == 0x5B { state = .csi }
                else if [0x5D, 0x50, 0x58, 0x5E, 0x5F].contains(n) { state = .string }
                else if n >= 0x30 && n <= 0x7E { state = .normal }
            case .csi: if (0x40...0x7E).contains(n) { state = .normal }
            case .string:
                if n == 7 || n == 0x9C { state = .normal }
                else if n == 0x1B { state = .stringEscape }
            case .stringEscape: state = n == 0x5C ? .normal : .string
            }
        }
        return result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
