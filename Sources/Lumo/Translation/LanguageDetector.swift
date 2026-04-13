import Foundation

enum LanguageDetector {
    /// True when ≥50% of the string's *letter* characters are Hangul.
    /// Digits, punctuation, whitespace, and emoji are not counted.
    static func isKorean(_ s: String) -> Bool {
        var hangul = 0
        var letters = 0
        for scalar in s.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if isHangul(scalar) { hangul += 1 }
        }
        guard letters > 0 else { return false }
        return Double(hangul) / Double(letters) >= 0.5
    }

    private static func isHangul(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0xAC00...0xD7A3,   // Hangul Syllables
             0x1100...0x11FF,   // Hangul Jamo
             0x3130...0x318F,   // Hangul Compatibility Jamo
             0xA960...0xA97F,   // Hangul Jamo Extended-A
             0xD7B0...0xD7FF:   // Hangul Jamo Extended-B
            return true
        default:
            return false
        }
    }
}
