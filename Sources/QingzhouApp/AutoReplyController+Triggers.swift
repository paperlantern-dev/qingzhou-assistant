import Foundation
import QingzhouCore

/// 关键词触发: the owner's set text or picture, or straight to the owner, before any AI reply.
extension AutoReplyController {
    /// Runs the first matching rule for the customer's newest message. true = handled (no AI reply).
    /// A missing picture, or a text or picture that did not go out, leaves it to the AI (false).
    func handleTrigger(_ snap: Snapshot, chat: String, who: String, key: String, incoming: String) async -> Bool {
        let pending = snap.conversation.pendingIncoming.map(\.text)
        guard let match = TriggerRule.match(options.triggers, pending: pending) else { return false }
        let rule = match.rule, keyword = match.keyword
        add(.info, "【\(who)】关键词“\(keyword)”触发规则：\(rule.action.summary)")
        step("关键词触发", "“\(keyword)” → \(rule.action.summary)")
        switch rule.action {
        case .handOver:
            markHandled(chat, key)
            addHuman(chat: chat, who: who, message: incoming, reason: rule.handOverReason(keyword: keyword))
            watchOwnerWording(chat: chat, who: who, question: incoming)
            return true
        case .sendCatalog:
            ensureKBFresh()
            // The list a customer gets leaves out what is sold out.
            guard let kb, let text = Catalog.text(folder: kb.folder, files: kb.files, soldOut: options.soldOut) else {
                add(.warn, "【\(who)】知识库里没有价格表（csv：品名、规格、价格），这次让 AI 照常回复")
                return false
            }
            return await sendTriggered(text: text, picture: nil, keyword: keyword,
                                       chat: chat, who: who, key: key, incoming: incoming)
        case .sendText(let text):
            return await sendTriggered(text: text, picture: nil, keyword: keyword,
                                       chat: chat, who: who, key: key, incoming: incoming)
        case .sendImage(let path):
            let picture = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: picture.path) else {
                add(.warn, "【\(who)】规则里的图片找不到了（\(picture.lastPathComponent)），这次让 AI 照常回复")
                return false
            }
            return await sendTriggered(text: "", picture: picture, keyword: keyword,
                                       chat: chat, who: who, key: key, incoming: incoming)
        }
    }

    /// Sends the rule's text or picture; in 辅助模式 it waits on 首页 as a draft, in 演练模式 it is only logged.
    private func sendTriggered(text: String, picture: URL?, keyword: String, chat: String,
                               who: String, key: String, incoming: String) async -> Bool {
        let basis = "关键词触发：\(keyword)"
        let shown = picture.map { "[图片] \($0.lastPathComponent)" } ?? text
        if let why = limiter.blockReason(chat: chat) {
            add(.warn, "【\(who)】\(basis)，但\(why)")
            return true
        }
        if options.assistMode, !dryRun {
            step("放到首页，等你确认")
            markHandled(chat, key)
            addDraft(chat: chat, who: who, question: incoming, text: text, basis: basis, picture: picture?.path)
            return true
        }
        if dryRun {
            markHandled(chat, key)
            add(.warn, "【\(who)】演练模式，不发送。拟回复：\(shown)（\(basis)）")
            return true
        }
        guard let screen = await waitLikeAPerson(typing: text, chat: chat, key: key, who: who) else {
            return true   // the chat moved on: the next round looks again
        }
        do {
            step("正在发送", shown)
            let method: String?
            if let picture {
                method = try await deliverImage(picture, in: screen, chat: chat)
            } else {
                method = try await deliver(text, in: screen, chat: chat)
            }
            guard let method else {
                guard isRunning else { return true }   // stopped meanwhile: it is answered after the restart
                if picture != nil {   // it may have gone out after all: never paste it again, ask the owner
                    markHandled(chat, key)
                    addHuman(chat: chat, who: who, message: incoming,
                             reason: "图片可能没发出去（微信里可能是红色感叹号），请你看一下")
                    return true
                }
                add(.warn, "【\(who)】\(basis)：这段话没有确认发出，这次让 AI 照常回复")
                return false
            }
            step("已发送", method)
            markHandled(chat, key)
            limiter.record(chat: chat)
            sentCount += 1
            add(.sent, "【\(who)】我：\(shown)\n\(basis) · \(method) · 已在窗口中确认")
            note(.replied, who: who, title: "已回复（关键词）", detail: "“\(shown)” · \(basis)")
            return true
        } catch {
            refreshPermissions()
            guard isRunning else { return true }
            if picture != nil {   // a failed paste may still have left something behind: ask the owner
                markHandled(chat, key)
                addHuman(chat: chat, who: who, message: incoming, reason: "图片没发出去（\(error.localizedDescription)），请你看一下")
                return true
            }
            add(.error, "【\(who)】\(basis)：没发出去（\(error.localizedDescription)），这次让 AI 照常回复")
            return false
        }
    }

    /// Like an AI reply: “read” the message and “type” (a picture takes a moment to pick), then look
    /// again. nil when they wrote more, someone answered, or another chat is open.
    private func waitLikeAPerson(typing text: String, chat: String, key: String, who: String) async -> Snapshot? {
        var rng = SystemRandomNumberGenerator()
        let pacer = HumanPacer(config: pacing)
        let wait = pacer.readDelay(using: &rng) + (text.isEmpty ? 1 : pacer.typingDelay(for: text, using: &rng))
        status = String(format: "关键词触发，%.0f 秒后发送", wait)
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        guard isRunning, let now = await read(forceOCR: true) else { return nil }
        guard ChatID.same(now.chat, chat) else {
            add(.warn, "当前会话已不是「\(who)」，这条先不发，稍后重新处理")
            return nil
        }
        guard TextMatch.similar(now.conversation.pendingKey, key) else {
            add(.warn, now.conversation.pendingKey.isEmpty ? "已有人回复，放弃这条" : "对方又发了新消息，重新处理")
            return nil
        }
        return now
    }
}
