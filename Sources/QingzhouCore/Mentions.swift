import Foundation

/// Recognises “@我” in group messages. WeChat writes “@nickname” and a narrow space after it.
public enum Mentions {
    /// True when `text` @-mentions `me` (my nickname in the group), anywhere in the text.
    /// Spaces, punctuation and emoji are ignored on both sides, as is letter case; a long name may
    /// have one OCR slip. OCR often drops the space after a mention, so anything may follow the
    /// name: a longer name that starts with mine (“@店小二二号”) can't be told apart and counts.
    public static func mentions(me: String, in text: String) -> Bool {
        let name = key(me)
        guard !name.isEmpty else { return false }
        return text.indices.contains { i in
            atSigns.contains(text[i]) && startsWith(key(String(text[text.index(after: i)...])), name)
        }
    }

    private static let atSigns: Set<Character> = ["@", "＠"]

    private static func key(_ s: String) -> String { TextMatch.normalize(s).lowercased() }

    /// `rest` begins with `name`: exactly, or with one character misread, dropped or added
    /// (`TextMatch.similar` allows that only for long names).
    private static func startsWith(_ rest: String, _ name: String) -> Bool {
        if rest.hasPrefix(name) { return true }
        let chars = Array(rest)
        return (name.count - 1...name.count + 1).contains { length in
            length > 0 && length <= chars.count && TextMatch.similar(String(chars.prefix(length)), name)
        }
    }
}
