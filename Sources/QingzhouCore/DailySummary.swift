import Foundation

/// What happened on one day, kept on disk so it survives a restart.
public struct DayRecord: Codable, Equatable {
    public struct Item: Codable, Equatable {
        public var who: String
        public var what: String
        public init(who: String, what: String) {
            self.who = who
            self.what = what
        }
    }

    public var day: String            // yyyy-MM-dd
    public var replied = 0
    public var learned = 0
    public var handedOver: [Item] = []
    public var unanswered: [Item] = []   // questions the knowledge base had no answer for

    public init(day: String) { self.day = day }

    public var isEmpty: Bool { replied == 0 && learned == 0 && handedOver.isEmpty && unanswered.isEmpty }
}

/// The days' records (`每日记录.json`), the newest 30.
public final class DayLog {
    public static let keep = 30
    public private(set) var days: [DayRecord] = []
    private let file: URL
    private let calendar: Calendar

    public init(folder: URL, calendar: Calendar = .current) {
        file = folder.appendingPathComponent("每日记录.json")
        self.calendar = calendar
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([DayRecord].self, from: data) {
            days = saved
        }
    }

    public func record(for date: Date = Date()) -> DayRecord { record(named: DailySummary.dayName(date, calendar)) }

    public func record(named day: String) -> DayRecord { days.first { $0.day == day } ?? DayRecord(day: day) }

    public func addReply(at date: Date = Date()) { change(date) { $0.replied += 1 } }

    public func addLearned(at date: Date = Date()) { change(date) { $0.learned += 1 } }

    public func addHandOver(who: String, what: String, at date: Date = Date()) {
        change(date) { $0.handedOver.append(.init(who: who, what: what)) }
    }

    /// The same question (ignoring punctuation and spaces) is kept once a day.
    public func addUnanswered(who: String, question: String, at date: Date = Date()) {
        let key = TextMatch.normalize(question)
        guard !key.isEmpty else { return }
        change(date) { r in
            guard !r.unanswered.contains(where: { TextMatch.normalize($0.what) == key }) else { return }
            r.unanswered.append(.init(who: who, what: question))
        }
    }

    /// On how many of the kept days this question had no answer.
    public func daysAsked(_ question: String) -> Int {
        let key = TextMatch.normalize(question)
        return days.filter { d in d.unanswered.contains { TextMatch.similar(TextMatch.normalize($0.what), key) } }.count
    }

    private func change(_ date: Date, _ edit: (inout DayRecord) -> Void) {
        let day = DailySummary.dayName(date, calendar)
        var r = record(named: day)
        edit(&r)
        days = (days.filter { $0.day != day } + [r]).sorted { $0.day < $1.day }.suffix(Self.keep).map { $0 }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(days).write(to: file, options: .atomic)
    }
}

/// 每日小结: one day in a line, the questions that had no answer, and when to show it.
public struct DailySummary: Equatable {
    public var headline: String
    public var unanswered: [String]
    public var facts: String   // the whole day in words, for 小轻舟

    /// From this hour on, today's summary shows; before it, yesterday's.
    public static let eveningHour = 20

    public static func dayName(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `daysAsked` tells on how many days a question came up; from the second day it is said.
    public static func make(_ r: DayRecord, daysAsked: (String) -> Int = { _ in 1 }) -> DailySummary {
        guard !r.isEmpty else { return DailySummary(headline: "没有回复过消息", unanswered: [], facts: "没有回复过消息") }
        var parts = ["回复 \(r.replied) 条"]
        if !r.handedOver.isEmpty { parts.append("交给你 \(r.handedOver.count) 位") }
        if !r.unanswered.isEmpty { parts.append("没答上 \(r.unanswered.count) 个") }
        var facts = ["回复 \(r.replied) 条"]
        if !r.handedOver.isEmpty { facts.append("交给店主：" + r.handedOver.map { "\($0.who)（\($0.what)）" }.joined(separator: "、")) }
        if !r.unanswered.isEmpty { facts.append("知识库没答上的问题：" + r.unanswered.map { "\($0.who)问“\($0.what)”" }.joined(separator: "、")) }
        if r.learned > 0 { facts.append("学到 \(r.learned) 条新问答") }
        let questions = r.unanswered.map(\.what).map { q in daysAsked(q) > 1 ? "\(q)（第 \(daysAsked(q)) 天被问）" : q }
        return DailySummary(headline: parts.joined(separator: " · "), unanswered: questions,
                            facts: facts.joined(separator: "；"))
    }

    /// Which day's summary 动态 shows now: today's in the evening, otherwise yesterday's; nil when
    /// that day had nothing or the owner closed it.
    public static func dayToShow(now: Date, closed: String, hasRecord: (String) -> Bool,
                                 calendar: Calendar = .current) -> String? {
        let evening = calendar.component(.hour, from: now) >= eveningHour
        let date = evening ? now : calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let day = dayName(date, calendar)
        return day != closed && hasRecord(day) ? day : nil
    }
}
