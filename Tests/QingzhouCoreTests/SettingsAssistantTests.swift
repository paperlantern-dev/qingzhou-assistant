import Foundation
import Testing
@testable import QingzhouCore

private func snapshot(neverReply: [String] = [], alerts: Bool = false) -> SettingsSnapshot {
    SettingsSnapshot(rules: TriggerRule.presets, persona: "称呼客户用“你”。",
                     priceItems: [Catalog.Item(name: "水蜜桃", spec: "3两左右一个", price: "78元/斤"),
                                  Catalog.Item(name: "特级红富士", spec: "5斤装一箱", price: "280元/斤"),
                                  Catalog.Item(name: "特级红富士", spec: "10斤装一箱", price: "560元/斤")],
                     neverReply: neverReply, replyAll: false, confirmFirst: false, replyToGroups: false,
                     maxPerHour: 20, maxPerChatPerHour: 5, alertsAvailable: alerts)
}

@Test("Rules have short names: 售后, 找真人, 讲价, 付款或下单, 价格表")
func ruleDisplayNames() {
    #expect(TriggerRule.presets.map(\.displayName) == ["售后", "找真人", "讲价", "付款或下单", "价格表"])
}

@Test("The model's answer becomes a checked list of changes, wrapped in a code fence or not")
func settingsPlanParsed() {
    let raw = """
    ```json
    {"reply":"好的，售后加两个词","actions":[
      {"type":"add_words","rule":"售后","words":["发霉","有异味","坏了"]},
      {"type":"set","key":"replyAll","value":true},
      {"type":"set","key":"maxPerHour","value":500}
    ]}
    ```
    """
    let plan = SettingsAssistant.plan(from: raw, snapshot: snapshot())
    #expect(plan.reply == "好的，售后加两个词")
    // “坏了” is already there, so only the new words stay; the hourly limit is kept within 5–60.
    #expect(plan.changes == [.addWords(rule: "售后", words: ["发霉", "有异味"]), .replyAll(true), .maxPerHour(60)])
    #expect(plan.problems.isEmpty)
}

@Test("Changes that cannot be done are left out and said why")
func settingsPlanProblems() {
    let raw = """
    {"reply":"","actions":[
      {"type":"add_words","rule":"不存在的规则","words":["x"]},
      {"type":"set_price","item":"特级红富士","spec":"","price":"300元/斤"},
      {"type":"set","key":"alerts","value":true},
      {"type":"set","key":"apiKey","value":true}
    ]}
    """
    let plan = SettingsAssistant.plan(from: raw, snapshot: snapshot())
    #expect(plan.changes.isEmpty)
    #expect(plan.problems.count == 4)
    #expect(plan.problems[1].contains("2 种规格"))
    #expect(SettingsAssistant.plan(from: "不是 JSON", snapshot: snapshot()).problems.count == 1)
}

@Test("A price with its spec, new rules, answers and the never-reply list pass the checks")
func settingsPlanMore() {
    let raw = """
    {"reply":"ok","actions":[
      {"type":"set_price","item":"红富士","spec":"10斤装","price":"600元/斤"},
      {"type":"new_rule","name":"自提","words":["自提","到店拿"],"text":null},
      {"type":"add_answer","question":"周日发货吗","answer":"周日不发，周一发"},
      {"type":"never_reply_add","names":["老妈"]},
      {"type":"toggle_rule","rule":"讲价","on":false}
    ]}
    """
    let plan = SettingsAssistant.plan(from: raw, snapshot: snapshot())
    #expect(plan.changes == [.setPrice(item: "特级红富士", spec: "10斤装一箱", price: "600元/斤"),
                             .newRule(name: "自提", words: ["自提", "到店拿"], text: nil),
                             .addAnswer(question: "周日发货吗", answer: "周日不发，周一发"),
                             .neverReplyAdd(["老妈"]),
                             .toggleRule(rule: "讲价", on: false)])
}

@Test("Rule changes apply by name; a new hand-over rule goes first")
func settingsApplyRules() {
    let before = TriggerRule.presets
    let after = SettingsAssistant.apply([.addWords(rule: "售后", words: ["发霉"]),
                                         .removeWords(rule: "讲价", words: ["抹零"]),
                                         .toggleRule(rule: "找真人", on: false),
                                         .newRule(name: "自提", words: ["自提"], text: nil),
                                         .newRule(name: "地址", words: ["地址"], text: "店在幸福路 8 号")], to: before)
    #expect(after.count == before.count + 2)
    #expect(after.first?.displayName == "自提")
    #expect(after.first { $0.displayName == "售后" }?.keywords.last == "发霉")
    #expect(after.first { $0.displayName == "讲价" }?.keywords.contains("抹零") == false)
    #expect(after.first { $0.displayName == "找真人" }?.enabled == false)
    #expect(after.last?.action == .sendText("店在幸福路 8 号"))
}

@Test("One row of the price table gets its new price; an unclear item changes nothing")
func settingsApplyPrice() throws {
    let csv = "品名,规格,价格,说明\n水蜜桃,3两左右一个,78元/斤,现摘的\n特级红富士,5斤装一箱,280元/斤,\n特级红富士,10斤装一箱,560元/斤,"
    let changed = try #require(Catalog.settingPrice(csv: csv, item: "水蜜桃", spec: "", to: "88元/斤"))
    #expect(changed.contains("水蜜桃,3两左右一个,88元/斤,现摘的") && changed.contains("560元/斤"))
    #expect(Catalog.settingPrice(csv: csv, item: "特级红富士", spec: "", to: "1元") == nil)
    let big = try #require(Catalog.settingPrice(csv: csv, item: "特级红富士", spec: "10斤装一箱", to: "600元/斤"))
    #expect(big.contains("10斤装一箱,600元/斤") && big.contains("5斤装一箱,280元/斤"))
}

@Test("The prompt shows the current rules and prices and the owner's words")
func settingsPrompt() {
    let p = SettingsAssistant.prompt(request: "售后加上发霉", snapshot: snapshot())
    #expect(p.contains("「售后」") && p.contains("水蜜桃") && p.contains("店主说：售后加上发霉"))
}

@Test("Questions get an answer and no changes; the prompt carries today's facts and the page")
func settingsQuestions() {
    var s = snapshot()
    s.page = "客户"
    s.facts = "今天已回复 12 条；等你处理 1 位：张小姐（讲价）"
    let p = SettingsAssistant.prompt(request: "今天怎么样", snapshot: s)
    #expect(p.contains("今天已回复 12 条") && p.contains("客户页"))
    let plan = SettingsAssistant.plan(from: #"{"reply":"今天回了 12 条，张小姐在等你","actions":[]}"#, snapshot: s)
    #expect(plan.changes.isEmpty && plan.problems.isEmpty && plan.reply.contains("12"))
}

@Test("Earlier lines go into the prompt so “再加一个” is understood")
func settingsPromptHistory() {
    let history = [ChatTurn(mine: true, text: "售后加上发霉"), ChatTurn(mine: false, text: "好，售后加上发霉")]
    let p = SettingsAssistant.prompt(request: "再加个有异味", snapshot: snapshot(), history: history)
    #expect(p.contains("店主：售后加上发霉") && p.contains("你：好，售后加上发霉") && p.contains("店主说：再加个有异味"))
    #expect(!SettingsAssistant.prompt(request: "x", snapshot: snapshot()).contains("前面聊过"))
}

@Test("The talk is kept on disk, the newest 100 lines, and can be cleared")
func chatLogKept() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = ChatLog(folder: dir)
    for i in 0..<105 { log.append(ChatTurn(mine: i % 2 == 0, text: "第\(i)句")) }
    #expect(log.turns.count == 100 && log.turns.first?.text == "第5句")
    #expect(ChatLog(folder: dir).turns.count == 100)
    #expect(log.recent(rounds: 2).map(\.text) == ["第101句", "第102句", "第103句", "第104句"])
    log.clear()
    #expect(ChatLog(folder: dir).turns.isEmpty)
}

@Test("“客人问…你怎么回” comes back as a customer's question to try, with no changes")
func settingsAsCustomer() {
    let plan = SettingsAssistant.plan(from: #"{"reply":"我按回客人的样子试一下","actions":[],"as_customer":" 水蜜桃多少钱 "}"#,
                                      snapshot: snapshot())
    #expect(plan.customerQuestion == "水蜜桃多少钱" && plan.changes.isEmpty)
    #expect(SettingsAssistant.plan(from: #"{"reply":"好","actions":[],"as_customer":""}"#, snapshot: snapshot()).customerQuestion == nil)
    #expect(SettingsAssistant.prompt(request: "x", snapshot: snapshot()).contains("as_customer"))
}

@Test("“水蜜桃卖完了” and “水蜜桃有货了” become checked changes to the sold-out list")
func settingsSoldOut() {
    var s = snapshot()
    let out = SettingsAssistant.plan(from: #"{"reply":"好","actions":[{"type":"sold_out","items":["水蜜桃","红富士","榴莲"]}]}"#, snapshot: s)
    // 红富士 means both sizes; 榴莲 is not in the price table.
    #expect(out.changes == [.soldOut(["水蜜桃", "特级红富士"])])
    #expect(out.problems.count == 1 && out.problems[0].contains("榴莲"))
    s.soldOut = ["水蜜桃"]
    let back = SettingsAssistant.plan(from: #"{"reply":"好","actions":[{"type":"in_stock","items":["水蜜桃","特级红富士"]}]}"#, snapshot: s)
    #expect(back.changes == [.backInStock(["水蜜桃"])])
    #expect(SettingsAssistant.prompt(request: "x", snapshot: s).contains("【卖完了的】水蜜桃"))
    #expect(SettingChange.soldOut(["水蜜桃"]).summary == "标成卖完：水蜜桃")
}

@Test("The reply is told what is sold out; the price list leaves those out")
func stockNoteAndList() throws {
    let items = [Catalog.Item(name: "水蜜桃", spec: "半斤", price: "90元/斤"), Catalog.Item(name: "当季脐橙", spec: "大", price: "90元/斤")]
    #expect(Stock.note(soldOut: []).contains("价格表上有的就是有货"))
    let note = Stock.note(soldOut: ["水蜜桃"])
    #expect(note.contains("卖完了：水蜜桃") && note.contains("下一季"))
    let list = try #require(Catalog.text(Stock.available(items, soldOut: ["水蜜桃"])))
    #expect(list.contains("当季脐橙") && !list.contains("水蜜桃"))
}
