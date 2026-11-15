import AppKit
import QingzhouCore

/// Contacting a customer first, only with their permission: a reservation they asked for, or
/// news after they said “有好东西告诉我”. Never chasing orders or repurchase reminders.
extension AutoReplyController {
    /// Notes what the customer just said about reservations or hearing from us, with their words.
    func recordPermissions(_ parsed: ParsedReply, chat: String, who: String, quote: String) {
        guard !GroupChat.isGroupTitle(who), !SystemChat.isSystem(who),
              parsed.reservation != nil || parsed.consentInterests != nil || parsed.optOut else { return }
        memory.update(chatID: chat, name: who) { r in
            if let item = parsed.reservation {
                if item.contains("取消") {
                    if let i = r.reservations.lastIndex(where: { $0.status == .waiting }) { r.reservations[i].status = .cancelled }
                } else {
                    r.reservations.append(Reservation(item: item, quote: quote))
                }
            }
            if let interests = parsed.consentInterests {
                r.consent = Consent(interests: interests, quote: quote)
                r.optedOutAt = nil
            }
            if parsed.optOut {
                r.optedOutAt = Date()
                r.consent = nil
            }
        }
        if let item = parsed.reservation {
            add(.info, item.contains("取消") ? "「\(who)」取消了预留" : "记下「\(who)」的预留：\(item)（到货后在首页点“已到货”才会通知他）")
        }
        if let interests = parsed.consentInterests { add(.info, "「\(who)」同意有新货时通知他（感兴趣：\(interests)）") }
        if parsed.optOut {
            outreachQueue.removeAll { ChatID.same($0.chat, chat) && { if case .news = $0.reason { return true }; return false }($0) }
            add(.info, "「\(who)」不想再收到主动消息，已撤销新品通知")
        }
        refreshCustomers()
    }

    func refreshCustomers() {
        let all = memory.all
        if all != customers { customers = all }
        if memoryCount != memory.count { memoryCount = memory.count }
    }

    /// “已到货”: queue a message telling this customer that what they asked us to keep has arrived.
    func reservationArrived(chat: String, id: UUID) {
        guard let r = memory.record(for: chat), let res = r.reservations.first(where: { $0.id == id }) else { return }
        outreachQueue.append(OutreachJob(chat: r.chatID, who: r.name, reason: .reservationArrived(res), due: Date()))
        add(.info, "已安排通知「\(r.name)」：\(res.item) 到货了")
        note(.outreach, who: r.name, title: "到货通知已安排", detail: "\(res.item) · " + (isRunning ? "空闲时发送" : "开始自动回复后发送"))
    }

    func deleteReservation(chat: String, id: UUID) {
        guard let r = memory.record(for: chat) else { return }
        memory.update(chatID: r.chatID, name: r.name) { $0.reservations.removeAll { $0.id == id } }
        outreachQueue.removeAll { if case .reservationArrived(let x) = $0.reason { return x.id == id }; return false }
        refreshCustomers()
    }

    func removeConsent(chat: String) {
        guard let r = memory.record(for: chat) else { return }
        memory.update(chatID: r.chatID, name: r.name) { $0.consent = nil }
        refreshCustomers()
    }

    /// Customers a news message would go to: only those who said they want news, and whose
    /// interests fit the message (or who said anything is fine).
    func newsRecipients(for text: String) -> [CustomerRecord] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        return memory.all.filter { $0.wantsNews(about: t) }
    }

    /// “发布新品”: queue one message per consenting customer, spread out over a few minutes.
    @discardableResult
    func publish(_ announcement: String) -> Int {
        let text = announcement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        let people = newsRecipients(for: text)
        var at = Date()
        for r in people {
            outreachQueue.append(OutreachJob(chat: r.chatID, who: r.name, reason: .news(announcement: text, consent: r.consent!),
                                             due: at))
            at = at.addingTimeInterval(Double.random(in: 60...180))
        }
        add(.info, "新品通知已安排给 \(people.count) 位同意过的客户：\(text.prefix(30))")
        return people.count
    }

    /// Sends the next permitted message once it is due: only in the daytime, within the sending
    /// limits, and only when that chat is not in the middle of a conversation.
    func runOutreach(_ snap: Snapshot) async {
        guard let job = outreachQueue.first(where: { $0.due <= Date() && mayRun($0) }) else { return }
        guard outreachHours.contains(Calendar.current.component(.hour, from: Date())) else { return }
        guard limiter.blockReason(chat: job.chat) == nil else { return }
        let drop = { self.outreachQueue.removeAll { $0.id == job.id } }
        // Never-reply people, and with “只回名单里的人” on, anyone not on that list: nothing proactive.
        if isNeverReply(job.who) || listSkipReason(job.who, opening: false) != nil { drop(); return }
        if case .news = job.reason, memory.record(for: job.chat)?.welcomesNews != true { drop(); return }
        let greeting: Bool = { if case .revisit = job.reason { return true }; return false }()
        let broadcast: Bool = { if case .broadcast = job.reason { return true }; return false }()
        if broadcast, memory.record(for: job.chat)?.optedOutAt != nil {   // said “别发了” after it was planned
            drop()
            add(.info, "定时群发：「\(job.who)」说过不要再主动发消息，不发")
            return
        }
        // Open the chat first if another one is showing.
        guard ChatID.same(snap.chat, job.chat) else {
            if let row = listRow(named: job.who, in: snap) {
                await openChat(row, from: snap)
                needsLook = true
            } else if greeting {
                drop()
                add(.info, "主动智能：左侧列表里看不到「\(job.who)」，这次不问候")
            } else if broadcast {
                drop()
                add(.info, "定时群发：左侧列表里看不到「\(job.who)」，这次不发")
            } else {
                drop()
                addHuman(chat: job.chat, who: job.who, message: job.label, reason: "左侧列表里找不到这个会话，请你手动通知")
            }
            return
        }
        guard snap.conversation.pendingIncoming.isEmpty else { return }   // they are talking: answer first
        if case .broadcast(let text) = job.reason {   // the owner's own words: no model, sent as written
            await sendBroadcast(job, text: text)
            return
        }
        let record = memory.record(for: job.chat)
        guard let gen = try? await makeEngine().reply(to: PromptBuilder.outreach(job.reason, record: record)),
              isRunning else { return }
        let text = gen.text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? ""
        guard !text.isEmpty, text.count <= 80, !Privacy.containsPlaceholder(text) else { drop(); return }
        if greeting, text.count <= 6, text.contains("跳过") {
            drop()
            add(.info, "主动智能：和「\(job.who)」没有合适的话题，这次不问候")
            return
        }
        guard let now = await read(forceOCR: true), ChatID.same(now.chat, job.chat),
              now.conversation.pendingIncoming.isEmpty else { return }
        drop()
        if dryRun { add(.warn, "【\(job.who)】演练模式，不发送。拟主动发送：\(text)"); return }
        if greeting, options.assistMode {   // 辅助模式: the user decides on 首页
            addDraft(chat: job.chat, who: job.who, question: "", text: text, basis: "主动智能 · \(job.label)", proactive: true)
            return
        }
        let why = greeting ? "主动智能" : "客户许可过"
        do {
            guard let method = try await deliver(text, in: now, chat: job.chat) else {
                add(.error, "主动消息没有确认发出：\(text)")
                return
            }
            limiter.record(chat: job.chat)
            sentCount += 1
            if case .reservationArrived(let res) = job.reason {
                memory.update(chatID: job.chat, name: job.who) { r in
                    if let i = r.reservations.firstIndex(where: { $0.id == res.id }) {
                        r.reservations[i].status = .notified
                        r.reservations[i].notifiedAt = Date()
                    }
                }
                refreshCustomers()
            }
            if greeting {
                memory.update(chatID: job.chat, name: job.who) { $0.lastRevisitAt = Date() }
                refreshCustomers()
            }
            add(.sent, "【\(job.who)】我（主动·\(job.label)）：\(text)\n\(why) · \(method) · 已在窗口中确认")
            note(.outreach, who: job.who, title: job.label, detail: "“\(text)” · \(why)")
        } catch {
            add(.error, "主动消息发送失败：\(error.localizedDescription)")
        }
    }

}
