import AppKit
import QingzhouCore

/// A reply written in 辅助模式, waiting on 首页 for the user to send, change or turn down.
struct Draft: Identifiable {
    let id = UUID()
    let time = Date()
    let chat: String          // ChatID
    let who: String
    let question: String      // what they said ("" for a 主动智能 greeting)
    let text: String          // what the assistant wrote: one or two messages (see DraftText)
    let basis: String
    let proactive: Bool       // a 主动智能 greeting, not an answer
    var approved: String?     // the text to send, once the user clicked 发送
    var liked = false
    var problem: String?      // why the last attempt to send it failed
    var picture: String? = nil   // a picture to send (its path) instead of text, e.g. from 关键词触发

    /// How the draft reads in the log and on 首页.
    var shown: String { picture.map { "[图片] " + URL(fileURLWithPath: $0).lastPathComponent } ?? text }
}

/// 辅助模式 (drafts the user sends) and the 不自动回复 list.
extension AutoReplyController {
    var neverReplyList: NeverReplyList { NeverReplyList(options.neverReply) }

    func isNeverReply(_ name: String) -> Bool { neverReplyList.contains(name) }

    /// Adds someone to the 不自动回复 list (dropping their drafts and planned messages), or takes them off.
    func setNeverReply(_ name: String, _ on: Bool) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let one = NeverReplyList([n])
        if on {
            if !isNeverReply(n) { options.neverReply.append(n) }
            drafts.removeAll { one.contains($0.who) }
            outreachQueue.removeAll { one.contains($0.who) }
            add(.info, "「\(n)」加入“不自动回复”名单")
        } else {
            options.neverReply.removeAll { NeverReplyList([$0]).contains(n) }
            add(.info, "「\(n)」移出“不自动回复”名单")
        }
    }

    func updateDockBadge() {
        let n = needsHuman.count + drafts.count
        NSApp.dockTile.badgeLabel = n == 0 ? nil : "\(n)"
    }

    /// The contact-list row showing this name (names may be cut off with “…”).
    func listRow(named name: String, in snap: Snapshot) -> UnreadRow? {
        let wanted = TextMatch.normalize(name)
        return snap.listNames.first { r in
            let n = TextMatch.normalize(r.name)
            return n.count >= 2 && (wanted.contains(n) || n.contains(wanted) || TextMatch.similar(n, wanted))
        }
    }

    /// Keeps a reply as a draft instead of sending it; a newer draft replaces the older one of that chat.
    /// `picture`: a picture file to send instead of text.
    func addDraft(chat: String, who: String, question: String, text: String, basis: String, proactive: Bool = false,
                  picture: String? = nil) {
        drafts.removeAll { ChatID.same($0.chat, chat) && $0.approved == nil }
        let draft = Draft(chat: chat, who: who, question: question, text: text, basis: basis, proactive: proactive,
                          picture: picture)
        drafts.append(draft)
        let what = proactive ? "主动问候写好了" : picture == nil ? "回复写好了" : "图片准备好了"
        add(.info, "【\(who)】辅助模式：\(what)，等你在首页确认：\(draft.shown)")
        note(.drafted, who: who, title: "\(what) · 等你确认", detail: "“\(draft.shown)”")
        NSSound.beep()
        alertIfWanted(chat: chat, who: who, message: question.isEmpty ? text : question,
                      reason: "辅助模式：回复已写好，等你点发送")
    }

    /// 发送: the next round sends `text` (the user may have changed it) into that chat.
    /// A picture draft is sent as its picture (its text may be empty).
    func approveDraft(_ id: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = drafts.firstIndex(where: { $0.id == id }), !t.isEmpty || drafts[i].picture != nil else { return }
        drafts[i].approved = t
        drafts[i].problem = nil
        needsLook = true
    }

    /// 👍: this is how the owner likes it; remembered as an example for later replies (text only).
    func likeDraft(_ id: UUID) {
        guard let i = drafts.firstIndex(where: { $0.id == id }), !drafts[i].liked, drafts[i].picture == nil else { return }
        drafts[i].liked = true
        lessons.add(Lesson(kind: .liked, question: drafts[i].question, draft: drafts[i].text))
    }

    /// 👎 不发: drops the draft; the reason is remembered so later replies avoid it.
    func rejectDraft(_ id: UUID, reason: String?) {
        guard let d = drafts.first(where: { $0.id == id }) else { return }
        drafts.removeAll { $0.id == id }
        if let reason, d.picture == nil {
            lessons.add(Lesson(kind: .rejected, question: d.question, draft: d.text, reason: reason))
        }
        add(.info, "【\(d.who)】草稿不发" + (reason.map { "（\($0)）" } ?? ""))
    }

    /// The owner answered in the chat app: that chat's waiting reply drafts are no longer needed.
    func dropAnsweredDrafts(chat: String) {
        drafts.removeAll { ChatID.same($0.chat, chat) && $0.approved == nil && !$0.proactive }
    }

    /// Sends the draft the user approved, opening its chat first if another one is showing.
    /// true = it acted this round (the caller looks again before doing anything else).
    func sendApprovedDraft(_ snap: Snapshot) async -> Bool {
        guard let d = drafts.first(where: { $0.approved != nil }), let text = d.approved else { return false }
        func fail(_ why: String) { failDraft(d, why) }
        guard ChatID.same(snap.chat, d.chat) else {
            if let row = listRow(named: d.who, in: snap) {
                await openChat(row, from: snap)
            } else {
                fail("左侧列表里找不到这个会话，请在\(target.name)里手动发")
            }
            return true
        }
        if !d.proactive, snap.conversation.bubbles.last?.fromMe == true {
            drafts.removeAll { $0.id == d.id }
            add(.info, "【\(d.who)】你已经在\(target.name)里回过了，这条草稿不发")
            return true
        }
        if let why = limiter.blockReason(chat: d.chat) { fail(why); return true }
        if let picture = d.picture {
            if await sendDraftPicture(d, URL(fileURLWithPath: picture), in: snap) { finishDraft(d) }
            return true
        }
        var screen = snap
        for (n, part) in DraftText.messages(text).enumerated() {
            if n > 0 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let fresh = await read(forceOCR: true), ChatID.same(fresh.chat, d.chat) else { break }
                screen = fresh
            }
            do {
                guard let method = try await deliver(part, in: screen, chat: d.chat) else {
                    if n == 0 { fail("窗口里没有出现这条消息，没确认发出"); return true }
                    add(.warn, "【\(d.who)】第二条没有确认发出：\(part)")
                    break
                }
                limiter.record(chat: d.chat)
                sentCount += 1
                add(.sent, "【\(d.who)】我（你确认过）：\(part)\n\(d.basis) · \(method) · 已在窗口中确认")
            } catch {
                refreshPermissions()
                if n == 0 { fail(error.localizedDescription); return true }
                break
            }
        }
        finishDraft(d, sent: text)
        if TextMatch.normalize(text) != TextMatch.normalize(d.text) {
            lessons.add(Lesson(kind: .rewritten, question: d.question, draft: d.text, final: text))
        }
        return true
    }

    /// The draft went out: drop it and write it down (`sent`: the text that went out; nil for a picture).
    private func finishDraft(_ d: Draft, sent: String? = nil) {
        drafts.removeAll { $0.id == d.id }
        note(.replied, who: d.who, title: d.proactive ? "主动问候（你确认过）" : "已回复（你确认过）",
             detail: "“\(sent ?? d.shown)”")
        if d.proactive {
            memory.update(chatID: d.chat, name: d.who) { $0.lastRevisitAt = Date() }
            refreshCustomers()
        }
    }

    /// The draft did not go out: it waits on 首页 again, saying why.
    private func failDraft(_ d: Draft, _ why: String) {
        if let i = drafts.firstIndex(where: { $0.id == d.id }) { drafts[i].approved = nil; drafts[i].problem = why }
        add(.warn, "【\(d.who)】草稿没有发出：\(why)")
    }

    /// Sends a picture draft. false = not sent (the draft says why).
    private func sendDraftPicture(_ d: Draft, _ file: URL, in snap: Snapshot) async -> Bool {
        do {
            guard let method = try await deliverImage(file, in: snap, chat: d.chat) else {
                failDraft(d, "窗口里没看到图片发出，没确认发出；请先看一眼\(target.name)再决定要不要重发")
                return false
            }
            limiter.record(chat: d.chat)
            sentCount += 1
            add(.sent, "【\(d.who)】我（你确认过）：\(d.shown)\n\(d.basis) · \(method) · 已在窗口中确认")
            return true
        } catch {
            refreshPermissions()
            failDraft(d, error.localizedDescription)
            return false
        }
    }
}
