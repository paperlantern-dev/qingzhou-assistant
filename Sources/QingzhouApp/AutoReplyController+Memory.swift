import Foundation
import QingzhouCore

/// Keeping each customer's chat and key points on this Mac.
extension AutoReplyController {
    /// While auto-reply runs, keeps what is on screen in the open private chat (not groups,
    /// official accounts or people on the 不自动回复 list) in that customer's memory.
    func rememberIfCustomer(_ snap: Snapshot) {
        let conv = snap.conversation
        memoryCount = memory.count
        guard isRunning, useMemory, target.supportsAutoReply, !conv.title.isEmpty, !conv.bubbles.isEmpty,
              !GroupChat.isGroupTitle(conv.title), !SystemChat.isSystem(conv.title), !isNeverReply(conv.title)
        else { return }
        let chat = ChatID.make(title: conv.title)
        if let only = onlyChat, !chat.contains(only) { return }
        let record = memory.remember(chatID: chat, name: conv.title, visible: conv.bubbles)
        if record.avatarFile == nil { saveAvatar(of: chat, name: conv.title, from: snap) }
        learnOwnerAnswers(in: record)
        refreshCustomers()
    }

    /// Refreshes a customer's key points in the background once enough new messages came in.
    func summarizeIfDue(_ chat: String) {
        guard useMemory, let r = memory.record(for: chat), !summarizing.contains(r.chatID),
              r.sinceSummary >= 20 || (r.summary.isEmpty && r.messages.count >= 10) else { return }
        summarizing.insert(r.chatID)
        let engine = makeEngine()
        Task { [weak self] in
            let result = try? await engine.reply(to: PromptBuilder.summary(of: r))
            guard let self else { return }
            self.summarizing.remove(r.chatID)
            guard let text = result?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            self.memory.setSummary(String(text.prefix(300)), for: r.chatID)
            self.add(.info, "已更新「\(r.name)」的客户要点：\(text.prefix(60))")
        }
    }
}
