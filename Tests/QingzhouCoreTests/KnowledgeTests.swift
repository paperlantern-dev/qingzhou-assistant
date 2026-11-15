import Foundation
import Testing
@testable import QingzhouCore

/// Writes files into a fresh temp folder and loads them as a knowledge base.
private func makeKB(_ files: [String: String]) throws -> KnowledgeBase {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kb-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, text) in files { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    return KnowledgeBase.load(folder: dir)
}

private let faq = """
# 发货
付款后 48 小时内从杭州仓发货，默认中通快递。

# 发票
支持电子普通发票，下单时备注抬头和税号。

# 退换货
支持七天无理由退货，运费由买家承担。定制商品除外。
"""

@Test("Markdown is split into passages by heading")
func splitsByHeading() throws {
    let kb = try makeKB(["faq.md": faq, "ignore.png": "x"])
    #expect(kb.files == ["faq.md"])
    #expect(kb.chunks.count == 3)
}

@Test("Search finds the right passage for a question", arguments: [
    ("订单什么时候能发货？", "48 小时"),
    ("那能开发票吗？", "电子普通发票"),
    ("支持七天无理由退货吗", "七天无理由"),
])
func searchFindsPassage(question: String, expected: String) throws {
    let kb = try makeKB(["faq.md": faq])
    let top = try #require(kb.search(question).first)
    #expect(top.chunk.text.contains(expected))
}

@Test("Unrelated questions find nothing")
func searchUnrelated() throws {
    let kb = try makeKB(["faq.md": faq])
    #expect(kb.search("周日有线下门店可以试穿吗").isEmpty)
}

@Test("Each CSV row becomes a labeled passage")
func csvRows() throws {
    let kb = try makeKB(["price.csv": "问题,答案\n满多少包邮,满 99 元包邮\n会员折扣,9.5 折\n"])
    #expect(kb.chunks.map(\.text) == ["问题：满多少包邮；答案：满 99 元包邮", "问题：会员折扣；答案：9.5 折"])
    #expect(kb.search("多少钱包邮").first?.chunk.text.contains("99") == true)
}

@Test("Empty folder is an empty knowledge base")
func emptyFolder() throws {
    #expect(try makeKB([:]).isEmpty)
}

@Test("Parser reads citations and reply, dropping unknown ids")
func parsesReply() {
    let r = ReplyParser.parse("引用：2, 9\n回复：可以的，下单时备注抬头和税号就行。", allowed: [1, 2, 3])
    #expect(r == ParsedReply(citations: [2], text: "可以的，下单时备注抬头和税号就行"))
    #expect(r?.hasBasis == true)
}

@Test("“无” means no basis; missing format is rejected")
func parsesNoBasis() {
    #expect(ReplyParser.parse("引用：无\n回复：我确认一下再回复您", allowed: [1])?.hasBasis == false)
    #expect(ReplyParser.parse("随便说点什么", allowed: [1]) == nil)
}

@Test("Prompt contains numbered passages and the format rules")
func promptHasKnowledge() {
    let conv = Conversation(bubbles: [ChatBubble(fromMe: false, text: "能开发票吗", top: 0)])
    let p = PromptBuilder.build(conversation: conv, knowledge: [KnowledgeChunk(id: 7, source: "faq.md", text: "支持电子普通发票")])
    #expect(p.contains("[7]（来自 faq.md）\n支持电子普通发票"))
    #expect(p.contains("引用："))
    #expect(p.contains("对方：能开发票吗"))
}

@Test("Parser reads the message type: small talk is confident without citations")
func parsesSmallTalk() {
    let hi = ReplyParser.parse("类型：寒暄\n引用：无\n回复：不客气～", allowed: [1])
    #expect(hi?.isSmallTalk == true)
    #expect(hi?.hasBasis == false)
    #expect(hi?.isConfident == true)
    let unknown = ReplyParser.parse("类型：问题\n引用：无\n回复：我确认一下再回复您", allowed: [1])
    #expect(unknown?.isConfident == false)
    let known = ReplyParser.parse("类型：问题\n引用：1\n回复：满99包邮", allowed: [1])
    #expect(known?.isConfident == true)
    // Older two-line answers still parse; without a type they are not small talk.
    #expect(ReplyParser.parse("引用：无\n回复：好的", allowed: [1])?.isSmallTalk == false)
}

@Test("A reply may be two messages, never more")
func parsesTwoMessages() {
    let raw = "类型：问题\n引用：2\n预留：无\n授权：无\n撤回：无\n回复：单笔满99元包邮～\n回复2：您大概要买多少呀？"
    #expect(ReplyParser.parse(raw, allowed: [2])?.messages == ["单笔满99元包邮", "你大概要买多少呀？"])
    let three = ReplyParser.parse("引用：无\n回复：一\n回复2：二\n回复3：三", allowed: [])
    #expect(three?.messages.count == 2)
}

@Test("Reservations, consent and opt-outs are read from the reply")
func parsesPermissions() {
    let keep = ReplyParser.parse("类型：问题\n引用：无\n预留：红富士，两箱\n授权：无\n撤回：无\n回复：好的，帮您留着", allowed: [])
    #expect(keep?.reservation == "红富士，两箱")
    #expect(keep?.consentInterests == nil)
    let news = ReplyParser.parse("类型：问题\n引用：无\n预留：无\n授权：水果\n撤回：无\n回复：好的，有新货告诉您", allowed: [])
    #expect(news?.consentInterests == "水果")
    #expect(news?.reservation == nil)
    let stop = ReplyParser.parse("类型：寒暄\n引用：无\n预留：无\n授权：无\n撤回：是\n回复：好的，不打扰您", allowed: [])
    #expect(stop?.optOut == true)
}

@Test("“帮我留…到了告诉我” is a reservation only, not permission to send news")
func reservationIsNotConsent() {
    let raw = "类型：问题\n引用：无\n预留：特级红富士2箱\n授权：特级红富士\n撤回：无\n回复：好的，给您记下"
    let parsed = ReplyParser.parse(raw, allowed: [])
    #expect(parsed?.reservation == "特级红富士2箱")
    #expect(parsed?.consentInterests == nil)
}

private let priceList = """
品名,规格,价格,说明
特级红富士,5斤装一箱,280元/斤,当季特级
当季脐橙,中果,60元/斤,家常吃
水蜜桃,每个半斤左右,78元/斤,夏季最甜
"""

@Test("“有什么产品” gets the whole price list, though no row says 产品", arguments: [
    "你们有什么产品", "都卖些啥", "有哪些水果", "发个价格表看看",
])
func catalogQuestionsSeeEveryProduct(question: String) throws {
    let kb = try makeKB(["商品与价格.csv": priceList, "faq.md": faq])
    let texts = kb.passages(for: question).map(\.text).joined()
    #expect(texts.contains("红富士") && texts.contains("脐橙") && texts.contains("水蜜桃"))
}

@Test("A small knowledge base goes along whole; a big one only the matches, plus products for list questions")
func bigKnowledgeBaseIsSearched() throws {
    let filler = (1...60).map { "# 说明\($0)\n第\($0)条售后细则，与商品无关的长段文字。" + String(repeating: "售后细则说明。", count: 20) }
    let kb = try makeKB(["商品与价格.csv": priceList, "faq.md": faq, "long.md": filler.joined(separator: "\n\n")])
    #expect(kb.passages(for: "订单什么时候能发货？").count < kb.chunks.count)
    #expect(kb.passages(for: "订单什么时候能发货？").contains { $0.text.contains("48 小时") })
    #expect(kb.passages(for: "你们有什么产品").filter { $0.source == "商品与价格.csv" }.count == 3)
    let small = try makeKB(["商品与价格.csv": priceList, "faq.md": faq])
    #expect(small.passages(for: "订单什么时候能发货？").count == small.chunks.count)
}

@Test("Replies say 你, never 您, and the prompt asks for plain, list-style answers")
func repliesSoundLikeTheOwner() throws {
    let raw = "类型：问题\n引用：1\n回复：不好意思，刚刚给您配少了\n· 特级红富士 1箱 280元\n合计 280 元\n回复2：您看行吗"
    let parsed = try #require(ReplyParser.parse(raw, allowed: [1]))
    #expect(parsed.text == "不好意思，刚刚给你配少了\n· 特级红富士 1箱 280元\n合计 280 元" && parsed.second == "你看行吗")
    let prompt = PromptBuilder.build(conversation: Conversation(bubbles: []), knowledge: [])
    #expect(prompt.contains("不要用“您”") && prompt.contains("一行一样竖着排") && prompt.contains("合计"))
}

@Test("Files brought into the knowledge folder never overwrite one already there")
func knowledgeImportNames() {
    #expect(KnowledgeImport.destinationName(for: "价格.csv", existing: []) == "价格.csv")
    #expect(KnowledgeImport.destinationName(for: "价格.csv", existing: ["价格.csv"]) == "价格 2.csv")
    #expect(KnowledgeImport.destinationName(for: "价格.csv", existing: ["价格.csv", "价格 2.csv"]) == "价格 3.csv")
    #expect(KnowledgeImport.isSupported(URL(fileURLWithPath: "/a/b.docx")) && !KnowledgeImport.isSupported(URL(fileURLWithPath: "/a/b.zip")))
}
