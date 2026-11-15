import Foundation
import QingzhouCore

/// 每日小结: the day's numbers are kept on disk (DayLog); 动态 shows today's in the evening and
/// yesterday's the next morning, until the owner closes it.
extension AutoReplyController {
    /// The day whose summary 动态 shows now, if any.
    var summaryToShow: (title: String, summary: DailySummary, day: String)? {
        let today = DailySummary.dayName(Date())
        let forced = CommandLine.arguments.contains("--show-summary")   // screenshots
        guard let day = forced ? today : DailySummary.dayToShow(now: Date(), closed: summaryClosed, hasRecord: {
            !self.dayLog.record(named: $0).isEmpty
        }) else { return nil }
        return (day == today ? "今天小结" : "昨天小结", DailySummary.make(dayLog.record(named: day), daysAsked: dayLog.daysAsked), day)
    }

    func closeSummary(_ day: String) { summaryClosed = day }

    /// Today and yesterday in words, for 小轻舟.
    func summaryFacts() -> String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return "今天小结：\(DailySummary.make(dayLog.record()).facts)；昨天小结：\(DailySummary.make(dayLog.record(for: yesterday)).facts)"
    }
}
