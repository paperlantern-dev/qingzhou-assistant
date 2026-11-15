import Foundation
import Testing
@testable import QingzhouCore

private let day1 = Date(timeIntervalSince1970: 1_800_000_000)

@Test("Each day's numbers are kept on disk; the same unanswered question is counted once")
func dayLogKept() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = DayLog(folder: dir)
    log.addReply(at: day1); log.addReply(at: day1)
    log.addHandOver(who: "张小姐", what: "讲价", at: day1)
    log.addUnanswered(who: "王女士", question: "门口能停车吗", at: day1)
    log.addUnanswered(who: "李先生", question: "门口能停车吗？", at: day1)
    log.addLearned(at: day1)
    log.addReply(at: day1 + 86_400)

    let again = DayLog(folder: dir)
    let r = again.record(for: day1)
    #expect(r.replied == 2 && r.learned == 1)
    #expect(r.handedOver == [DayRecord.Item(who: "张小姐", what: "讲价")])
    #expect(r.unanswered.map(\.what) == ["门口能停车吗"])
    #expect(again.record(for: day1 + 86_400).replied == 1)
    #expect(again.record(for: day1 + 5 * 86_400).isEmpty)
}

@Test("Only the newest 30 days are kept")
func dayLogKeepsAMonth() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = DayLog(folder: dir)
    for i in 0..<35 { log.addReply(at: day1 + Double(i) * 86_400) }
    #expect(log.days.count == 30 && log.record(for: day1).isEmpty)
}

@Test("The summary says how many were answered, who was handed over, and what could not be answered")
func dailySummaryLines() {
    var r = DayRecord(day: "2027-01-15")
    r.replied = 12
    r.learned = 2
    r.handedOver = [.init(who: "张小姐", what: "讲价"), .init(who: "李先生", what: "售后")]
    r.unanswered = [.init(who: "王女士", what: "门口能停车吗")]
    let s = DailySummary.make(r)
    #expect(s.headline == "回复 12 条 · 交给你 2 位 · 没答上 1 个")
    #expect(s.unanswered == ["门口能停车吗"])
    #expect(s.facts.contains("张小姐（讲价）") && s.facts.contains("学到 2 条"))
    #expect(DailySummary.make(DayRecord(day: "2027-01-16")).headline == "没有回复过消息")
}

@Test("In the evening today's summary shows; next morning yesterday's, until it is closed")
func dailySummaryWhen() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let morning = cal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 9))!
    let evening = cal.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 21))!
    let busy: (String) -> Bool = { _ in true }
    #expect(DailySummary.dayToShow(now: evening, closed: "", hasRecord: busy, calendar: cal) == "2027-01-15")
    #expect(DailySummary.dayToShow(now: morning, closed: "", hasRecord: busy, calendar: cal) == "2027-01-14")
    #expect(DailySummary.dayToShow(now: morning, closed: "2027-01-14", hasRecord: busy, calendar: cal) == nil)
    #expect(DailySummary.dayToShow(now: evening, closed: "2027-01-14", hasRecord: busy, calendar: cal) == "2027-01-15")
    #expect(DailySummary.dayToShow(now: evening, closed: "", hasRecord: { _ in false }, calendar: cal) == nil)
}
