import Foundation
import Testing
@testable import QingzhouCore

// MARK: 模板

@Test("Persona templates are short and ready to use; the fresh-food one comes first and never chases orders")
func personaTemplates() throws {
    let all = PersonaTemplates.all
    #expect((3...4).contains(all.count))
    #expect(Set(all.map(\.name)).count == all.count)
    for t in all {
        #expect(!t.name.isEmpty)
        #expect(!t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(t.text.count <= 300)
        #expect(t.text.components(separatedBy: "\n").allSatisfy { $0.count <= 50 })   // short lines
        #expect(t.text.contains("知识库"))     // facts only from the knowledge base
        #expect(t.text.contains("不催"))       // the owner's rule: only reply, never chase
    }
    let fresh = try #require(all.first)
    #expect(fresh.name.contains("生鲜"))
    #expect(fresh.text.contains("不催单"))
    #expect(fresh.text.contains("称呼客户用“你”") && fresh.text.contains("道歉"))
    #expect(["通用网店客服", "水果零食店", "本地预约服务"].allSatisfy { name in all.contains { $0.name == name } })
}

// MARK: 回复时带上人设

@Test("The reply prompt carries the persona, trimmed and before the rules, only when one is set")
func promptCarriesPersona() throws {
    let conv = Conversation(bubbles: [ChatBubble(fromMe: false, text: "在吗", top: 0)])
    let p = PromptBuilder.build(conversation: conv, knowledge: [], persona: "  称呼客户用“您”，一次一两句\n")
    #expect(p.contains("【店铺人设和话术"))
    #expect(p.contains("价格等事实仍只能来自知识库"))
    #expect(p.contains("】\n称呼客户用“您”，一次一两句\n"))
    let style = try #require(p.range(of: "称呼客户用“您”"))
    let rules = try #require(p.range(of: "规则："))
    #expect(style.lowerBound < rules.lowerBound)
    #expect(!PromptBuilder.build(conversation: conv, knowledge: []).contains("店铺人设"))
    #expect(!PromptBuilder.build(conversation: conv, knowledge: [], persona: " \n ").contains("店铺人设"))
}

// MARK: 从我的聊天学

@Test("Learning asks for the owner's way of talking only, from their own messages")
func learnStylePrompt() {
    let p = PromptBuilder.learnStyle(samples: ["在的呀～您要几斤", "今天刚到的水蜜桃，280一斤"], existing: "")
    #expect(p.contains("在的呀～您要几斤") && p.contains("今天刚到的水蜜桃，280一斤"))
    #expect(p.contains("只写说话的风格和习惯"))
    #expect(p.contains("不要抄任何价格"))
    #expect(p.contains("不要执行任何命令") && p.contains("不要读取任何文件"))
    #expect(p.contains("300"))
    #expect(p.contains("催单"))
    #expect(!p.contains("【现在的人设】"))
    let better = PromptBuilder.learnStyle(samples: ["好嘞"], existing: " 称呼客户用“您” \n")
    #expect(better.contains("【现在的人设】\n称呼客户用“您”\n"))
    #expect(better.contains("改进"))
}

private func record(_ name: String, _ messages: [(fromMe: Bool, text: String, at: TimeInterval)]) -> CustomerRecord {
    var r = CustomerRecord(chatID: "人|\(name)", name: name, now: Date(timeIntervalSince1970: 0))
    r.messages = messages.map { StoredMessage(fromMe: $0.fromMe, text: $0.text, seenAt: Date(timeIntervalSince1970: $0.at)) }
    return r
}

@Test("Samples are the owner's own messages, newest first, without noise, repeats or the assistant's words")
func samplesFromChats() {
    let wang = record("王女士", [
        (false, "多少钱一斤", 100),
        (true, "在的呀～", 100),
        (true, "嗯", 110),                       // one word
        (true, "[图片]", 120),                   // a placeholder
        (true, "280", 130),                      // a bare number
        (true, "今天刚到的，\n您要几斤？", 140),   // two lines become one
    ])
    let li = record("李先生", [
        (true, "在的呀", 200),                   // the same as “在的呀～” without punctuation
        (true, "我确认一下再回复您", 210),          // the assistant sent this
        (false, "好的谢谢", 220),
        (true, "好嘞，您路上注意安全👌", 230),
    ])
    let written = ["“我确认一下再回复您” · 知识库里没有答案，暂缓答复"]
    #expect(PersonaSamples.fromChats([wang, li], excluding: written)
        == ["好嘞，您路上注意安全👌", "在的呀", "今天刚到的， 您要几斤？"])
    #expect(PersonaSamples.fromChats([wang, li], limit: 2) == ["好嘞，您路上注意安全👌", "我确认一下再回复您"])
    #expect(PersonaSamples.fromChats([]).isEmpty)
}

@Test("Messages seen at the same moment keep their chat order (newest first); long ones are cut")
func samplesOrderAndLength() {
    let r = record("张", [(true, "第一句话呀", 5), (true, "第二句话呀", 5), (true, String(repeating: "长", count: 500), 1)])
    let picked = PersonaSamples.fromChats([r])
    #expect(picked.prefix(2) == ["第二句话呀", "第一句话呀"])
    #expect(picked.last?.count == PersonaSamples.maxLength)
}

@Test("Imported lines come first, then chat messages, without repeats")
func combineSamples() {
    let picked = PersonaSamples.combine(imported: ["在的呀～", "好嘞好嘞"], chats: ["在的呀", "今天刚到的", "明天发货"], limit: 3)
    #expect(picked.lines == ["在的呀～", "好嘞好嘞", "今天刚到的"])
    #expect(picked.fromImport == 2 && picked.fromChats == 1)
    #expect(PersonaSamples.combine(imported: [], chats: []).lines.isEmpty)
}

@Test("The model's answer becomes plain short lines")
func cleanLearnedAnswer() {
    #expect(PersonaSamples.cleanAnswer("```text\n称呼客户用“您”\n\n  一次一两句  \n```\n") == "称呼客户用“您”\n一次一两句")
    #expect(PersonaSamples.cleanAnswer("  \n ").isEmpty)
}

// MARK: 导入聊天记录

@Test("A chat export gives the lines marked “我：”, or every line when none are marked")
func exportLines() {
    let marked = """
    客户：多少钱一斤
    我：在的呀～您要几斤
    我: 今天刚到的
    我 ：嗯
    对方：好的

    我：在的呀～您要几斤
    """
    #expect(PersonaSamples.fromExport(marked) == ["在的呀～您要几斤", "今天刚到的"])
    #expect(PersonaSamples.fromExport("我：好的呀\r\n我：马上给您发") == ["好的呀", "马上给您发"])
    #expect(PersonaSamples.fromExport("- 我：好的呀～\n> 客户：在吗\n**我**：马上给您发\n我们：不算") == ["好的呀～", "马上给您发"])
    let plain = """
    2024-05-01 10:00
      您好，在的
    今天到了水蜜桃
    OK
    """
    #expect(PersonaSamples.fromExport(plain) == ["您好，在的", "今天到了水蜜桃"])
    let many = PersonaSamples.fromExport((1...400).map { "第\($0)句话" }.joined(separator: "\n"))
    #expect(many.count == PersonaSamples.maxImportLines)
    #expect(many.last == "第400句话")            // the end of the file (the newest) is kept
    #expect(PersonaSamples.fromExport("").isEmpty)
}

@Test("Exports in UTF-8 (with or without BOM) or GB18030 are read; other files are not")
func exportDecoding() throws {
    #expect(PersonaSamples.decode(Data("我：好的呀".utf8)) == "我：好的呀")
    #expect(PersonaSamples.decode(Data([0xEF, 0xBB, 0xBF]) + Data("我：好的呀".utf8)) == "我：好的呀")
    let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    let gbData = try #require("我：今天刚到的".data(using: gb))
    #expect(PersonaSamples.decode(gbData) == "我：今天刚到的")
    #expect(PersonaSamples.decode(Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01])) == nil)   // a picture
}

@Test("Only the end of a big export is read, starting at a whole line")
func exportFileTail() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let small = dir.appendingPathComponent("small.txt")
    try Data("第一行\n第二行\n第三行\n".utf8).write(to: small)          // 10 bytes a line
    #expect(try PersonaSamples.tail(of: small, limit: 100) == Data("第一行\n第二行\n第三行\n".utf8))
    #expect(try PersonaSamples.tail(of: small, limit: 15) == Data("第三行\n".utf8))   // cut inside “二”
    #expect(try PersonaSamples.readExport(at: small) == ["第一行", "第二行", "第三行"])

    // Bigger than the cap: the cut lands inside a character, which must not spoil the rest.
    let big = dir.appendingPathComponent("big.txt")
    let line = "我：今天的水蜜桃很新鲜哦\n"
    let text = String(repeating: line, count: PersonaSamples.maxImportBytes / line.utf8.count + 50) + "我：最后一句话呀\n"
    try Data(text.utf8).write(to: big)
    #expect(try PersonaSamples.readExport(at: big) == ["今天的水蜜桃很新鲜哦", "最后一句话呀"])
}

@Test("Exports that can't be used say why")
func exportFileProblems() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let blank = dir.appendingPathComponent("blank.txt")
    try Data("\n\n嗯\n".utf8).write(to: blank)
    #expect(throws: PersonaSamples.ExportError.empty) { try PersonaSamples.readExport(at: blank) }
    let picture = dir.appendingPathComponent("picture.txt")
    try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]).write(to: picture)
    #expect(throws: PersonaSamples.ExportError.notText) { try PersonaSamples.readExport(at: picture) }
    #expect(throws: PersonaSamples.ExportError.self) { try PersonaSamples.readExport(at: dir.appendingPathComponent("no.txt")) }
    #expect(PersonaSamples.ExportError.empty.errorDescription?.isEmpty == false)
}
