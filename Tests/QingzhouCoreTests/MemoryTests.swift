import Foundation
import Testing
@testable import QingzhouCore

private func m(_ fromMe: Bool, _ t: String) -> StoredMessage { StoredMessage(fromMe: fromMe, text: t) }
private func b(_ fromMe: Bool, _ t: String) -> ChatBubble { ChatBubble(fromMe: fromMe, text: t, top: 0) }

@Test("Reading the same screen again adds nothing")
func mergeSameScreen() {
    let screen = [m(false, "在吗"), m(true, "在的"), m(false, "满多少包邮")]
    let (once, added1) = MemoryMerge.merge([], visible: screen)
    let (twice, added2) = MemoryMerge.merge(once, visible: screen)
    #expect(added1 == 3)
    #expect(added2 == 0)
    #expect(twice.count == 3)
}

@Test("New messages are appended after the overlap, even if the top bubble is cut off")
func mergeNewMessages() {
    let stored = [m(false, "在吗"), m(true, "在的"), m(false, "满多少包邮")]
    let screen = [m(true, "在"), m(false, "满多少包邮"), m(true, "满99包邮"), m(false, "谢谢")]   // "在的" cut to "在"
    let (merged, added) = MemoryMerge.merge(stored, visible: screen)
    #expect(added == 2)
    #expect(merged.map(\.text) == ["在吗", "在的", "满多少包邮", "满99包邮", "谢谢"])
}

@Test("OCR differences and a voice message gaining its words are the same message")
func mergeTolerant() {
    let stored = [m(false, "你好，请问订单什么时候发货？"), m(false, "[语音3秒]")]
    let screen = [m(false, "你好,请问订单什么时候发货"), m(false, "[语音3秒]帮我查一下快递")]
    let (merged, added) = MemoryMerge.merge(stored, visible: screen)
    #expect(added == 0)
    #expect(merged.last?.text == "[语音3秒]帮我查一下快递")
}

@Test("Records are saved to disk, found again with OCR-varied names, and kept apart from groups")
func storePersists() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mem-\(UUID().uuidString)")
    let store = CustomerMemoryStore(folder: dir)
    store.remember(chatID: ChatID.make(title: "店小二2新鲜水果"), name: "店小二2新鲜水果",
                   visible: [b(false, "订单 QZ-1234 什么时候发货"), b(true, "48小时内")])
    let reopened = CustomerMemoryStore(folder: dir)
    #expect(reopened.count == 1)
    #expect(reopened.record(for: ChatID.make(title: "店小二＜新鲜水果"))?.messages.count == 2)
    #expect(reopened.record(for: ChatID.make(title: "店小二新鲜水果 (5)")) == nil)
}

@Test("Earlier history is what came before the screen")
func earlierHistory() {
    var r = CustomerRecord(chatID: "人|王女士", name: "王女士")
    r.messages = [m(false, "上次订单QZ-1234"), m(true, "好的"), m(false, "在吗"), m(true, "在的"), m(false, "能开发票吗")]
    let earlier = CustomerMemoryStore.earlier(in: r, visible: [b(false, "在吗"), b(true, "在的"), b(false, "能开发票吗")])
    #expect(earlier.map(\.text) == ["上次订单QZ-1234", "好的"])
}

@Test("Prompt carries the remembered history and key points")
func promptHasMemory() {
    var r = CustomerRecord(chatID: "人|王女士", name: "王女士")
    r.summary = "上次问过订单 QZ-1234 的发货时间"
    let p = PromptBuilder.build(conversation: Conversation(bubbles: [b(false, "我那个订单呢")]), knowledge: [],
                                memory: r, earlier: [m(false, "订单 QZ-1234 什么时候发货")])
    #expect(p.contains("要点：上次问过订单 QZ-1234 的发货时间"))
    #expect(p.contains("对方：订单 QZ-1234 什么时候发货"))
}

@Test("“记忆” counts as a source only when the customer's history was given")
func memoryAsSource() {
    let raw = "类型：问题\n引用：记忆\n回复：您上次问的是订单 QZ-1608。"
    #expect(ReplyParser.parse(raw, allowed: [], memoryGiven: true)?.isConfident == true)
    #expect(ReplyParser.parse(raw, allowed: [], memoryGiven: false)?.isConfident == false)
}

@Test("Customer files from before reservations/consent existed still load")
func oldRecordLoads() throws {
    let old = """
    {"chatID":"人|王女士","name":"王女士","firstSeen":"2026-11-04T10:00:00Z","lastSeen":"2026-11-04T10:00:00Z",
     "messages":[{"fromMe":false,"text":"在吗","seenAt":"2026-11-04T10:00:00Z"}],"summary":"","sinceSummary":1}
    """
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    let r = try dec.decode(CustomerRecord.self, from: Data(old.utf8))
    #expect(r.messages.count == 1)
    #expect(r.reservations.isEmpty)
    #expect(r.consent == nil)
}

@Test("News goes only to customers who agreed, about what they like; never after an opt-out")
func newsRecipients() {
    var apple = CustomerRecord(chatID: "人|甲", name: "甲")
    apple.consent = Consent(interests: "红富士、脐橙", quote: "有红富士告诉我")
    var any = CustomerRecord(chatID: "人|乙", name: "乙")
    any.consent = Consent(interests: "都可以", quote: "有好东西联系我")
    var stopped = any
    stopped.optedOutAt = Date()
    let none = CustomerRecord(chatID: "人|丙", name: "丙")
    #expect(apple.wantsNews(about: "今天到了一批特级红富士"))
    var peach = CustomerRecord(chatID: "人|丁", name: "丁")
    peach.consent = Consent(interests: "新到的水蜜桃", quote: "以后有新到的水蜜桃记得告诉我")
    #expect(peach.wantsNews(about: "今天到了一批当季水蜜桃，个大汁多"))
    #expect(!peach.wantsNews(about: "今天到了一批特级红富士"))
    #expect(!apple.wantsNews(about: "水蜜桃到货了"))
    #expect(any.wantsNews(about: "水蜜桃到货了"))
    #expect(!stopped.wantsNews(about: "水蜜桃到货了"))
    #expect(!none.wantsNews(about: "水蜜桃到货了"))
}
