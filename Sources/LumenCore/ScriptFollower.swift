import Foundation

/// Aligns recent recognition results with nearby script words. Silence and
/// off-script speech produce no movement; recognition revisions never rewind.
public struct ScriptFollower {
    private struct Word {
        let text: String
        let range: NSRange
    }
    private let words: [Word]
    private var lastRecognition = ""
    public private(set) var consumedWords = 0
    public var isAtEnd: Bool { !words.isEmpty && consumedWords == words.count }

    public init(script: String) { words = Self.tokenize(script) }

    public mutating func beginRecognition() { lastRecognition = "" }

    /// Returns a UTF-16 character offset in the original script for AppKit layout.
    public mutating func update(transcript: String) -> Int? {
        let recent = String(transcript.suffix(4_000))
        guard recent != lastRecognition else { return nil }
        lastRecognition = recent
        let spoken = Array(Self.tokenize(recent).suffix(6)).map(\.text)
        guard !spoken.isEmpty, !words.isEmpty, !isAtEnd else { return nil }
        let lower = max(0, consumedWords - 6)
        let upper = min(words.count, consumedWords + 80)
        let minimum = words.count == 1 ? 1 : 2
        guard spoken.count >= minimum else { return nil }
        for length in stride(from: min(spoken.count, 6), through: minimum, by: -1) {
            let suffix = Array(spoken.suffix(length))
            var best: Int?
            var bestDistance = Int.max
            guard upper - lower >= length else { continue }
            for start in lower...(upper - length) {
                let end = start + length
                guard end > consumedWords else { continue }
                // Two common words alone cannot jump far ahead in the script.
                if length == 2 && start > consumedWords + 8 { continue }
                guard words[start..<end].map(\.text) == suffix else { continue }
                let distance = abs(start - consumedWords)
                if distance < bestDistance {
                    best = end
                    bestDistance = distance
                }
            }
            if let end = best {
                consumedWords = end
                return words[end - 1].range.location
            }
        }
        return nil
    }

    private static func tokenize(_ text: String) -> [Word] {
        let pattern = #"[\p{L}\p{N}][\p{L}\p{N}\p{M}]*(?:['’][\p{L}\p{N}][\p{L}\p{N}\p{M}]*)*"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let folded = source.substring(with: match.range)
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .decomposedStringWithCanonicalMapping
            let normalized = String(
                String.UnicodeScalarView(folded.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) })
            )
            .replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "ـ", with: "")
            return Word(text: normalized, range: match.range)
        }
    }
}
