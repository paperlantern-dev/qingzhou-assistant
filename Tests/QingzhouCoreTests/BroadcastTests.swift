import Foundation
import Testing
@testable import QingzhouCore

// MARK: 定时群发

/// A fixed calendar, so the tests don't depend on this Mac's time zone.
private let bcCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}()

/// A time in November 2026 (the 5th is a Thursday).
private func bcAt(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    bcCal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
}

private func bcPerson(_ name: String, optedOut: Bool = false) -> CustomerRecord {
    var r = CustomerRecord(chatID: ChatID.make(title: name), name: name)
    if optedOut { r.optedOutAt = Date() }
    return r
}

@Test("A daily broadcast goes out once its time has passed today, at most once a day")
func broadcastDailyIsDue() {
    var b = Broadcast(text: "今天到了新鲜脐橙", schedule: .daily(hour: 10, minute: 0))
    #expect(!b.isDue(at: bcAt(5, 9, 59), calendar: bcCal))
    #expect(b.isDue(at: bcAt(5, 10), calendar: bcCal))
    #expect(b.isDue(at: bcAt(5, 15), calendar: bcCal))          // started late today: still today's
    b.lastRun = bcAt(5, 10, 1)
    #expect(!b.isDue(at: bcAt(5, 15), calendar: bcCal))         // already went out today
    #expect(!b.isDue(at: bcAt(6, 9, 59), calendar: bcCal))
    #expect(b.isDue(at: bcAt(6, 10), calendar: bcCal))          // the next day
    b.schedule = .daily(hour: 14, minute: 0)                    // time changed after today's went out
    #expect(!b.isDue(at: bcAt(5, 14, 5), calendar: bcCal))
}

@Test("A weekly broadcast goes out on its weekday only; missed days are not made up")
func broadcastWeeklyIsDue() {
    var b = Broadcast(text: "周四上新", schedule: .weekly(weekday: 5, hour: 10, minute: 30))
    #expect(!b.isDue(at: bcAt(5, 10, 29), calendar: bcCal))
    #expect(b.isDue(at: bcAt(5, 10, 30), calendar: bcCal))      // Thursday
    #expect(!b.isDue(at: bcAt(6, 11), calendar: bcCal))         // Friday: Thursday's is not sent late
    b.lastRun = bcAt(5, 10, 30)
    #expect(!b.isDue(at: bcAt(5, 18), calendar: bcCal))
    #expect(b.isDue(at: bcAt(12, 10, 30), calendar: bcCal))     // next Thursday
}

@Test("A one-time broadcast goes out once, and only on its day")
func broadcastOnceIsDue() {
    var b = Broadcast(text: "周六闭店一天", schedule: .once(at: bcAt(5, 14, 30)))
    #expect(!b.isDue(at: bcAt(5, 14, 29), calendar: bcCal))
    #expect(b.isDue(at: bcAt(5, 14, 30), calendar: bcCal))
    #expect(b.isDue(at: bcAt(5, 20), calendar: bcCal))
    #expect(!b.isDue(at: bcAt(6, 10), calendar: bcCal))         // missed on its day: never sent late
    b.lastRun = bcAt(5, 14, 30)
    #expect(!b.isDue(at: bcAt(5, 20), calendar: bcCal))
}

@Test("Switched off, empty or with an impossible time, it never goes out")
func broadcastNotDue() {
    var off = Broadcast(text: "今天到了脐橙", schedule: .daily(hour: 10, minute: 0))
    off.enabled = false
    #expect(!off.isDue(at: bcAt(5, 11), calendar: bcCal))
    #expect(!Broadcast(text: "  \n ", schedule: .daily(hour: 10, minute: 0)).isDue(at: bcAt(5, 11), calendar: bcCal))
    #expect(!Broadcast(text: "x", schedule: .daily(hour: 25, minute: 0)).isDue(at: bcAt(5, 23), calendar: bcCal))
    #expect(!Broadcast(text: "x", schedule: .daily(hour: 10, minute: 75)).isDue(at: bcAt(5, 23), calendar: bcCal))
    #expect(!Broadcast(text: "x", schedule: .weekly(weekday: 9, hour: 10, minute: 0)).isDue(at: bcAt(5, 23), calendar: bcCal))
}

@Test("Saved or switched on after today's time, it starts with the next one")
func broadcastActivatedLate() {
    let late = Broadcast(text: "今天到了脐橙", schedule: .daily(hour: 10, minute: 0), enabled: false)
        .activated(at: bcAt(5, 15), calendar: bcCal)
    #expect(late.enabled)
    #expect(!late.isDue(at: bcAt(5, 15, 1), calendar: bcCal))   // no blast right after saving
    #expect(late.isDue(at: bcAt(6, 10), calendar: bcCal))
    let sameMinute = Broadcast(text: "x", schedule: .daily(hour: 15, minute: 0))
        .activated(at: bcAt(5, 15, 0, 40), calendar: bcCal)
    #expect(sameMinute.isDue(at: bcAt(5, 15, 0, 41), calendar: bcCal))   // saved within that minute: still today
    let early = Broadcast(text: "x", schedule: .daily(hour: 15, minute: 0)).activated(at: bcAt(5, 9), calendar: bcCal)
    #expect(early.isDue(at: bcAt(5, 15), calendar: bcCal))
}

@Test("Everyone remembered gets it, except who said 别发了 and who the app leaves out")
func broadcastRecipientsEveryone() {
    let records = [bcPerson("王女士"), bcPerson("李先生", optedOut: true), bcPerson("妈妈"), bcPerson("张三")]
    let b = Broadcast(text: "今天到了脐橙")
    #expect(b.recipients(from: records).map(\.name) == ["王女士", "妈妈", "张三"])
    #expect(b.recipients(from: records) { $0.name == "妈妈" }.map(\.name) == ["王女士", "张三"])
}

@Test("Chosen customers are matched by name loosely; nobody else gets it")
func broadcastRecipientsChosen() {
    let records = [bcPerson("客户·王女士🍎"), bcPerson("王女士2"), bcPerson("李先生"), bcPerson("赵六", optedOut: true)]
    let b = Broadcast(text: "x", recipients: ["客户·王女士", "赵六"])
    #expect(b.recipients(from: records).map(\.name) == ["客户·王女士🍎"])   // 赵六 said 别发了
    #expect(Broadcast(text: "x", recipients: ["不在了"]).recipients(from: records).isEmpty)
}

@Test("A chat listed twice gets one message")
func broadcastRecipientsOncePerChat() {
    let twice = [bcPerson("店小二新鲜水果"), bcPerson("王女士"), bcPerson("店小二新鲜水果")]
    #expect(Broadcast(text: "x").recipients(from: twice).map(\.name) == ["店小二新鲜水果", "王女士"])
}

@Test("The schedule reads in plain words")
func broadcastScheduleLabels() {
    #expect(Broadcast.Schedule.daily(hour: 9, minute: 5).label(calendar: bcCal) == "每天 09:05")
    #expect(Broadcast.Schedule.weekly(weekday: 4, hour: 18, minute: 30).label(calendar: bcCal) == "每周三 18:30")
    #expect(Broadcast.Schedule.weekly(weekday: 1, hour: 10, minute: 0).label(calendar: bcCal) == "每周日 10:00")
    #expect(Broadcast.Schedule.once(at: bcAt(6, 10)).label(calendar: bcCal) == "11月6日 10:00 发一次")
}

@Test("The owner's words go out as one message")
func broadcastOneLine() {
    #expect(Broadcast.oneLine("  早上好！\n\n今天到了脐橙 \r\n要的私聊  ") == "早上好！ 今天到了脐橙 要的私聊")
    #expect(Broadcast.oneLine(" \n ") == "")
}

@Test("Broadcasts round-trip, and ones saved by an older version still load, switched off")
func broadcastDecoding() throws {
    var b = Broadcast(text: "今天到了脐橙", picture: "/tmp/a.jpg", recipients: ["王女士"],
                      schedule: .weekly(weekday: 2, hour: 10, minute: 30))
    b.lastRun = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(try JSONDecoder().decode(Broadcast.self, from: JSONEncoder().encode(b)) == b)

    let old = try JSONDecoder().decode(Broadcast.self, from: Data(#"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","text":"你好"}"#.utf8))
    #expect(old.id.uuidString == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
    #expect(old.text == "你好" && old.recipients.isEmpty && old.picture == nil && old.lastRun == nil)
    #expect(!old.enabled)
    // A schedule this version can't read loads switched off instead of losing all settings.
    let odd = try JSONDecoder().decode(Broadcast.self,
                                       from: Data(#"{"text":"你好","schedule":{"monthly":{"day":1}},"enabled":true}"#.utf8))
    #expect(!odd.enabled)
}
