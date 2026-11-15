import AppKit
import Testing
@testable import QingzhouCore

/// Renders text into an image in memory, so OCR has to actually read it.
private func render(_ text: String) -> CGImage {
    let size = NSSize(width: 900, height: 120)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    (text as NSString).draw(at: NSPoint(x: 20, y: 40), withAttributes: [
        .font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black,
    ])
    image.unlockFocus()
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

@Test("Vision OCR reads a random code it has never seen")
func ocrReadsRandomCode() throws {
    let code = "QZ-\(Int.random(in: 1000...9999))"
    let result = try OCRService.recognize(render("编号 \(code) 明天开会"))
    #expect(result.text.contains(code))
    #expect(result.text.contains("开会"))
}

@Test("OCR returns nothing for a blank image")
func ocrBlankImage() throws {
    #expect(try OCRService.recognize(render("")).lines.isEmpty)
}

// Window 1000x800 pt, mock layout: sidebar 220, header 86, input 150 → pane x 220...1000.
private let layout = ChatTarget.mockWeChat.layout
private let win = CGSize(width: 1000, height: 800)

/// Builds an OCR line from point coordinates (top-left origin), like Vision would report.
private func line(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 18) -> OCRLine {
    OCRLine(text: text, confidence: 1,
            box: CGRect(x: x / win.width, y: 1 - (y + h) / win.height, width: w / win.width, height: h / win.height))
}

@Test("Parser splits left (them) and right (me) bubbles and merges wrapped lines")
func parserSides() {
    let lines = [
        line("客户·王女士", x: 240, y: 50, w: 120),          // header → ignored
        line("文件传输助手", x: 60, y: 300, w: 100),          // sidebar → ignored
        line("你好，请问订单什么", x: 300, y: 120, w: 300),
        line("时候发货？", x: 300, y: 140, w: 100),           // wrapped line of same bubble
        line("今天下午就发", x: 800, y: 200, w: 120),
        line("能开发票吗", x: 300, y: 260, w: 120),
        line("草稿文字", x: 240, y: 700, w: 100),             // input area → ignored
    ]
    let conv = ChatParser.parse(lines, windowSize: win, layout: layout)
    #expect(conv.bubbles.map(\.fromMe) == [false, true, false])
    #expect(conv.bubbles[0].text == "你好，请问订单什么时候发货？")
    #expect(conv.pendingIncoming.map(\.text) == ["能开发票吗"])
}

@Test("Nothing is pending when I spoke last")
func parserNothingPending() {
    let conv = ChatParser.parse([
        line("在吗", x: 300, y: 120, w: 60),
        line("在的", x: 880, y: 180, w: 60),
    ], windowSize: win, layout: layout)
    #expect(conv.pendingIncoming.isEmpty)
    #expect(conv.pendingKey.isEmpty)
}

@Test("Small OCR differences count as the same message")
func textSimilarity() {
    let a = TextMatch.normalize("你好，请问订单 QZ-1234 什么时候能发货？")
    let b = TextMatch.normalize("你好,请问订单QZ-1234什么时候能发货")
    #expect(TextMatch.similar(a, b))
    #expect(!TextMatch.similar(a, TextMatch.normalize("能开发票吗")))
}

@Test("Human pacing stays inside its ranges")
func pacingRanges() {
    var rng = SystemRandomNumberGenerator()
    let p = HumanPacer(config: .human)
    for _ in 0..<200 {
        #expect(PacingConfig.human.readDelay.contains(p.readDelay(using: &rng)))
        #expect(p.typingDelay(for: String(repeating: "字", count: 500), using: &rng) <= PacingConfig.human.maxTyping)
    }
}

@Test("Prompt labels who said what")
func promptHasRoles() {
    let conv = Conversation(bubbles: [
        ChatBubble(fromMe: false, text: "在吗", top: 0),
        ChatBubble(fromMe: true, text: "在的", top: 1),
        ChatBubble(fromMe: false, text: "能开发票吗", top: 2),
    ])
    let p = PromptBuilder.build(conversation: conv, knowledge: [])
    #expect(p.contains("对方：在吗\n我：在的\n对方：能开发票吗"))
}

@Test("Engines report where they run")
func engineLabels() {
    #expect(OllamaEngine().runsOnDevice)
    #expect(!CodexCLIEngine().runsOnDevice)
}

@Test("Voice messages are recognized by their length mark", arguments: [
    ("5\"", 5), ("12”", 12), ("3″", 3), ("》5\"", 5),
    ("满99包邮", nil), ("07:16", nil), ("5个", nil),
] as [(String, Int?)])
func voiceToken(text: String, seconds: Int?) {
    #expect(Voice.seconds(in: text) == seconds)
}

@Test("A voice bubble needs 转文字 until its words show up below it")
func voiceBubbleTranscript() {
    let only = ChatParser.parse([line("5\"", x: 300, y: 300, w: 40)], windowSize: win, layout: layout)
    #expect(only.bubbles.first?.needsTranscript == true)
    #expect(only.bubbles.first?.text == "[语音5秒]")
    let done = ChatParser.parse([line("5\"", x: 300, y: 300, w: 40),
                                 line("你好，满多少包邮啊？", x: 300, y: 322, w: 160)], windowSize: win, layout: layout)
    #expect(done.bubbles.count == 1)
    #expect(done.bubbles.first?.needsTranscript == false)
    #expect(done.bubbles.first?.text == "[语音5秒]你好，满多少包邮啊？")
}

@Test("WeChat 4.1: the “转文字” button next to a voice message is found, also when read into the same line")
func voiceButton() {
    let separate = ChatParser.parse([line("• 3\"", x: 383, y: 300, w: 35), line("转文字", x: 492, y: 301, w: 37)],
                                    windowSize: win, layout: layout)
    #expect(separate.bubbles.count == 1)
    #expect(separate.bubbles.first?.needsTranscript == true)
    #expect(separate.bubbles.first?.transcribeButton != nil)
    let merged = ChatParser.parse([line("• 3\" 转文字", x: 383, y: 300, w: 150)], windowSize: win, layout: layout)
    #expect(merged.bubbles.first?.text == "[语音3秒]")
    #expect(merged.bubbles.first?.transcribeButton != nil)
}

/// A window picture with a green (mine) bubble and a white (theirs) bubble, both reaching far left.
private func bubbleWindow() -> CGImage {
    let scale: CGFloat = 2
    let ctx = CGContext(data: nil, width: Int(win.width * scale), height: Int(win.height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
    ctx.fill(CGRect(origin: .zero, size: win))
    ctx.setFillColor(NSColor(red: 0.58, green: 0.93, blue: 0.41, alpha: 1).cgColor)   // WeChat green
    ctx.fill(CGRect(x: 280, y: win.height - 330, width: 680, height: 40))           // y 290…330 from top
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: 280, y: win.height - 430, width: 680, height: 40))           // y 390…430 from top
    return ctx.makeImage()!
}

@Test("A long green bubble is mine even when it reaches the left side (real WeChat bug)")
func longGreenBubbleIsMine() {
    let lines = [line("不好意思，您发的我没看明白，您想看什么东西呀？我确认一下再回复您", x: 300, y: 300, w: 640),
                 line("你好，请问你们那边有什么产品可以推荐给我看看呢谢谢", x: 300, y: 400, w: 640)]
    let conv = ChatParser.parse(lines, windowSize: win, layout: layout, image: bubbleWindow())
    #expect(conv.bubbles.map(\.fromMe) == [true, false])
}

@Test("“2•” next to a 转文字 button is a voice message; the button itself is not a message")
func bareVoiceNextToButton() {
    let conv = ChatParser.parse([line("2•", x: 300, y: 300, w: 30), line("• 转文字", x: 420, y: 301, w: 50)],
                                windowSize: win, layout: layout)
    #expect(conv.bubbles.count == 1)
    #expect(conv.bubbles.first?.text == "[语音2秒]")
    #expect(conv.bubbles.first?.transcribeButton != nil)
    // Without a button, a short number is just a number.
    #expect(ChatParser.parse([line("2•", x: 300, y: 300, w: 30)], windowSize: win, layout: layout)
        .bubbles.first?.voiceSeconds == nil)
}
