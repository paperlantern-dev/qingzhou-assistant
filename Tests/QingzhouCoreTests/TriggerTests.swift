import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import QingzhouCore

// MARK: 关键词触发

private func textRule(_ keywords: [String], _ text: String = "价目表发您了", enabled: Bool = true) -> TriggerRule {
    TriggerRule(keywords: keywords, action: .sendText(text), enabled: enabled)
}

@Test("A rule fires when the newest message contains one of its keywords, loosely")
func triggerMatchesLoosely() {
    let rule = textRule(["价格", "多少钱"])
    #expect(rule.keyword(in: "特级红富士多少钱一斤？") == "多少钱")
    #expect(rule.keyword(in: "红富士 多少 钱一斤") == "多少钱")       // OCR may split words with spaces
    #expect(textRule(["多少钱？"]).keyword(in: "多少钱一斤") == "多少钱？")   // punctuation in the keyword
    #expect(textRule([" 多少钱 "]).keyword(in: "多少钱") == "多少钱")
    #expect(rule.keyword(in: "脐橙怎么保存？") == nil)
    #expect(rule.keyword(in: "") == nil)
}

@Test("Latin keywords match whatever the letter case")
func triggerIgnoresCase() {
    #expect(textRule(["VIP"]).keyword(in: "我是vip客户") == "VIP")
}

@Test("Switched-off rules and empty keywords never fire")
func triggerOffOrEmpty() {
    #expect(textRule(["多少钱"], enabled: false).keyword(in: "多少钱") == nil)
    #expect(textRule(["", "  ", "，"]).keyword(in: "多少钱，在吗") == nil)
    #expect(textRule([]).keyword(in: "多少钱") == nil)
}

@Test("A rule with nothing to send never fires; handing over needs no reason")
func triggerNeedsSomethingToDo() {
    #expect(textRule(["多少钱"], "  ").keyword(in: "多少钱") == nil)
    #expect(TriggerRule(keywords: ["多少钱"], action: .sendImage(path: "")).keyword(in: "多少钱") == nil)
    #expect(TriggerRule(keywords: ["多少钱"], action: .sendImage(path: "/a/价目表.png")).keyword(in: "多少钱") == "多少钱")
    #expect(TriggerRule(keywords: ["退款"], action: .handOver(reason: "")).keyword(in: "我要退款") == "退款")
    #expect(!textRule(["多少钱"], "").isComplete)
    #expect(textRule(["多少钱"]).isComplete)
}

@Test("The first matching rule wins")
func triggerFirstMatchWins() throws {
    let handOver = TriggerRule(keywords: ["退款"], action: .handOver(reason: ""))
    let price = textRule(["多少钱", "退款"])
    let first = try #require(TriggerRule.firstMatch([handOver, price], message: "退款要多少钱"))
    #expect(first.rule == handOver)
    #expect(first.keyword == "退款")
    var off = handOver
    off.enabled = false
    let next = try #require(TriggerRule.firstMatch([off, price], message: "退款要多少钱"))
    #expect(next.rule == price)
    #expect(next.keyword == "多少钱")
    #expect(TriggerRule.firstMatch([handOver, price], message: "你好") == nil)
    #expect(TriggerRule.firstMatch([], message: "退款") == nil)
}

@Test("Keywords typed with commas, 、 or spaces are split, without repeats")
func triggerKeywordsFromText() {
    #expect(TriggerRule.keywords(from: "投诉，退款、坏了, 差评;；投诉") == ["投诉", "退款", "坏了", "差评"])
    #expect(TriggerRule.keywords(from: " 多少钱  价格\n报价 ") == ["多少钱", "价格", "报价"])
    #expect(TriggerRule.keywords(from: "，、 ").isEmpty)
    #expect(textRule(["投诉", "退款"]).keywordText == "投诉、退款")
}

@Test("Handing over says why: the owner's reason, or the word the customer used")
func triggerHandOverReason() {
    #expect(TriggerRule(keywords: ["退款"], action: .handOver(reason: "")).handOverReason(keyword: "退款") == "提到“退款”")
    #expect(TriggerRule(keywords: ["退款"], action: .handOver(reason: " 售后问题 ")).handOverReason(keyword: "退款") == "售后问题")
}

@Test("Preset rules: money and blame go to the owner, list questions get the price list")
func triggerPresets() throws {
    let rules = TriggerRule.presets
    func action(_ message: String) -> TriggerRule.Action? { TriggerRule.firstMatch(rules, message: message)?.rule.action }
    #expect(action("货收到就坏了！") == .handOver(reason: "售后问题"))
    #expect(action("你是机器人吗") == .handOver(reason: "客人要找真人"))
    #expect(action("能便宜点吗") == .handOver(reason: "客人在讲价"))
    #expect(action("怎么付款") == .handOver(reason: "客人要付款或下单"))
    #expect(action("你们有什么产品") == .sendCatalog)
    #expect(action("今天有什么水果？") == .sendCatalog)
    #expect(action("货坏了，你们还卖什么") == .handOver(reason: "售后问题"))   // after-sales first
    // Everyday questions don't fire a rule
    for q in ["是人工催熟的吗", "你们发什么快递", "红富士多少钱一斤", "老板在吗", "脐橙怎么保存"] {
        #expect(action(q) == nil, "\(q)")
    }
    #expect(TriggerRule.missingPresets(in: rules).isEmpty)
    #expect(TriggerRule.missingPresets(in: Array(rules.dropFirst())).count == 1)
}

@Test("Switching an action's kind keeps what the owner wrote for each kind")
func triggerActionKinds() {
    #expect(TriggerRule.Action(kind: .text, content: "你好") == .sendText("你好"))
    #expect(TriggerRule.Action(kind: .image, content: "/a.png") == .sendImage(path: "/a.png"))
    #expect(TriggerRule.Action(kind: .handOver, content: "售后") == .handOver(reason: "售后"))
    #expect(TriggerRule.Action.sendImage(path: "/a.png").kind == .image)
    #expect(TriggerRule.Action.handOver(reason: "售后").content == "售后")
    #expect(TriggerRule.Kind.allCases.map(\.rawValue) == ["发一段话", "发一张图片", "发价格表", "交给我处理"])
    #expect(TriggerRule.Action(kind: .catalog, content: "") == .sendCatalog)
}

@Test("The run log says what a rule does")
func triggerSummary() {
    #expect(TriggerRule.Action.sendText("你好").summary == "发一段话：你好")
    #expect(TriggerRule.Action.sendImage(path: "/a/价目表.png").summary == "发图片：价目表.png")
    #expect(TriggerRule.Action.handOver(reason: "售后").summary == "交给我处理")
}

@Test("Rules survive saving, and rules saved by the first version still load")
func triggerCoding() throws {
    let rules = [textRule(["多少钱"]), TriggerRule(keywords: ["图"], action: .sendImage(path: "/a/b.png"), enabled: false),
                 TriggerRule(keywords: ["价格表"], action: .sendCatalog)]
    let back = try JSONDecoder().decode([TriggerRule].self, from: JSONEncoder().encode(rules))
    #expect(back == rules)

    let old = #"""
    [{"id":"7D3F1C2A-0B4E-4F57-9A51-2C9B5E0F1A11","keywords":["价格"],"action":{"sendText":{"_0":"见图"}},"enabled":false},
     {"keywords":["图"],"action":{"sendImage":{"path":"/a/b.png"}}},
     {"keywords":["投诉"],"action":{"handOver":{"reason":"售后"}}}]
    """#
    let loaded = try JSONDecoder().decode([TriggerRule].self, from: Data(old.utf8))
    #expect(loaded.count == 3)
    #expect(loaded[0].id.uuidString == "7D3F1C2A-0B4E-4F57-9A51-2C9B5E0F1A11")
    #expect(loaded[0].action == .sendText("见图"))
    #expect(!loaded[0].enabled)
    #expect(loaded[1].enabled)                                   // missing fields get their defaults
    #expect(loaded[1].action == .sendImage(path: "/a/b.png"))
    #expect(loaded[2].action == .handOver(reason: "售后"))
}

// MARK: 发图片: the picture folder

private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qz-pictures-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("Only common picture files count as pictures")
func pictureTypes() {
    for name in ["a.png", "b.JPG", "c.jpeg", "d.heic", "e.gif", "f.webp"] {
        #expect(PictureLibrary.isPicture(URL(fileURLWithPath: "/x/\(name)")), "\(name)")
    }
    for name in ["a.txt", "b.pdf", "c", "d.png.zip"] {
        #expect(!PictureLibrary.isPicture(URL(fileURLWithPath: "/x/\(name)")), "\(name)")
    }
}

@Test("A picked picture is copied into the app folder, keeping its name and avoiding clashes")
func pictureImport() throws {
    let root = try tempFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("下载"), library = root.appendingPathComponent("图片")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let first = source.appendingPathComponent("价目表.png")
    try Data("first".utf8).write(to: first)

    let copied = try PictureLibrary.importPicture(first, into: library)
    #expect(copied.lastPathComponent == "价目表.png")
    #expect(copied.deletingLastPathComponent().lastPathComponent == "图片")
    #expect(try Data(contentsOf: copied) == Data("first".utf8))
    #expect(try PictureLibrary.importPicture(first, into: library) == copied)   // the same picture again: no copy

    let other = source.appendingPathComponent("sub/价目表.png")
    try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("second".utf8).write(to: other)
    let second = try PictureLibrary.importPicture(other, into: library)
    #expect(second.lastPathComponent == "价目表 2.png")
    #expect(try Data(contentsOf: second) == Data("second".utf8))
    #expect(try PictureLibrary.importPicture(second, into: library) == second)   // already in the folder
}

@Test("Missing files and other kinds of files are not imported")
func pictureImportRefuses() throws {
    let library = try tempFolder()
    defer { try? FileManager.default.removeItem(at: library) }
    #expect(throws: PictureError.missing("没有.png")) {
        try PictureLibrary.importPicture(URL(fileURLWithPath: "/nowhere/没有.png"), into: library)
    }
    let text = library.appendingPathComponent("说明.txt")
    try Data("x".utf8).write(to: text)
    #expect(throws: PictureError.notAPicture("说明.txt")) { try PictureLibrary.importPicture(text, into: library) }
    #expect(PictureError.missing("a.png").errorDescription?.contains("a.png") == true)
}

@Test("Numbered names keep the extension")
func pictureNumberedNames() {
    #expect(PictureLibrary.numbered("a.png", 1) == "a.png")
    #expect(PictureLibrary.numbered("a.png", 2) == "a 2.png")
    #expect(PictureLibrary.numbered("价目表", 3) == "价目表 3")
}

@Test("The clipboard gets the picture at its own size, at most 4096 px")
func picturePasteboardData() throws {
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    func png(_ w: Int, _ h: Int) throws -> URL {
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let url = folder.appendingPathComponent("p\(w)x\(h).png")
        let image = try #require(ctx.makeImage())
        try #require(WindowCapture.pngData(image)).write(to: url)
        return url
    }
    let small = try #require(AutoSender.pictureData(try png(300, 200)))
    let rep = try #require(NSBitmapImageRep(data: small.png))
    #expect(rep.pixelsWide == 300 && rep.pixelsHigh == 200)
    #expect(NSBitmapImageRep(data: small.tiff)?.pixelsWide == 300)
    let wide = try #require(AutoSender.pictureData(try png(5000, 50)))
    #expect(NSBitmapImageRep(data: wide.png)?.pixelsWide == 4096)
    #expect(AutoSender.pictureData(folder.appendingPathComponent("none.png")) == nil)
}

// MARK: 发图片: checking it arrived

// Window 1000x800 pt at 1 px per point, mock layout: sidebar 220, header 86, input 150.
private let layout = ChatTarget.mockWeChat.layout
private let windowSize = CGSize(width: 1000, height: 800)

/// A light window with dark boxes at the given places (window points, top-left origin).
private func window(_ boxes: [CGRect] = []) -> CGImage {
    let w = Int(windowSize.width), h = Int(windowSize.height)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1))
    for b in boxes { ctx.fill(CGRect(x: b.minX, y: CGFloat(h) - b.maxY, width: b.width, height: b.height)) }
    return ctx.makeImage()!
}

private func pane(_ image: CGImage) -> [UInt8] {
    PictureCheck.paneFingerprint(image, windowSize: windowSize, layout: layout)
}

@Test("Only changes in the message pane count")
func picturePaneChanges() {
    let empty = pane(window())
    #expect(!empty.isEmpty)
    #expect(!PictureCheck.changed(empty, pane(window())))
    #expect(PictureCheck.changed(empty, pane(window([CGRect(x: 700, y: 400, width: 160, height: 160)]))))   // a picture
    #expect(!PictureCheck.changed(empty, pane(window([CGRect(x: 20, y: 300, width: 180, height: 60)]))))    // contact list
    #expect(!PictureCheck.changed(empty, pane(window([CGRect(x: 300, y: 700, width: 400, height: 60)]))))   // input box
    #expect(!PictureCheck.changed(empty, pane(window([CGRect(x: 600, y: 300, width: 2, height: 2)]))))      // a speck
    #expect(!PictureCheck.changed([], []))
}

private func them(_ text: String) -> ChatBubble { ChatBubble(fromMe: false, text: text, top: 0) }
private func me(_ text: String) -> ChatBubble { ChatBubble(fromMe: true, text: text, top: 0) }

@Test("A pasted picture counts as sent only when nothing else explains the change")
func pictureConfirmation() {
    let before = Conversation(bubbles: [me("在的"), them("红富士多少钱？")], title: "客户·王女士")
    func check(_ after: [ChatBubble], changed: Bool = true, input: String = "") -> Bool {
        PictureCheck.confirmed(before: before, after: Conversation(bubbles: after, title: "客户·王女士"),
                               paneChanged: changed, inputText: input, fileName: "价目表.png")
    }
    #expect(check([me("在的"), them("红富士多少钱")]))                 // the picture shows no text
    #expect(check([them("红富士多少钱？"), me("红富士 88元/斤")]))     // text inside the picture
    #expect(!check([me("在的"), them("红富士多少钱？")], changed: false))
    #expect(!check([me("在的"), them("红富士多少钱？")], input: "价目表"))   // something is left in the input box
    #expect(check([me("在的"), them("红富士多少钱？")], input: "l"))        // a stray mark (the caret) is not text
    #expect(!check([them("红富士多少钱？"), them("在吗")]))             // they wrote again: can't tell
    #expect(!check([them("红富士多少钱？"), me("file:///Users/a/图片/价目表.png")]))   // pasted as text
    let quiet = Conversation(bubbles: [me("您好")], title: "客户·王女士")
    #expect(!PictureCheck.confirmed(before: quiet, after: Conversation(bubbles: [me("您好"), them("嗯")]),
                                    paneChanged: true, inputText: "", fileName: "a.png"))
}

@Test("Handing over looks at everything they sent; other rules only at the newest message")
func triggerMatchPending() {
    let rules = TriggerRule.presets
    #expect(TriggerRule.match(rules, pending: ["水蜜桃能便宜点吗", "请问支持七天无理由退货吗？"])?.rule.action
            == .handOver(reason: "客人在讲价"))
    #expect(TriggerRule.match(rules, pending: ["你们有什么产品"])?.rule.action == .sendCatalog)
    #expect(TriggerRule.match(rules, pending: ["发个价格表看看", "满多少包邮啊"]) == nil)   // the AI answers both
    #expect(TriggerRule.match(rules, pending: ["货坏了", "你们还卖什么"])?.rule.action == .handOver(reason: "售后问题"))
}
