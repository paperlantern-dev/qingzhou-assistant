import Foundation

/// 定时群发 (off by default): a fixed message the owner schedules for chosen customers.
/// It goes out exactly as written, at most once per scheduled time; missed times are never made up.
public struct Broadcast: Codable, Equatable, Identifiable {
    /// When it goes out. `weekday` as in Calendar: 1 = Sunday … 7 = Saturday.
    public enum Schedule: Codable, Equatable {
        case once(at: Date)
        case daily(hour: Int, minute: Int)
        case weekly(weekday: Int, hour: Int, minute: Int)
    }

    /// At most this many customers per run.
    public static let maxPerRun = 30
    /// The longest message the owner can save.
    public static let maxLength = 500

    public var id = UUID()
    public var text: String
    /// A picture sent after the text (file path), or nil.
    public var picture: String?
    /// Customer names; empty = everyone remembered.
    public var recipients: [String]
    public var schedule: Schedule
    public var enabled: Bool
    /// When it last went out.
    public var lastRun: Date?
    /// When it was saved or switched on: times before this don't count, so nothing goes out right away.
    public var activeSince: Date?

    public init(text: String, picture: String? = nil, recipients: [String] = [],
                schedule: Schedule = .daily(hour: 10, minute: 0), enabled: Bool = true) {
        self.text = text
        self.picture = picture
        self.recipients = recipients
        self.schedule = schedule
        self.enabled = enabled
    }

    /// Due at `now`: switched on, has words, and today's time has come but it has not gone out
    /// today (a one-time broadcast: not ever). Times missed on earlier days are never made up.
    public func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let time = schedule.time(on: now, calendar: calendar), time <= now,
              time >= (activeSince ?? .distantPast) else { return false }
        if case .once = schedule { return lastRun == nil }
        return (lastRun ?? .distantPast) < calendar.startOfDay(for: now)
    }

    /// A copy switched on at `now`: if today's time has already passed, it starts with the next one.
    /// Counted from the start of this minute, so “15:00” saved at 15:00 still goes out today.
    public func activated(at now: Date = Date(), calendar: Calendar = .current) -> Broadcast {
        var copy = self
        copy.enabled = true
        copy.activeSince = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        return copy
    }

    /// Who it goes to: the chosen names (matched loosely, like the never-reply list) or, with none
    /// chosen, everyone remembered. Never anyone who said “别发了” or whom `skip` leaves out
    /// (never-reply people, groups, system chats); each chat once. (OCR variants of a name are
    /// already one record in the memory store; the planner also skips chats already queued.)
    public func recipients(from records: [CustomerRecord],
                           skip: (CustomerRecord) -> Bool = { _ in false }) -> [CustomerRecord] {
        let chosen = NeverReplyList(recipients)
        var seen = Set<String>()
        return records.filter { r in
            r.optedOutAt == nil && (recipients.isEmpty || chosen.contains(r.name)) && !skip(r)
                && seen.insert(r.chatID).inserted
        }
    }

    /// The owner's words as one message: line breaks become spaces, ends trimmed.
    public static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, picture, recipients, schedule, enabled, lastRun, activeSince
    }

    /// Entries saved by an older version load with defaults. One whose schedule can't be read
    /// stays switched off (instead of failing, which would lose all settings).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try? c.decodeIfPresent(Schedule.self, forKey: .schedule)
        let on = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        picture = try c.decodeIfPresent(String.self, forKey: .picture)
        recipients = try c.decodeIfPresent([String].self, forKey: .recipients) ?? []
        schedule = saved ?? .daily(hour: 10, minute: 0)
        enabled = saved != nil && on
        lastRun = try c.decodeIfPresent(Date.self, forKey: .lastRun)
        activeSince = try c.decodeIfPresent(Date.self, forKey: .activeSince)
    }
}

extension Broadcast.Schedule {
    /// Its time on that day, or nil when it doesn't go out that day (or the time is impossible).
    public func time(on day: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .once(let at):
            return calendar.isDate(at, inSameDayAs: day) ? at : nil
        case .daily(let hour, let minute):
            return Self.clock(hour, minute, on: day, calendar)
        case .weekly(let weekday, let hour, let minute):
            guard calendar.component(.weekday, from: day) == weekday else { return nil }
            return Self.clock(hour, minute, on: day, calendar)
        }
    }

    /// “每天 09:05”, “每周三 18:30”, “11月6日 10:00 发一次”.
    public func label(calendar: Calendar = .current) -> String {
        switch self {
        case .once(let at):
            let c = calendar.dateComponents([.month, .day, .hour, .minute], from: at)
            return "\(c.month ?? 0)月\(c.day ?? 0)日 \(Self.hhmm(c.hour ?? 0, c.minute ?? 0)) 发一次"
        case .daily(let hour, let minute):
            return "每天 \(Self.hhmm(hour, minute))"
        case .weekly(let weekday, let hour, let minute):
            return "每\(Self.weekdayName(weekday)) \(Self.hhmm(hour, minute))"
        }
    }

    /// “周日” … “周六” (1 = Sunday, as in Calendar).
    public static func weekdayName(_ weekday: Int) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return (1...7).contains(weekday) ? names[weekday - 1] : "周?"
    }

    private static func hhmm(_ hour: Int, _ minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }

    private static func clock(_ hour: Int, _ minute: Int, on day: Date, _ calendar: Calendar) -> Date? {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
