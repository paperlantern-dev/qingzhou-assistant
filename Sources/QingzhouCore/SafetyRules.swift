import Foundation

/// Recognizes group chats from what is visible on screen.
public enum GroupChat {
    /// WeChat shows a group's member count after its name, e.g. "客户交流群 (12)".
    /// Private chats never show it. Confirmed on WeChat for Mac 4.1.15.
    public static func isGroupTitle(_ title: String) -> Bool {
        title.range(of: #"[(（]\s*\d+\s*[)）]\s*$"#, options: .regularExpression) != nil
    }

    /// The preview line of a group row reads "nickname: message" (optionally "[3条] nickname: message").
    /// Pass only the preview line, not the name or the time ("07:16" is not "nickname: message").
    public static func looksLikeGroupPreview(_ preview: String) -> Bool {
        let p = preview.trimmingCharacters(in: .whitespaces)
        if isTimeOrDate(p) { return false }
        return p.range(of: #"^(\[\d+条\]\s*)?[^:：\s\d][^:：]{0,19}\s?[:：]\s?\S"#,
                       options: .regularExpression) != nil
    }

    /// "07:16", "2024/02/17", "昨天", "星期三" … — the time column of a row.
    public static func isTimeOrDate(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.range(of: #"^(\d{1,2}[:：]\d{2}|\d{2,4}[/\-]\d{1,2}([/\-]\d{1,2})?|昨天.*|星期.|周.)$"#,
                       options: .regularExpression) != nil
    }
}

/// Chats that are not people or groups and must never be opened or answered.
public enum SystemChat {
    public static let names: Set<String> = [
        "公众号", "服务号", "订阅号", "订阅号消息", "服务通知", "微信团队", "微信支付", "文件传输助手", "腾讯新闻",
    ]

    public static func isSystem(_ name: String) -> Bool {
        names.contains(TextMatch.normalize(name))
    }
}

/// Identity of a chat: whether it is a group, plus its name (without the member count).
/// A group and a person with the same name are different chats.
public enum ChatID {
    public static func make(title: String) -> String {
        let isGroup = GroupChat.isGroupTitle(title)
        let name = isGroup
            ? title.replacingOccurrences(of: #"\s*[(（]\s*\d+\s*[)）]\s*$"#, with: "", options: .regularExpression)
            : title
        return (isGroup ? "群|" : "人|") + TextMatch.normalize(name)
    }

    /// Same kind (group/person) and the same name, allowing small OCR differences in the name.
    public static func same(_ a: String, _ b: String) -> Bool {
        guard a.prefix(2) == b.prefix(2) else { return false }
        return TextMatch.similar(String(a.dropFirst(2)), String(b.dropFirst(2)))
    }
}

/// Caps how many replies are sent: overall per hour, and per chat per hour.
public struct SendLimiter {
    public var maxPerHour: Int
    public var maxPerChatPerHour: Int
    private var sends: [(chat: String, at: Date)] = []

    public init(maxPerHour: Int, maxPerChatPerHour: Int) {
        self.maxPerHour = maxPerHour
        self.maxPerChatPerHour = maxPerChatPerHour
    }

    /// nil when a reply may be sent now, otherwise a reason to show the user.
    /// `chat` is a `ChatID`; pass "" to check only the overall limit.
    public func blockReason(chat: String, now: Date = Date()) -> String? {
        let recent = sends.filter { now.timeIntervalSince($0.at) < 3600 }
        if recent.count >= maxPerHour {
            return "已达每小时上限 \(maxPerHour) 条，暂停回复"
        }
        let inChat = recent.filter { ChatID.same($0.chat, chat) }.count
        if inChat >= maxPerChatPerHour {
            return "这个会话已达每小时上限 \(maxPerChatPerHour) 条，暂停回复它"
        }
        return nil
    }

    public mutating func record(chat: String, at: Date = Date()) {
        sends = sends.filter { at.timeIntervalSince($0.at) < 3600 } + [(chat, at)]
    }
}
