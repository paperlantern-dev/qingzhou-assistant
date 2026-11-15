import Foundation

/// People who never get an automatic reply (family, friends, suppliers): their chats are not
/// opened, answered, remembered or contacted first.
public struct NeverReplyList: Equatable {
    public var names: [String]

    public init(_ names: [String]) { self.names = names }

    /// True when a chat title, or a name in the contact list, is one of them. OCR may misread a
    /// character; a contact-list name cut off with “…” counts when it is the start of a listed name.
    public func contains(_ name: String) -> Bool {
        let cut = name.contains("…") || name.contains("...")
        let n = Self.key(name)
        guard n.count >= 2 else { return false }
        return names.contains { listed in
            let m = Self.key(listed)
            guard m.count >= 2 else { return false }
            return TextMatch.similar(m, n) || (cut && n.count >= 3 && m.hasPrefix(n))
        }
    }

    /// A name without a group's member count (“家人群(5)”) and without spaces or punctuation.
    private static func key(_ name: String) -> String {
        TextMatch.normalize(name.replacingOccurrences(of: #"\s*[(（]\s*\d+\s*[)）]\s*$"#, with: "",
                                                      options: .regularExpression))
    }
}
