import AppKit
import QingzhouCore

/// One line of “今天” on the home screen, in plain words.
struct Activity: Identifiable {
    enum Kind { case replied, handedOver, outreach, voice, drafted, learned }
    let id = UUID()
    let time = Date()
    let kind: Kind
    let who: String
    let title: String
    let detail: String
    /// For a reply the assistant wrote itself: what the customer said and what was answered,
    /// so the owner can teach a better answer from 动态.
    var question: String? = nil
    var reply: String? = nil
}

/// What the home screen, the customer screens and the panel header need from the controller.
extension AutoReplyController {
    func note(_ kind: Activity.Kind, who: String, title: String, detail: String, question: String? = nil, reply: String? = nil) {
        activity.append(Activity(kind: kind, who: who, title: title, detail: detail, question: question, reply: reply))
        // Kept on disk too, for the day's 小结 (the list above is gone after a restart).
        if kind == .replied { dayLog.addReply() }
        if kind == .handedOver, !who.isEmpty { dayLog.addHandOver(who: who, what: title.replacingOccurrences(of: " · 交给你", with: "")) }
        if activity.count > 200 { activity.removeFirst(activity.count - 200) }
    }

    /// Replies sent today (shown in the header).
    var repliesToday: Int {
        dayLog.record().replied
    }

    /// Reservations still waiting for “已到货”, newest first.
    var waitingReservations: [(record: CustomerRecord, reservation: Reservation)] {
        customers.flatMap { r in r.reservations.filter { $0.status == .waiting && !isQueued($0) }.map { (r, $0) } }
            .sorted { $0.reservation.createdAt > $1.reservation.createdAt }
    }

    /// “已到货” was clicked and the message waits to be sent.
    func isQueued(_ reservation: Reservation) -> Bool {
        outreachQueue.contains { job in
            if case .reservationArrived(let r) = job.reason { return r.id == reservation.id }
            return false
        }
    }

    /// The number on the 首页 tab: drafts and messages left for the user, plus reservations to act on.
    var homeBadge: Int { drafts.count + needsHuman.count + waitingReservations.count }

    /// The chat window was not found the last time it was looked for.
    var chatWindowMissing: Bool { status.hasPrefix("找不到") }

    private static var avatarCache: [URL: NSImage] = [:]

    /// A saved avatar never changes, so each picture is read from disk once.
    func avatar(of record: CustomerRecord) -> NSImage? {
        guard let url = memory.avatarURL(of: record) else { return nil }
        if let image = Self.avatarCache[url] { return image }
        let image = NSImage(contentsOf: url)
        Self.avatarCache[url] = image
        return image
    }

    func updateSummary(_ text: String, chat: String) {
        memory.setSummary(text, for: chat)
        refreshCustomers()
    }

    /// Cuts the customer's avatar out of the contact list on the left (it shows exactly as in the
    /// chat app), next to the row with their name.
    func saveAvatar(of chat: String, name: String, from snap: Snapshot) {
        let wanted = TextMatch.normalize(name)
        guard let row = snap.listNames.first(where: { r in
            let n = TextMatch.normalize(r.name).replacingOccurrences(of: "…", with: "")
            return n.count >= 2 && (wanted.contains(n) || n.contains(wanted) || TextMatch.similar(n, wanted))
        }) else { return }
        let scale = CGFloat(snap.image.width) / max(1, snap.window.frame.width)
        let side: CGFloat = 38
        let rect = CGRect(x: (target.layout.avatarRight - side + 1) * scale, y: (row.y - 3) * scale,
                          width: side * scale, height: side * scale)
        guard let crop = snap.image.cropping(to: rect), let png = WindowCapture.pngData(crop) else { return }
        memory.saveAvatar(png, for: chat, name: name)
        refreshCustomers()
    }

    /// “在微信里打开”: brings the chat app forward with that customer's chat open, for the user.
    func showInChatApp(_ chat: String) {
        Task {
            guard let snap = await read(forceOCR: true), let pid = snap.window.owningApplication?.processID else {
                add(.warn, "找不到「\(target.name)」的窗口")
                return
            }
            let f = snap.window.frame
            var point: CGPoint?
            if !ChatID.same(snap.chat, chat), let r = memory.record(for: chat) {
                let wanted = TextMatch.normalize(r.name)
                if let row = snap.listNames.first(where: { row in
                    let n = TextMatch.normalize(row.name).replacingOccurrences(of: "…", with: "")
                    return n.count >= 2 && (wanted.contains(n) || n.contains(wanted) || TextMatch.similar(n, wanted))
                }) {
                    point = CGPoint(x: f.minX + target.layout.sidebarWidth * 0.6, y: f.minY + row.y + 12)
                }
            }
            try? await AutoSender.showForUser(pid: pid, windowFrame: f, click: point)
        }
    }
}
