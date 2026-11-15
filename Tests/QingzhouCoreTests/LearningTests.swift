import Foundation
import Testing
@testable import QingzhouCore

private func tempFolder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

@Test("Lessons about the same kind of question come first, even when they are old")
func lessonsPickedByQuestion() {
    let dir = tempFolder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = LessonStore(folder: dir)
    store.add(Lesson(kind: .rewritten, question: "水蜜桃能便宜点吗", draft: "我确认一下", final: "已经是实在价了"))
    for i in 0..<10 { store.add(Lesson(kind: .liked, question: "第\(i)个快递什么时候到", draft: "明天发顺丰")) }
    let text = store.promptText(for: "脐橙可以便宜点吗", limit: 4)
    #expect(text.contains("已经是实在价了"))
    #expect(text.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count == 4)
    // With nothing alike, the newest ones are used.
    #expect(store.promptText(for: "你好", limit: 2).contains("第9个快递"))
    #expect(LessonStore(folder: tempFolder()).promptText(for: "你好").isEmpty)
}

@Test("What the owner said himself is kept as a lesson and reads as his own words")
func lessonOwnerSaid() {
    let dir = tempFolder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = LessonStore(folder: dir)
    store.add(Lesson(kind: .ownerSaid, question: "收到有两个烂的", draft: "", final: "拍个照给我，烂的按个退给你"))
    #expect(LessonStore(folder: dir).promptText(for: "有个烂了").contains("店主自己是这样回的：“拍个照给我，烂的按个退给你”"))
}

@Test("A question that could not be answered on several days is counted across days")
func unansweredAskedAgain() {
    let dir = tempFolder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = DayLog(folder: dir)
    let d = Date(timeIntervalSince1970: 1_800_000_000)
    log.addUnanswered(who: "王女士", question: "门口能停车吗", at: d)
    log.addUnanswered(who: "李先生", question: "门口能停车吗？", at: d + 86_400)
    log.addUnanswered(who: "张小姐", question: "门口能停车吗", at: d + 3 * 86_400)
    log.addUnanswered(who: "张小姐", question: "周日发货吗", at: d + 3 * 86_400)
    #expect(log.daysAsked("门口能停车吗") == 3 && log.daysAsked("周日发货吗") == 1)
    let s = DailySummary.make(log.record(for: d + 3 * 86_400), daysAsked: log.daysAsked)
    #expect(s.unanswered == ["门口能停车吗（第 3 天被问）", "周日发货吗"])
}

@Test("Plain wording is learned by itself; numbers and promises wait for the owner's click")
func ownerAnswerNeedsApproval() {
    #expect(!OwnerAnswer.needsApproval("不好意思，已经是实在价了"))
    #expect(!OwnerAnswer.needsApproval("拍个照给我看看，我马上帮你处理"))
    #expect(OwnerAnswer.needsApproval("给你算 85 一斤"))
    #expect(OwnerAnswer.needsApproval("这次给你抹个零"))
    #expect(OwnerAnswer.needsApproval("烂的按个退给你"))
    #expect(OwnerAnswer.needsApproval("下次送你两只"))
    #expect(OwnerAnswer.needsApproval("可以，包邮"))
}

@Test("A chat handed to the owner waits for his wording, kept apart from knowledge questions")
func mannerSuggestionKept() {
    let dir = tempFolder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = AnswerSuggestionStore(folder: dir)
    store.watch(chat: "c1", who: "张小姐", question: "能便宜点吗", manner: true)
    store.watch(chat: "c2", who: "王女士", question: "门口能停车吗")
    let again = AnswerSuggestionStore(folder: dir)
    #expect(again.open(in: "c1").first?.isManner == true && again.open(in: "c2").first?.isManner == false)
}

@Test("A reply is recognised on screen by its first or last line, also when those lines are short")
func replyRecognisedByLines() {
    let reply = "这些都有货：\n\n· 特级红富士　10斤装一箱　560元/斤\n· 当季脐橙　中果　60元/斤\n\n你想要哪种？"
    #expect(TextMatch.shows("你想要哪种", reply))                           // only the last line is in view
    #expect(TextMatch.shows("这些都有货特级红富士10斤装", reply))            // only the start is in view
    #expect(TextMatch.shows("当季脐橙中果60元斤你想要哪种", reply))
    #expect(!TextMatch.shows("在的请问有什么可以帮您", reply))
    #expect(!TextMatch.shows("", reply) && !TextMatch.shows("好", "好的"))
    #expect(TextMatch.shows("不讲价都是实在价", "不讲价，都是实在价。"))
    // One-word lines are too little to go by.
    #expect(!TextMatch.shows("好", "好\n我看一下发货时间再告诉你"))
}
