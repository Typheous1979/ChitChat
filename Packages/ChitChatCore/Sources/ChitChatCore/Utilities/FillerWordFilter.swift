import Foundation

/// Removes filler words (um, uh, you know, etc.) from transcription text.
/// Uses word-boundary regex matching to avoid modifying real words like "umbrella" or "assume".
/// Pre-compiles the regex at init for fast per-result processing.
public final class FillerWordFilter: Sendable {

    /// Default filler words — conservative list that's safe to remove without changing meaning.
    /// Multi-word fillers are listed first (longest-first matching).
    public static let defaultFillers: [String] = [
        // Multi-word (matched before single-word components)
        "you know what I mean",
        "you know what",
        "you know",
        "I mean",
        "sort of",
        "kind of",
        "or something",
        "or whatever",
        "and stuff",
        "and things",
        "if you will",
        "as it were",
        "to be honest",
        "to be fair",
        "like I said",
        "at the end of the day",
        "mm-hmm",
        "mm hmm",
        "uh-huh",
        "uh huh",
        // Single-word hesitation markers
        "um",
        "uh",
        "erm",
        "er",
        "ah",
        "hmm",
        "hm",
        "mmm",
        "mm",
        "mhm",
    ]

    private let fillerPattern: NSRegularExpression
    private static let multipleSpacePattern = try! NSRegularExpression(pattern: #"\s{2,}"#)
    private static let danglingCommaPattern = try! NSRegularExpression(pattern: #",\s*,"#)

    public init(fillerWords: [String] = FillerWordFilter.defaultFillers) {
        // Build alternation pattern with word boundaries, longest-first
        let sorted = fillerWords.sorted { $0.count > $1.count }
        let escaped = sorted.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = #"\b(?:"# + escaped.joined(separator: "|") + #")\b"#
        self.fillerPattern = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    /// Remove filler words from the given text.
    /// Returns the cleaned text with proper spacing and capitalization.
    public func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text
        let range = NSRange(result.startIndex..., in: result)

        // Step 1: Remove filler words
        result = fillerPattern.stringByReplacingMatches(in: result, range: range, withTemplate: "")

        // Step 2: Clean up dangling commas (", ," → ",")
        result = Self.danglingCommaPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ","
        )

        // Step 3: Collapse multiple spaces
        result = Self.multipleSpacePattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: " "
        )

        // Step 4: Trim
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 5: Re-capitalize sentence starts
        result = Self.recapitalizeSentenceStarts(result)

        return result
    }

    /// Re-capitalize the first letter and any letter after sentence-ending punctuation.
    private static func recapitalizeSentenceStarts(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var chars = Array(text)

        // Capitalize first letter
        if let idx = chars.firstIndex(where: { $0.isLetter }) {
            chars[idx] = Character(chars[idx].uppercased())
        }

        // Capitalize after . ! ?
        var i = 0
        while i < chars.count {
            if chars[i] == "." || chars[i] == "!" || chars[i] == "?" {
                var j = i + 1
                while j < chars.count && chars[j].isWhitespace { j += 1 }
                if j < chars.count && chars[j].isLetter {
                    chars[j] = Character(chars[j].uppercased())
                }
            }
            i += 1
        }

        return String(chars)
    }
}
