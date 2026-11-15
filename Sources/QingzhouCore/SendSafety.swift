import Foundation

/// The text of a reply draft in its box on 首页: one or two messages.
public enum DraftText {
    /// An empty line separates the messages; line breaks inside a message stay.
    public static func join(_ messages: [String]) -> String {
        messages.joined(separator: "\n\n")
    }

    /// The messages to send, at most two. Nothing is dropped: text after the second message goes out with it.
    public static func messages(_ text: String) -> [String] {
        let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let parts = lines.split(whereSeparator: \.isEmpty).map { $0.joined(separator: "\n") }
        guard parts.count > 2 else { return parts }
        return [parts[0], parts.dropFirst().joined(separator: "\n")]
    }
}

/// Looked at again right before a foreground send: while waiting for the user to stop typing,
/// another chat may have been opened, the customer may have written more, or the owner may have
/// started typing in the input box.
public enum SendCheck {
    /// Why not to send now; nil when the screen still shows what the reply was written for.
    public static func problem(chat: String, pendingKey: String, nowChat: String, nowPendingKey: String,
                               nowInput: String) -> String? {
        if !ChatID.same(nowChat, chat) { return "当前会话已经换了" }
        if pendingKey != nowPendingKey, !TextMatch.similar(pendingKey, nowPendingKey) {
            return nowPendingKey.isEmpty ? "已经有人回复了" : "对方又发了新消息"
        }
        if !PictureCheck.inputLooksEmpty(nowInput) { return "输入框里有别的字" }
        return nil
    }
}
