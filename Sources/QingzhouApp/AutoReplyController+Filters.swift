import Foundation
import QingzhouCore

/// 白名单 (只回这些人) and 群里只回@我.
extension AutoReplyController {
    /// Why this chat must be skipped because of the “只回名单里的人” list, or nil.
    /// `opening`: deciding whether to open a row in the contact list (else: whether to reply).
    func listSkipReason(_ name: String, opening: Bool) -> String? {
        guard options.onlyListOn else { return nil }
        let action = opening ? "不点开" : "不回复"
        guard !options.onlyList.isEmpty else { return "：“只回这些人”名单是空的，\(action)（在设置里添加名字）" }
        return NeverReplyList(options.onlyList).contains(name) ? nil : "不在“只回这些人”名单里，\(action)"
    }

    /// Why a group message must be skipped because it does not @ me, or nil.
    /// Only when 回复群聊 is on: otherwise groups are skipped anyway, with their own reason.
    func groupAtSkipReason(_ snap: Snapshot, newest: String) -> String? {
        guard replyToGroups, options.groupAtOnly, GroupChat.isGroupTitle(snap.conversation.title) else { return nil }
        guard !TextMatch.normalize(options.myGroupName).isEmpty else { return "群里只回@我：先在设置里填你的群昵称" }
        return Mentions.mentions(me: options.myGroupName, in: newest) ? nil : "的新消息没有@我（群里只回@我），不回复"
    }

    /// Adds someone to the “只回这些人” list (names need two characters), or takes them off.
    func setOnlyList(_ name: String, _ on: Bool) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if on {
            guard TextMatch.normalize(n).count >= 2, !NeverReplyList(options.onlyList).contains(n) else { return }
            options.onlyList.append(n)
            add(.info, "「\(n)」加入“只回这些人”名单")
        } else {
            options.onlyList.removeAll { $0 == n }
            add(.info, "「\(n)」移出“只回这些人”名单")
        }
    }
}
