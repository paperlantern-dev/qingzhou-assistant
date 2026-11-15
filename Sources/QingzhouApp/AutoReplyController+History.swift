import Foundation
import QingzhouCore

/// How far 读以前的聊天 got.
struct HistoryRun: Equatable {
    var chatsDone = 0
    var maxChats: Int
    var messagesAdded = 0
    var lessonsAdded = 0
    var current = ""
    var finished = false
    var note = ""
}

/// 读以前的聊天: opens customer chats one by one, scrolls each up a few screens, and keeps what it
/// reads in customer memory (this Mac only). It only clicks chats and scrolls: nothing is typed
/// or sent. The owner's answers become lessons in his own words, cleaned of anything private.
extension AutoReplyController {
    static let historyMaxLessons = 80

    func startHistory(maxChats: Int, pagesPerChat: Int) {
        guard historyTask == nil else { return }
        guard !isRunning else {
            add(.warn, "先暂停自动回复，再读以前的聊天")
            return
        }
        history = HistoryRun(maxChats: maxChats)
        startEscWatcher()   // 双击 Esc stops it
        add(.info, "开始读以前的聊天：最多 \(maxChats) 位客户，每位往上翻 \(pagesPerChat) 屏（只读，不回复）")
        historyTask = Task { [weak self] in
            await self?.runHistory(maxChats: maxChats, pages: pagesPerChat)
            self?.historyTask = nil
            if self?.isRunning == false { self?.stopEscWatcher() }
        }
    }

    func stopHistory() {
        historyTask?.cancel()
        history?.note = "已停下"
    }

    private func runHistory(maxChats: Int, pages: Int) async {
        var seen = Set<String>()
        var listScrolls = 0
        var lessons = 0
        while (history?.chatsDone ?? 0) < maxChats, !Task.isCancelled {
            guard let snap = await read(forceOCR: true) else { finishHistory("找不到微信窗口"); return }
            let rows = HistoryStitch.rowNames(snap.listNames).filter { r in
                let n = TextMatch.normalize(r.name)
                return n.count >= 2 && !seen.contains(n) && !SystemChat.isSystem(r.name) && !isNeverReply(r.name)
            }
            add(.debug, "聊天列表：\(HistoryStitch.rowNames(snap.listNames).map(\.name).joined(separator: "、"))；还没读的 \(rows.count) 个")
            if rows.isEmpty {   // everything on screen done: the list further down
                guard listScrolls < 15, await scrollList(snap) else { break }
                listScrolls += 1
                continue
            }
            for row in rows where (history?.chatsDone ?? 0) < maxChats && !Task.isCancelled {
                seen.insert(TextMatch.normalize(row.name))
                guard await historyIdle("点开「\(row.name)」") else { finishHistory("电脑一直有人在用，先停下"); return }
                guard let opened = await openRow(row, from: snap) else { continue }
                let title = opened.conversation.title
                if GroupChat.isGroupTitle(title) || SystemChat.isSystem(title) || isNeverReply(title) { continue }
                history?.current = title
                let messages = await readUp(pages: pages, from: opened)
                let chat = ChatID.make(title: title)
                let added = memory.addHistory(chatID: chat, name: title, messages: messages)
                lessons += learnFromHistory(messages, limit: Self.historyMaxLessons - lessons)
                history?.chatsDone += 1
                history?.messagesAdded += added
                history?.lessonsAdded = lessons
                add(.info, "读完「\(title)」：\(messages.count) 条，新记下 \(added) 条")
            }
        }
        refreshCustomers()
        finishHistory(Task.isCancelled ? "已停下" : "")
    }

    /// Waits until mouse and keyboard were left alone a moment (up to 2 minutes): the chat is
    /// clicked and scrolled, which would get in the owner's way. False when stopped or timed out.
    private func historyIdle(_ action: String) async -> Bool {
        let deadline = Date().addingTimeInterval(120)
        while AutoSender.userIdleSeconds < min(idleSeconds, 2) {
            guard !Task.isCancelled, Date() < deadline else { return false }
            history?.note = "等你停下鼠标键盘再\(action)"
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        history?.note = ""
        return !Task.isCancelled
    }

    private func finishHistory(_ note: String) {
        history?.finished = true
        history?.current = ""
        if !note.isEmpty { history?.note = note }
        let h = history
        add(.info, "读以前的聊天结束：\(h?.chatsDone ?? 0) 位客户，新记下 \(h?.messagesAdded ?? 0) 条，学到 \(h?.lessonsAdded ?? 0) 条你的说法")
    }

    /// Clicks a row in the chat list; returns the chat now open when its title fits the row.
    private func openRow(_ row: UnreadRow, from snap: Snapshot) async -> Snapshot? {
        guard let pid = snap.window.owningApplication?.processID else { return nil }
        let f = snap.window.frame
        let point = CGPoint(x: f.minX + target.layout.sidebarWidth * 0.6, y: f.minY + row.y + 12)
        do { try await AutoSender.click(point, inPID: pid, windowFrame: f) } catch {
            add(.error, "点开「\(row.name)」失败：\(error.localizedDescription)")
            return nil
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let now = await read(forceOCR: true) else { return nil }
        let want = TextMatch.normalize(row.name).replacingOccurrences(of: "…", with: "")
        let got = TextMatch.normalize(now.conversation.title)
        guard want.count >= 2, got.contains(want) || want.contains(got) || TextMatch.similar(got, want) else {
            add(.debug, "点了「\(row.name)」，打开的是「\(now.conversation.title)」，跳过")
            return nil
        }
        return now
    }

    /// Scrolls the open chat up screen by screen, then back down; returns everything read, oldest first.
    private func readUp(pages: Int, from first: Snapshot) async -> [StoredMessage] {
        let stored = { (s: Snapshot) in s.conversation.bubbles.map { StoredMessage(fromMe: $0.fromMe, text: $0.text) } }
        var screens = [stored(first)]
        guard let pid = first.window.owningApplication?.processID else { return stored(first) }
        let f = first.window.frame
        let pane = CGPoint(x: f.minX + target.layout.sidebarWidth + (f.width - target.layout.sidebarWidth) / 2,
                           y: f.minY + target.layout.headerHeight + (f.height - target.layout.headerHeight - target.layout.inputHeight) / 2)
        var scrolled = 0
        for _ in 0..<pages where !Task.isCancelled {
            guard await historyIdle("往上翻") else { break }
            try? await AutoSender.scroll(at: pane, lines: 8, times: 2, inPID: pid, windowFrame: f)
            scrolled += 1
            guard let now = await read(forceOCR: true), ChatID.same(now.chat, first.chat) else { break }
            let page = stored(now)
            if let last = screens.last, page.map(\.text) == last.map(\.text) { break }   // the top: nothing more
            screens.append(page)
        }
        // Back to the newest messages, so the chat looks as before.
        if scrolled > 0 { try? await AutoSender.scroll(at: pane, lines: -8, times: 2 * scrolled + 4, inPID: pid, windowFrame: f) }
        return HistoryStitch.join(pagesNewestFirst: screens)
    }

    /// Scrolls the chat list down to the next rows; false when it did not move.
    private func scrollList(_ snap: Snapshot) async -> Bool {
        guard let pid = snap.window.owningApplication?.processID else { return false }
        let f = snap.window.frame
        let point = CGPoint(x: f.minX + target.layout.sidebarWidth * 0.6, y: f.minY + f.height * 0.6)
        try? await AutoSender.scroll(at: point, lines: -6, times: 2, inPID: pid, windowFrame: f)
        guard let after = await read(forceOCR: true) else { return false }
        return after.listNames.map(\.name) != snap.listNames.map(\.name)
    }

    /// The owner's answers in old chats, kept as lessons in his own words. Returns how many were added.
    private func learnFromHistory(_ messages: [StoredMessage], limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        let known = Set(lessons.lessons.map { TextMatch.normalize($0.question) })
        var added = 0
        for p in HistoryClean.pairs(messages).reversed() where added < limit {   // newest first
            let key = TextMatch.normalize(p.question)
            guard !known.contains(key) else { continue }
            lessons.add(Lesson(kind: .ownerSaid, question: p.question, draft: "", final: p.answer))
            added += 1
        }
        return added
    }
}
