import CoreGraphics
import Foundation

/// 读以前的聊天: screens read while scrolling a chat up, joined into one chat.
public enum HistoryStitch {
    /// Screens from the bottom up (newest first), joined oldest first.
    public static func join(pagesNewestFirst pages: [[StoredMessage]]) -> [StoredMessage] {
        pages.reduce([StoredMessage]()) { joined, page in stitch(older: page, newer: joined) }
    }

    /// `older` ends where `newer` begins (they may overlap; the first bubble of either may be cut
    /// off at the top of the screen). Joined without repeats. With no overlap, older comes first.
    public static func stitch(older: [StoredMessage], newer: [StoredMessage]) -> [StoredMessage] {
        guard !older.isEmpty else { return newer }
        guard !newer.isEmpty else { return older }
        for start in older.indices {   // the longest overlap first
            let rest = Array(older[start...])
            let length = min(rest.count, newer.count)
            let alike = (0..<length).allSatisfy { k in
                MemoryMerge.same(rest[k], newer[k]) || (k == 0 && cutOff(newer[k], of: rest[k]))
            }
            // One matching message is only trusted when it is not tiny.
            guard alike, length > 1 || TextMatch.normalize(rest[0].text).count >= 2 else { continue }
            var joined = Array(older[..<start]) + newer + Array(rest.dropFirst(newer.count))
            if cutOff(newer[0], of: rest[0]), !MemoryMerge.same(rest[0], newer[0]) { joined[start] = rest[0] }   // keep the whole one
            return joined
        }
        return older + newer
    }
}

extension HistoryStitch {
    /// Text lines of the chat list → one per row: the name on top; the preview right under it
    /// (closer than `rowGap`) is dropped.
    public static func rowNames(_ lines: [UnreadRow], rowGap: CGFloat = 34) -> [UnreadRow] {
        var kept: [UnreadRow] = []
        for l in lines.sorted(by: { $0.y < $1.y }) {
            if let last = kept.last, l.y - last.y < rowGap { continue }
            kept.append(l)
        }
        return kept
    }

    /// The top bubble of a screen cut off: only the end of the message shows.
    static func cutOff(_ seen: StoredMessage, of whole: StoredMessage) -> Bool {
        let s = TextMatch.normalize(seen.text), w = TextMatch.normalize(whole.text)
        return seen.fromMe == whole.fromMe && s.count >= 2 && w.count > s.count && w.hasSuffix(s)
    }
}

/// Cleaning old chats before anything is learned from them: no addresses, phones, names or
/// tracking numbers (a message with one is left out whole), no one-word or picture messages.
public enum HistoryClean {
    /// The owner's message as a sample of how he talks, or nil when it should not be learned.
    public static func learnable(_ raw: String) -> String? {
        guard !Privacy.redact(raw).changed, !hasTrackingNumber(raw) else { return nil }
        return PersonaSamples.sample(raw)
    }

    /// Customer question → the owner's answer (his messages right after it), for lessons in his
    /// own words. Left out: answers with a number or a promise (old prices), anything private.
    public static func pairs(_ messages: [StoredMessage]) -> [(question: String, answer: String)] {
        var result: [(question: String, answer: String)] = []
        var i = 0
        while i < messages.count {
            guard !messages[i].fromMe else { i += 1; continue }
            let question = messages[i].text
            var answers: [String] = []
            var j = i + 1
            while j < messages.count, messages[j].fromMe { answers.append(messages[j].text); j += 1 }
            let answer = answers.joined(separator: "\n")
            let key = TextMatch.normalize(question)
            if looksLikeQuestion(question), !answers.isEmpty, !isFiller(answer),
               learnable(question) != nil, answers.allSatisfy({ learnable($0) != nil }),
               !OwnerAnswer.needsApproval(answer),
               !result.contains(where: { TextMatch.similar(TextMatch.normalize($0.question), key) }) {
                result.append((question, answer))
            }
            i = max(j, i + 1)
        }
        return result
    }

    /// A question about something: a question mark or word, and more than a yes or a 今天的吗.
    static func looksLikeQuestion(_ text: String) -> Bool {
        let t = TextMatch.normalize(text)
        guard t.count >= 4 else { return false }
        return ["？", "?", "吗", "么", "多少", "怎么", "能不能", "有没有", "几", "哪", "什么", "是不是", "可不可以"]
            .contains { text.contains($0) }
    }

    /// Answers that say nothing to learn from on their own: 好的, 是的, 收到, 地址…
    static func isFiller(_ answer: String) -> Bool {
        ["好", "好的", "好的好的", "是的", "是", "嗯", "嗯嗯", "收到", "对", "地址", "ok", "OK", "行"]
            .contains(TextMatch.normalize(answer))
    }

    static func hasTrackingNumber(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(SF|JT|YT|ZTO|STO|YD)\d{8,}|(?<!\d)\d{12,}(?!\d)"#, options: .regularExpression) != nil
    }
}
