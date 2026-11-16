import Foundation
import Testing
@testable import QingzhouCore

// MARK: 不回名单

@Test("The never-reply list matches a chat's name, also with small OCR differences")
func neverReplyMatchesNames() {
    let list = NeverReplyList(["妈妈", "张三丰", "家人群", "客户·王女士"])
    #expect(list.contains("妈妈"))
    #expect(list.contains("张三丰🍎"))
    #expect(list.contains("家人群(5)"))        // a group title carries its member count
    #expect(!list.contains("王女士"))          // only part of a listed name
    #expect(!list.contains("客户·李先生"))
    #expect(list.contains("客户·王…"))         // cut off in the contact list
    #expect(!list.contains("客户·李…"))
}

@Test("Very short names never block anyone")
func neverReplyIgnoresShortNames() {
    #expect(!NeverReplyList(["王", " "]).contains("王女士"))
    #expect(!NeverReplyList(["王"]).contains("王"))
    #expect(!NeverReplyList(["客户·王女士"]).contains("客户…"))   // a cut name needs three characters
}

// MARK: 手机提醒

@Test("Only WeCom and Feishu robot webhooks over https are accepted")
func alertWebhookKinds() {
    #expect(AlertWebhook.kind(of: "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=abc") == .weCom)
    #expect(AlertWebhook.kind(of: " https://open.feishu.cn/open-apis/bot/v2/hook/123 ") == .feishu)
    #expect(AlertWebhook.kind(of: "https://open.larksuite.com/open-apis/bot/v2/hook/123") == .feishu)
    #expect(AlertWebhook.kind(of: "http://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=abc") == nil)
    #expect(AlertWebhook.kind(of: "https://qyapi.weixin.qq.com.evil.com/cgi-bin/webhook/send?key=abc") == nil)
    #expect(AlertWebhook.kind(of: "https://example.com/open-apis/bot/v2/hook/123") == nil)
    #expect(AlertWebhook.kind(of: "https://qyapi.weixin.qq.com/other") == nil)
    #expect(AlertWebhook.kind(of: "") == nil)
}

@Test("The alert request carries the text in each robot's own format")
func alertWebhookRequests() throws {
    let we = try #require(AlertWebhook.request(to: "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=abc", text: "你好"))
    #expect(we.httpMethod == "POST")
    let weBody = try #require(we.httpBody)
    let weJSON = try #require(try JSONSerialization.jsonObject(with: weBody) as? [String: Any])
    #expect(weJSON["msgtype"] as? String == "text")
    #expect((weJSON["text"] as? [String: Any])?["content"] as? String == "你好")
    let fs = try #require(AlertWebhook.request(to: "https://open.feishu.cn/open-apis/bot/v2/hook/123", text: "你好"))
    let fsBody = try #require(fs.httpBody)
    let fsJSON = try #require(try JSONSerialization.jsonObject(with: fsBody) as? [String: Any])
    #expect(fsJSON["msg_type"] as? String == "text")
    #expect((fsJSON["content"] as? [String: Any])?["text"] as? String == "你好")
    #expect(AlertWebhook.request(to: "https://example.com/x", text: "你好") == nil)
}

@Test("The robot's answer tells whether the alert arrived")
func alertWebhookAnswers() {
    #expect(AlertWebhook.problem(in: Data(#"{"errcode":0,"errmsg":"ok"}"#.utf8)) == nil)
    #expect(AlertWebhook.problem(in: Data(#"{"code":0,"msg":"success","data":{}}"#.utf8)) == nil)
    #expect(AlertWebhook.problem(in: Data(#"{"StatusCode":0,"StatusMessage":"success"}"#.utf8)) == nil)
    #expect(AlertWebhook.problem(in: Data(#"{"errcode":93000,"errmsg":"invalid webhook url"}"#.utf8)) == "invalid webhook url")
    #expect(AlertWebhook.problem(in: Data(#"{"code":19024,"msg":"Key Words Not Found"}"#.utf8)) == "Key Words Not Found")
    #expect(AlertWebhook.problem(in: Data("oops".utf8)) != nil)
}

@Test("An alert says who wrote, what, and why it was left to you")
func alertMessageText() {
    let text = AlertWebhook.message(who: "客户·王女士", text: "周日有门店吗？", reason: "知识库里没有答案")
    #expect(text.hasPrefix("【轻舟助手】"))
    #expect(text.contains("客户·王女士") && text.contains("周日有门店吗？") && text.contains("知识库里没有答案"))
    #expect(AlertWebhook.message(who: "a", text: String(repeating: "长", count: 500), reason: "r").count < 300)
}

// MARK: 辅助模式：店主教过的说法

@Test("Lessons from drafts are saved, newest first in the prompt, and capped")
func lessonsAreKeptAndCapped() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = LessonStore(folder: dir)
    store.add(Lesson(kind: .rewritten, question: "多少钱一斤", draft: "280元", final: "280一斤，今天刚到的"))
    store.add(Lesson(kind: .rejected, question: "在吗", draft: "您好，请问有什么可以帮您的吗？", reason: "太客气了"))
    store.add(Lesson(kind: .liked, question: "怎么保存", draft: "放冰箱冷藏"))
    let text = store.promptText(limit: 2)
    #expect(text.contains("放冰箱冷藏") && text.contains("太客气了"))
    #expect(!text.contains("280一斤"))                   // only the newest two
    #expect(text.contains("知识库"))                     // style only; facts still come from the knowledge base
    #expect(LessonStore(folder: dir).lessons.count == 3)
    for i in 0..<LessonStore.keep { store.add(Lesson(kind: .liked, question: "q\(i)", draft: "d\(i)")) }
    #expect(store.lessons.count == LessonStore.keep)
    #expect(LessonStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        .promptText() == "")
}

@Test("The reply prompt carries what the owner taught")
func promptIncludesLessons() {
    let conv = Conversation(bubbles: [ChatBubble(fromMe: false, text: "多少钱", top: 0)])
    #expect(PromptBuilder.build(conversation: conv, knowledge: [], lessons: "【店主教过的说法】示例").contains("【店主教过的说法】"))
    #expect(!PromptBuilder.build(conversation: conv, knowledge: []).contains("店主教过"))
}

// MARK: 主动智能

private func customer(_ name: String, theirsDaysAgo: Double?, lastDaysAgo: Double, now: Date) -> CustomerRecord {
    var r = CustomerRecord(chatID: "人|\(name)", name: name, now: now.addingTimeInterval(-120 * 86400))
    if let t = theirsDaysAgo {
        r.messages.append(StoredMessage(fromMe: false, text: "你好", seenAt: now.addingTimeInterval(-t * 86400)))
    }
    r.messages.append(StoredMessage(fromMe: true, text: "好的", seenAt: now.addingTimeInterval(-lastDaysAgo * 86400)))
    return r
}

@Test("主动智能 picks customers who went quiet for a while, once per quiet spell")
func revisitPicksQuietCustomers() {
    let now = Date()
    var greeted = customer("已问候", theirsDaysAgo: 12, lastDaysAgo: 10, now: now)
    greeted.lastRevisitAt = now.addingTimeInterval(-2 * 86400)
    var optedOut = customer("别发了", theirsDaysAgo: 12, lastDaysAgo: 10, now: now)
    optedOut.optedOutAt = now.addingTimeInterval(-20 * 86400)
    var waiting = customer("等到货", theirsDaysAgo: 12, lastDaysAgo: 10, now: now)
    waiting.reservations = [Reservation(item: "红富士", quote: "帮我留", createdAt: now)]
    let records = [
        customer("十天", theirsDaysAgo: 11, lastDaysAgo: 10, now: now),
        customer("八天", theirsDaysAgo: 9, lastDaysAgo: 8, now: now),
        customer("昨天", theirsDaysAgo: 1, lastDaysAgo: 1, now: now),
        customer("太久", theirsDaysAgo: 90, lastDaysAgo: 80, now: now),
        customer("没说过话", theirsDaysAgo: nil, lastDaysAgo: 10, now: now),
        greeted, optedOut, waiting,
    ]
    #expect(Revisit.candidates(in: records, now: now, minDays: 7, maxDays: 30, limit: 5).map(\.name) == ["八天", "十天"])
    #expect(Revisit.candidates(in: records, now: now, minDays: 7, maxDays: 30, limit: 1).map(\.name) == ["八天"])
    #expect(Revisit.candidates(in: records, now: now, minDays: 7, maxDays: 30, limit: 5) { $0.name == "八天" }
        .map(\.name) == ["十天"])
}

@Test("Someone greeted before, who wrote again since, can be greeted after the next quiet spell")
func revisitAgainAfterTheyWrote() {
    let now = Date()
    var r = customer("老客户", theirsDaysAgo: 9, lastDaysAgo: 8, now: now)
    r.lastRevisitAt = now.addingTimeInterval(-40 * 86400)
    #expect(Revisit.candidates(in: [r], now: now, minDays: 7, maxDays: 30, limit: 5).count == 1)
}

@Test("Old customer files without a greeting date still load")
func recordLoadsWithoutRevisitDate() throws {
    let json = #"{"chatID":"人|王","name":"王","firstSeen":"2026-11-01T00:00:00Z","lastSeen":"2026-11-01T00:00:00Z","messages":[]}"#
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    #expect(try dec.decode(CustomerRecord.self, from: Data(json.utf8)).lastRevisitAt == nil)
}

@Test("The greeting prompt asks for one gentle line, or 跳过, and no selling")
func revisitPrompt() {
    var r = CustomerRecord(chatID: "人|王", name: "王")
    r.summary = "买过脐橙"
    r.messages = [StoredMessage(fromMe: false, text: "脐橙收到了"), StoredMessage(fromMe: true, text: "好的")]
    let p = PromptBuilder.outreach(.revisit(days: 10), record: r)
    #expect(p.contains("10 天") && p.contains("跳过") && p.contains("买过脐橙") && p.contains("脐橙收到了"))
    #expect(p.contains("不要催单"))
}

// MARK: 草稿里的多条消息

@Test("A draft keeps the line breaks inside one message; an empty line separates two messages")
func draftKeepsLineBreaks() {
    let table = "红富士 5斤 39元\n脐橙 5斤 29元\n水蜜桃 3斤 45元"
    #expect(DraftText.messages(table) == [table])                       // one message, nothing dropped
    #expect(DraftText.messages(DraftText.join([table, "要哪种？"])) == [table, "要哪种？"])
    #expect(DraftText.messages("  好的 \n\n\n 明天发  ") == ["好的", "明天发"])
    #expect(DraftText.messages(" \n ").isEmpty)
}

@Test("More than two messages in a draft: the rest goes out with the second, never dropped")
func draftNeverDropsText() {
    #expect(DraftText.messages("一\n\n二\n\n三\n四") == ["一", "二\n三\n四"])
}

// MARK: 前台发送前再看一眼

@Test("A foreground send is called off when the chat, the newest message or the input box changed")
func sendCheckCatchesChanges() {
    let chat = ChatID.make(title: "客户·王女士"), other = ChatID.make(title: "客户·李先生")
    #expect(SendCheck.problem(chat: chat, pendingKey: "红富士多少钱", nowChat: chat, nowPendingKey: "红富士多少钱", nowInput: "") == nil)
    #expect(SendCheck.problem(chat: chat, pendingKey: "", nowChat: chat, nowPendingKey: "", nowInput: "") == nil)
    #expect(SendCheck.problem(chat: chat, pendingKey: "红富士多少钱", nowChat: other, nowPendingKey: "红富士多少钱", nowInput: "") != nil)
    #expect(SendCheck.problem(chat: chat, pendingKey: "红富士多少钱", nowChat: chat, nowPendingKey: "红富士多少钱 再加一箱脐橙", nowInput: "") != nil)
    #expect(SendCheck.problem(chat: chat, pendingKey: "红富士多少钱", nowChat: chat, nowPendingKey: "", nowInput: "") != nil)
    #expect(SendCheck.problem(chat: chat, pendingKey: "红富士多少钱", nowChat: chat, nowPendingKey: "红富士多少钱", nowInput: "我自己打到一半的话") != nil)
}

@Test("Only the assistant's own text is ever taken back out of the input box")
func cleanupOnlyTouchesAssistantText() {
    let reply = "红富士5斤装39元，今天下单明天发"
    #expect(SendCheck.isAssistantText(input: reply, reply: reply))
    #expect(SendCheck.isAssistantText(input: "红富士5斤装39", reply: reply))          // typed half-way
    #expect(!SendCheck.isAssistantText(input: "我自己打到一半的话", reply: reply))   // the owner's own draft
    #expect(!SendCheck.isAssistantText(input: "", reply: reply))
    #expect(!SendCheck.isAssistantText(input: "好", reply: reply))                    // too little to tell
}

@Test("Test runs keep their data in a folder of their own, never the owner's records")
func testRunsUseTheirOwnData() {
    let support = URL(fileURLWithPath: "/data/Application Support"), temp = URL(fileURLWithPath: "/tmp/x")
    #expect(AppData.root(arguments: ["app"], support: support, temp: temp).path == "/data/Application Support/轻舟助手")
    #expect(AppData.root(arguments: ["app", "--autotest", "r.json"], support: support, temp: temp).path.hasPrefix("/tmp/x/"))
    #expect(AppData.root(arguments: ["app", "--autotest", "r.json", "--data-dir", "/d/run1"], support: support, temp: temp).path == "/d/run1")
}
