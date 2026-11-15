import Foundation
import QingzhouCore

/// 定时群发 (off by default): at set times the owner's own words go to chosen customers, one by
/// one. It goes against “不打扰客户”, so only the owner turns it on, and the limits are tight.
extension AutoReplyController {
    /// What a queued broadcast message belongs to (the queue's job only carries the text).
    struct BroadcastSend {
        let broadcast: UUID
        let picture: String?
    }

    /// Queued broadcast messages, by job id.
    static var broadcastSends: [UUID: BroadcastSend] = [:]

    /// Pictures chosen for broadcasts are copied here, so they are still there when the time comes.
    static var broadcastPictureFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("轻舟助手/图片", isDirectory: true)
    }

    /// Copies a picture the owner chose into the app's own folder; returns the copy.
    static func copyBroadcastPicture(from source: URL) throws -> URL {
        let folder = broadcastPictureFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let copy = folder.appendingPathComponent("群发-\(UUID().uuidString.prefix(8)).\(ext)")
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    /// Who a broadcast reaches among `records`: never-reply people, groups and system chats are left out.
    func broadcastRecipients(_ b: Broadcast, in records: [CustomerRecord]) -> [CustomerRecord] {
        b.recipients(from: records) { r in
            r.chatID.hasPrefix("群|") || GroupChat.isGroupTitle(r.name) || SystemChat.isSystem(r.name)
                || isNeverReply(r.name)
        }
    }

    // MARK: Planning

    /// Queues the scheduled messages that are due (only when 定时群发 is on, while running, in the daytime).
    func planBroadcastsIfDue(now: Date = Date()) {
        guard options.broadcastOn, isRunning,
              outreachHours.contains(Calendar.current.component(.hour, from: now)) else { return }
        dropStaleBroadcastSends(now: now)
        let due = options.broadcasts.filter { $0.isDue(at: now) }
        guard !due.isEmpty else { return }
        due.forEach { queueBroadcast($0, now: now) }
        let ran = Set(due.map(\.id))
        options.broadcasts = options.broadcasts.map { b in
            guard ran.contains(b.id) else { return b }
            var done = b
            done.lastRun = now
            return done
        }
    }

    /// One message per recipient not already waiting for one, at most `Broadcast.maxPerRun`, 1–3 minutes apart.
    private func queueBroadcast(_ b: Broadcast, now: Date) {
        Self.broadcastSends = Self.broadcastSends.filter { id, _ in outreachQueue.contains { $0.id == id } }
        let all = broadcastRecipients(b, in: memory.all)
        let text = Broadcast.oneLine(b.text)
        var people: [CustomerRecord] = []
        var left = 0
        var at = now
        for (i, r) in all.enumerated() {
            if people.count == Broadcast.maxPerRun { left = all.count - i; break }
            // Already waiting for a message (also when OCR read the name a little differently).
            if outreachQueue.contains(where: { ChatID.same($0.chat, r.chatID) }) { continue }
            let job = OutreachJob(chat: r.chatID, who: r.name, reason: .broadcast(text: text), due: at)
            Self.broadcastSends[job.id] = BroadcastSend(broadcast: b.id, picture: b.picture)
            outreachQueue.append(job)
            people.append(r)
            at = at.addingTimeInterval(Double.random(in: 60...180))
        }
        guard !people.isEmpty else {
            add(.info, "定时群发：「\(text.prefix(16))」这次没有可发的客户")
            return
        }
        add(.info, "定时群发：「\(text.prefix(16))」安排发给 \(people.count) 位，每人间隔 1–3 分钟："
            + people.map(\.name).joined(separator: "、")
            + (left > 0 ? "（一次最多 \(Broadcast.maxPerRun) 位，其余 \(left) 位这次不发）" : ""))
        note(.outreach, who: "定时群发", title: "已安排给 \(people.count) 位客户", detail: "“\(text.prefix(30))”")
    }

    // MARK: Changes from the settings card

    /// 新建群发: saved switched on, counted from now (a time already past today waits for the next one).
    func addBroadcast(_ b: Broadcast) {
        options.broadcasts = options.broadcasts + [b.activated()]
        add(.info, "新建定时群发：\(b.schedule.label()) ·「\(b.text.prefix(16))」")
    }

    /// Switches one broadcast on (counted from now) or off (its waiting messages are cancelled).
    func setBroadcast(_ id: UUID, enabled on: Bool) {
        options.broadcasts = options.broadcasts.map { b in
            guard b.id == id else { return b }
            if on { return b.activated() }
            var off = b
            off.enabled = false
            return off
        }
        if !on { cancelBroadcastSends(of: id) }
    }

    func deleteBroadcast(_ id: UUID) {
        options.broadcasts = options.broadcasts.filter { $0.id != id }
        cancelBroadcastSends(of: id)
    }

    /// The 定时群发 switch. Off cancels what is waiting; on counts from now, so times already past
    /// today are not made up.
    func setBroadcastOn(_ on: Bool) {
        var next = options
        next.broadcastOn = on
        if on { next.broadcasts = next.broadcasts.map { $0.enabled ? $0.activated() : $0 } }
        options = next
        if !on { cancelBroadcastSends() }
        add(.info, on ? "定时群发已打开" : "定时群发已关闭")
    }

    /// Takes waiting broadcast messages out of the queue: those of one broadcast, or all of them.
    func cancelBroadcastSends(of id: UUID? = nil) {
        let n = removeBroadcastSends { id == nil || Self.broadcastSends[$0.id]?.broadcast == id }
        if n > 0 { add(.info, "定时群发：取消了 \(n) 条还没发的消息") }
    }

    /// Messages that could not go out on the day they were planned are dropped, never sent late.
    private func dropStaleBroadcastSends(now: Date) {
        let n = removeBroadcastSends { !Calendar.current.isDate($0.due, inSameDayAs: now) }
        if n > 0 { add(.info, "定时群发：\(n) 条消息当天没发出去，已取消（不会补发）") }
    }

    /// Removes the waiting broadcast messages that match; returns how many. The queue is only
    /// changed when something matches (this runs every round).
    private func removeBroadcastSends(where match: (OutreachJob) -> Bool) -> Int {
        let gone = outreachQueue.filter { job in
            if case .broadcast = job.reason { return match(job) }
            return false
        }
        guard !gone.isEmpty else { return 0 }
        let ids = Set(gone.map(\.id))
        outreachQueue.removeAll { ids.contains($0.id) }
        gone.forEach { Self.broadcastSends[$0.id] = nil }
        return gone.count
    }

    // MARK: Sending

    /// Sends a broadcast message into the open chat exactly as the owner wrote it, then its picture.
    /// Also in 辅助模式: the owner wrote these words and chose the time.
    func sendBroadcast(_ job: OutreachJob, text: String) async {
        let picture = Self.broadcastSends[job.id]?.picture
        guard isRunning, let now = await read(forceOCR: true), ChatID.same(now.chat, job.chat),
              now.conversation.pendingIncoming.isEmpty else { return }
        outreachQueue.removeAll { $0.id == job.id }
        Self.broadcastSends[job.id] = nil
        if dryRun {
            add(.warn, "【\(job.who)】演练模式，不发送。拟定时群发：\(text)" + (picture == nil ? "" : "（再发一张图片）"))
            return
        }
        let method: String
        do {
            guard let sent = try await deliver(text, in: now, chat: job.chat) else {
                add(.error, "定时群发没有确认发出（\(job.who)）：\(text)")
                return
            }
            method = sent
        } catch {
            refreshPermissions()
            add(.error, "定时群发发送失败（\(job.who)）：\(error.localizedDescription)")
            return
        }
        limiter.record(chat: job.chat)
        sentCount += 1
        add(.sent, "【\(job.who)】我（定时群发）：\(text)\n你写的原话 · \(method) · 已在窗口中确认")
        let withPicture = await sendBroadcastPicture(picture, to: job)
        note(.outreach, who: job.who, title: "定时群发", detail: "“\(text)”" + (withPicture ? " · 带图片" : ""))
    }

    /// The broadcast's picture, a moment after its text. true = it went out.
    private func sendBroadcastPicture(_ path: String?, to job: OutreachJob) async -> Bool {
        guard let path else { return false }
        let file = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            add(.warn, "【\(job.who)】定时群发的图片找不到了（\(file.lastPathComponent)），只发了文字")
            return false
        }
        if let why = limiter.blockReason(chat: job.chat) {
            add(.warn, "【\(job.who)】定时群发的图片没发：\(why)")
            return false
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard isRunning, let fresh = await read(forceOCR: true), ChatID.same(fresh.chat, job.chat) else {
            add(.warn, "【\(job.who)】会话变了，定时群发的图片没发")
            return false
        }
        do {
            guard let method = try await deliverImage(file, in: fresh, chat: job.chat) else {
                add(.warn, "【\(job.who)】定时群发的图片没有确认发出")
                return false
            }
            limiter.record(chat: job.chat)
            sentCount += 1
            add(.sent, "【\(job.who)】我（定时群发·图片）：\(file.lastPathComponent)\n\(method) · 已在窗口中确认")
            return true
        } catch {
            refreshPermissions()
            add(.error, "【\(job.who)】定时群发的图片发送失败：\(error.localizedDescription)")
            return false
        }
    }
}
