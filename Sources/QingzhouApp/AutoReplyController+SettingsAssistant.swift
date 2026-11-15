import Foundation
import QingzhouCore

/// Everything a confirmed change list touched, as it was before, so 撤销 can put it back.
struct SettingsUndo {
    let options: AssistantOptions
    let replyMode: ReplyMode
    let replyToGroups: Bool
    let voiceToText: Bool
    let outreachEnabled: Bool
    let maxPerHour: Int
    let maxPerChatPerHour: Int
    let files: [URL: String?]   // knowledge files as they were (nil: did not exist)
    let summary: [String]
}

/// “✨ 跟轻舟说”: plain words in, a change list out, applied only when the owner confirms.
extension AutoReplyController {
    func settingsSnapshot(page: String = "") -> SettingsSnapshot {
        var snap = SettingsSnapshot(rules: options.triggers, persona: options.persona, priceItems: priceTable()?.items ?? [],
                         neverReply: options.neverReply, replyAll: replyMode == .all, confirmFirst: options.assistMode,
                         replyToGroups: replyToGroups, maxPerHour: maxPerHour, maxPerChatPerHour: maxPerChatPerHour,
                         alertsAvailable: !alertAddress.isEmpty)
        snap.page = page
        snap.soldOut = options.soldOut
        snap.facts = todayFacts()
        return snap
    }

    /// How today went, in a few lines, so 小轻舟 can answer questions about it.
    func todayFacts() -> String {
        var lines = ["运行状态：\(isRunning ? "运行中" : "没在运行")", "今天已回复 \(repliesToday) 条"]
        if needsHuman.isEmpty, drafts.isEmpty {
            lines.append("没有等店主处理的")
        } else {
            let people = needsHuman.map { "\($0.who)（\($0.reason)：\($0.message.prefix(30))）" }
            lines.append("等店主处理 \(needsHuman.count + drafts.count) 件：" + (people + drafts.map { "\($0.who)（草稿）" }).joined(separator: "、"))
        }
        if !waitingReservations.isEmpty {
            lines.append("留货：" + waitingReservations.map { "\($0.record.name) \($0.reservation.item)" }.joined(separator: "、"))
        }
        lines.append("学到等确认的问答 \(answerSuggestions.count) 条；聊过的客户 \(customers.count) 位")
        if let price = priceTable(),
           let date = (try? FileManager.default.attributesOfItem(atPath: price.url.path))?[.modificationDate] as? Date {
            let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
            lines.append("价格表 \(price.items.count) 样，\(days == 0 ? "今天改过" : "\(days) 天没改")")
        }
        lines.append(options.soldOut.isEmpty ? "没有标成卖完的货" : "标成卖完的：" + options.soldOut.joined(separator: "、"))
        lines.append(summaryFacts())
        if engine == .api, let api = activeApi { lines.append("回复用的模型：\(api.name) \(api.model)") }
        if engine == .ollama { lines.append("回复用的模型：本机 \(ollamaModel)") }
        return lines.joined(separator: "；")
    }

    /// The first price table in the knowledge folder: its file and items.
    func priceTable() -> (url: URL, items: [Catalog.Item])? {
        for f in kb?.files ?? [] where f.lowercased().hasSuffix(".csv") {
            let url = kbFolder.appendingPathComponent(f)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let items = Catalog.items(csv: text)
                if !items.isEmpty { return (url, items) }
            }
        }
        return nil
    }

    /// The owner's speaking style plus what is in stock, as the reply prompt gets it.
    var replyPersona: String { options.persona + "\n\n" + Stock.note(soldOut: options.soldOut) }

    /// Asks the model what to change. Nothing is changed here.
    func planSettings(_ request: String, page: String = "") async -> SettingsPlan {
        ensureKBFresh()
        let snapshot = settingsSnapshot(page: page)
        // The last few exchanges, so “再加一个”“改成 88” are understood (fewer for a small local model).
        let history = chatLog.recent(rounds: engine == .ollama ? 6 : 12)
        add(.info, "跟轻舟说：\(request)")
        do {
            let raw = try await makeEngine().reply(to: SettingsAssistant.prompt(request: request, snapshot: snapshot,
                                                                                history: history))
            let plan = SettingsAssistant.plan(from: raw.text, snapshot: snapshot)
            add(.info, "修改单：\(plan.changes.count) 项" + (plan.problems.isEmpty ? "" : "，\(plan.problems.count) 项做不了"))
            return plan
        } catch {
            add(.error, "没能问到 AI：\(error.localizedDescription)")
            return SettingsPlan(changes: [], problems: ["没能问到 AI：\(error.localizedDescription)"], reply: "")
        }
    }

    /// One turn with 小轻舟: asks the model, tries a customer's question the real way when asked,
    /// and keeps both lines in the chat. Returns the plan (changes still wait for 确认).
    func talkToAssistant(_ request: String, page: String = "") async -> SettingsPlan {
        let plan = await planSettings(request, page: page)   // the history it sends is before this line
        addChat(request, mine: true)
        var answer = plan.reply.isEmpty ? (plan.changes.isEmpty ? "我没听明白，换个说法试试？" : "帮你改这些：") : plan.reply
        if let q = plan.customerQuestion {
            let tried = await askTest(q)
            let said = tried.reply?.messages.joined(separator: "\n") ?? ""
            answer += "\n\n客人问：\(q)\n" + (said.isEmpty ? "（没答出来：\(tried.error ?? "再试一次")）" : "会回：\n\(said)")
        }
        addChat(answer, mine: false)
        return plan
    }

    /// Makes the confirmed changes; keeps what they replaced for 撤销.
    func applySettings(_ changes: [SettingChange]) {
        guard !changes.isEmpty else { return }
        let price = priceTable()
        var files: [URL: String?] = [:]
        let learned = kbFolder.appendingPathComponent(LearnedQA.fileName)
        if changes.contains(where: { if case .addAnswer = $0 { return true }; return false }) {
            files[learned] = try? String(contentsOf: learned, encoding: .utf8)
        }
        if let price, changes.contains(where: { if case .setPrice = $0 { return true }; return false }) {
            files[price.url] = try? String(contentsOf: price.url, encoding: .utf8)
        }
        let undo = SettingsUndo(options: options, replyMode: replyMode, replyToGroups: replyToGroups, voiceToText: voiceToText,
                                outreachEnabled: outreachEnabled, maxPerHour: maxPerHour,
                                maxPerChatPerHour: maxPerChatPerHour, files: files, summary: changes.map(\.summary))

        var next = options
        next.triggers = SettingsAssistant.apply(changes, to: next.triggers)
        for c in changes {
            switch c {
            case .setPersona(let text): next.persona = text
            case .confirmFirst(let on): next.assistMode = on
            case .revisit(let on): next.revisitOn = on
            case .alerts(let on): next.alertsOn = on
            case .neverReplyAdd(let names): next.neverReply += names
            case .neverReplyRemove(let names): next.neverReply.removeAll { names.contains($0) }
            case .soldOut(let names): next.soldOut = (next.soldOut + names.filter { !next.soldOut.contains($0) })
            case .backInStock(let names): next.soldOut.removeAll { names.contains($0) }
            case .replyAll(let all): replyMode = all ? .all : .confident
            case .replyToGroups(let on): replyToGroups = on
            case .voiceToText(let on): voiceToText = on
            case .outreach(let on): outreachEnabled = on
            case .maxPerHour(let n): maxPerHour = n
            case .maxPerChatPerHour(let n): maxPerChatPerHour = n
            case .addAnswer(let q, let a):
                do { try LearnedQA.append(question: Privacy.redact(q).text, answer: Privacy.redact(a).text, to: kbFolder) } catch {
                    add(.error, "没能写进知识库：\(error.localizedDescription)")
                }
            case .setPrice(let item, let spec, let newPrice):
                if let price, let text = try? String(contentsOf: price.url, encoding: .utf8),
                   let changed = Catalog.settingPrice(csv: text, item: item, spec: spec, to: newPrice) {
                    do { try changed.write(to: price.url, atomically: true, encoding: .utf8) } catch {
                        add(.error, "没能改价格表：\(error.localizedDescription)")
                    }
                } else {
                    add(.warn, "价格表里没找到唯一的“\(item)”，没改")
                }
            default: break   // rule changes were applied above
            }
        }
        options = next
        if !files.isEmpty { reloadKB() }
        settingsUndo = undo
        add(.info, "已按你说的改好：" + changes.map(\.summary).joined(separator: "；"))
    }

    /// Puts back what the last confirmed change list replaced.
    func undoSettings() {
        guard let u = settingsUndo else { return }
        options = u.options
        replyMode = u.replyMode
        replyToGroups = u.replyToGroups
        voiceToText = u.voiceToText
        outreachEnabled = u.outreachEnabled
        maxPerHour = u.maxPerHour
        maxPerChatPerHour = u.maxPerChatPerHour
        for (url, text) in u.files {
            if let text { try? text.write(to: url, atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(at: url) }
        }
        if !u.files.isEmpty { reloadKB() }
        settingsUndo = nil
        add(.info, "已撤销：" + u.summary.joined(separator: "；"))
    }
}

/// 小轻舟's saved talk.
extension AutoReplyController {
    func loadChat() { assistantChat = chatLog.turns }

    func addChat(_ text: String, mine: Bool) {
        chatLog.append(ChatTurn(mine: mine, text: text))
        assistantChat = chatLog.turns
    }

    func clearChat() {
        chatLog.clear()
        assistantChat = []
    }
}
