import Foundation
import QingzhouCore

/// 主动智能 (off by default): once a day, greet a few customers who went quiet. It goes against
/// “只回复、不追单”, so only the user can turn it on.
extension AutoReplyController {
    private static let plannedKey = "revisitPlannedAt"
    /// When today's greetings were planned (tests reset it).
    static var revisitPlannedAt: Date? = {
        let t = UserDefaults.standard.double(forKey: plannedKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }()

    /// Whether a planned message may go out: greetings need 主动智能, scheduled ones 定时群发,
    /// the others 按许可主动联系.
    func mayRun(_ job: OutreachJob) -> Bool {
        switch job.reason {
        case .revisit: return options.revisitOn
        case .broadcast: return options.broadcastOn
        case .reservationArrived, .news: return outreachEnabled
        }
    }

    /// Once a day while running in the daytime: queue greetings, a few minutes apart.
    func planRevisitsIfDue(now: Date = Date()) {
        guard options.revisitOn, isRunning, outreachHours.contains(Calendar.current.component(.hour, from: now)) else { return }
        if let planned = Self.revisitPlannedAt, Calendar.current.isDate(planned, inSameDayAs: now) { return }
        Self.revisitPlannedAt = now
        if Self.saveSettings { UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.plannedKey) }
        let picks = Revisit.candidates(in: memory.all, now: now, minDays: options.revisitMinDays,
                                       maxDays: max(options.revisitMinDays, options.revisitMaxDays),
                                       limit: options.revisitPerDay) { r in
            isNeverReply(r.name) || GroupChat.isGroupTitle(r.name) || SystemChat.isSystem(r.name)
                || outreachQueue.contains { ChatID.same($0.chat, r.chatID) }
        }
        var at = now
        for r in picks {
            outreachQueue.append(OutreachJob(chat: r.chatID, who: r.name, reason: .revisit(days: Revisit.quietDays(r, now: now)),
                                             due: at))
            at = at.addingTimeInterval(Double.random(in: 300...900))
        }
        add(.info, picks.isEmpty ? "主动智能：今天没有需要问候的客户"
            : "主动智能：今天问候 \(picks.count) 位很久没聊的客户：\(picks.map(\.name).joined(separator: "、"))")
    }
}
