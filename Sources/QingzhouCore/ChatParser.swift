import CoreGraphics
import Foundation

/// Where things sit inside a chat window, in points from the window edges.
public struct ChatLayout {
    public let sidebarWidth: CGFloat   // contact list on the left
    public let headerHeight: CGFloat   // title bar + contact name bar
    public let inputHeight: CGFloat    // input area at the bottom
    public let inputClickFromBottom: CGFloat // where to click to focus the input box
    public let titleBarHeight: CGFloat  // window title bar (its text is not the chat name)
    public let listTop: CGFloat         // where the contact list starts (below the search box)
    /// Horizontal band where unread badges sit (top-right corner of contact avatars).
    public let badgeMinX: CGFloat
    public let badgeMaxX: CGFloat
    /// Where a contact row's name / preview text starts.
    public let rowTextMinX: CGFloat
    /// Right edge of contact avatars. A real badge sticks out past it; red inside a photo does not.
    public let avatarRight: CGFloat
    /// Where typed text shows in the input box, in points from the window bottom (toolbar excluded).
    public let inputTextFromBottom: ClosedRange<CGFloat>

    public init(sidebarWidth: CGFloat, headerHeight: CGFloat, inputHeight: CGFloat, inputClickFromBottom: CGFloat,
                titleBarHeight: CGFloat = 28, listTop: CGFloat = 84,
                badgeMinX: CGFloat = 0, badgeMaxX: CGFloat = 1000, rowTextMinX: CGFloat = 0, avatarRight: CGFloat = 0,
                inputTextFromBottom: ClosedRange<CGFloat> = 45...140) {
        self.inputTextFromBottom = inputTextFromBottom
        self.avatarRight = avatarRight
        self.badgeMinX = badgeMinX
        self.badgeMaxX = badgeMaxX
        self.rowTextMinX = rowTextMinX
        self.sidebarWidth = sidebarWidth
        self.headerHeight = headerHeight
        self.inputHeight = inputHeight
        self.inputClickFromBottom = inputClickFromBottom
        self.titleBarHeight = titleBarHeight
        self.listTop = listTop
    }

    /// The same layout with the contact list and input box as wide and high as they are on screen
    /// (the user can drag both dividers). nil keeps the measured value.
    public func resized(sidebarWidth: CGFloat?, inputHeight: CGFloat?) -> ChatLayout {
        let input = inputHeight ?? self.inputHeight
        let grown = input - self.inputHeight
        return ChatLayout(sidebarWidth: sidebarWidth ?? self.sidebarWidth, headerHeight: headerHeight, inputHeight: input,
                          inputClickFromBottom: min(inputClickFromBottom, input - 20), titleBarHeight: titleBarHeight,
                          listTop: listTop, badgeMinX: badgeMinX, badgeMaxX: badgeMaxX, rowTextMinX: rowTextMinX,
                          avatarRight: avatarRight,
                          inputTextFromBottom: inputTextFromBottom.lowerBound...max(inputTextFromBottom.lowerBound + 10,
                                                                                    inputTextFromBottom.upperBound + grown))
    }
}

public struct ChatBubble: Equatable {
    public let fromMe: Bool
    public let text: String
    public let top: CGFloat
    /// Set for a voice message (its length in seconds).
    public let voiceSeconds: Int?
    /// Center of the bubble's first line, in window points (where to right-click it).
    public let anchor: CGPoint
    /// WeChat 4.1 shows a “转文字” button right next to a voice message: where it is, if seen.
    public var transcribeButton: CGPoint?
    /// A picture or sticker (its text is then "[图片]" or "[表情]").
    public var media: MediaKind?
    /// WeChat shows a red “!” beside it: it was not sent.
    public var failed = false
    /// Where a picture or sticker is, in window points (to cut it out and look at it).
    public var frame: CGRect?

    public init(fromMe: Bool, text: String, top: CGFloat, voiceSeconds: Int? = nil, anchor: CGPoint = .zero,
                transcribeButton: CGPoint? = nil, media: MediaKind? = nil) {
        self.fromMe = fromMe
        self.text = text
        self.top = top
        self.voiceSeconds = voiceSeconds
        self.anchor = anchor
        self.transcribeButton = transcribeButton
        self.media = media
    }

    /// A voice message whose words are not on screen yet (no “转文字” text below it).
    public var needsTranscript: Bool { voiceSeconds.map { text == Voice.label($0) } ?? false }
}

/// Voice messages show only their length, e.g. 5" — no words until “转文字”.
public enum Voice {
    /// Seconds of a voice message line such as 5" (OCR may add the unread dot in front, or read
    /// the “转文字” button next to it into the same line: "• 3\" 转文字").
    public static func seconds(in text: String) -> Int? {
        let t = text.replacingOccurrences(of: "转文字", with: "")
        guard t.range(of: #"^\D{0,3}?\d{1,2}\s*["”″“'’]\D{0,3}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Int(t.filter(\.isNumber))
    }

    public static func hasButton(_ text: String) -> Bool { text.contains("转文字") }

    /// "2•", "• 2" — a short number without the quote mark (only trusted next to a 转文字 button).
    public static func bareSeconds(in text: String) -> Int? {
        let t = text.replacingOccurrences(of: "转文字", with: "")
        guard t.range(of: #"^\D{0,3}?\d{1,2}\D{0,3}$"#, options: .regularExpression) != nil,
              TextMatch.normalize(t).allSatisfy(\.isNumber) else { return nil }
        return Int(t.filter(\.isNumber))
    }

    public static func label(_ seconds: Int) -> String { "[语音\(seconds)秒]" }
}

public struct Conversation {
    public let bubbles: [ChatBubble]
    /// Name of the open chat, read from the header bar ("" if not found).
    public let title: String

    public init(bubbles: [ChatBubble], title: String = "") {
        self.bubbles = bubbles
        self.title = title
    }

    /// Their messages after my last message. Empty when I spoke last.
    public var pendingIncoming: [ChatBubble] {
        Array(bubbles.reversed().prefix { !$0.fromMe }.reversed())
    }

    /// Stable identity of what is waiting for a reply.
    public var pendingKey: String {
        TextMatch.normalize(pendingIncoming.map(\.text).joined())
    }
}

public enum ChatParser {
    /// Turns OCR lines into left (them) / right (me) bubbles.
    /// `windowSize` is the window size in points; OCR boxes are normalized to the whole window.
    /// With `image`, a line on a green bubble is mine wherever it sits (long bubbles reach far left).
    public static func parse(_ lines: [OCRLine], windowSize: CGSize, layout: ChatLayout,
                             image: CGImage? = nil) -> Conversation {
        let w = windowSize.width, h = windowSize.height
        let paneLeft = layout.sidebarWidth
        let paneWidth = max(1, w - paneLeft)
        let pixels = image.map { PixelSampler($0, windowWidth: w) }

        struct Placed {
            let fromMe: Bool; let text: String; let top: CGFloat; let bottom: CGFloat
            let voice: Int?; let anchor: CGPoint
        }
        let title = lines
            .filter { l in
                let top = (1 - l.box.maxY) * h
                return l.box.minX * w >= paneLeft && top >= layout.titleBarHeight && top < layout.headerHeight
            }
            .sorted { $0.box.minX < $1.box.minX }
            .first?.text ?? ""

        // “转文字” buttons next to voice messages. Remember where they are (to click them and to
        // recognize the voice message beside them); they are not message text.
        let isButton = { (l: OCRLine) in TextMatch.normalize(l.text) == "转文字" }
        var buttons: [CGPoint] = lines.compactMap { l in
            guard isButton(l), l.box.minX * w >= paneLeft else { return nil }
            return CGPoint(x: l.box.midX * w, y: (1 - l.box.midY) * h)
        }

        let placed: [Placed] = lines.compactMap { line in
            guard !isButton(line) else { return nil }
            let left = line.box.minX * w, right = line.box.maxX * w
            let top = (1 - line.box.maxY) * h, bottom = (1 - line.box.minY) * h
            guard left >= paneLeft, top >= layout.headerHeight, bottom <= h - layout.inputHeight else { return nil }
            let relLeft = (left - paneLeft) / paneWidth
            let relRight = (right - paneLeft) / paneWidth
            let midY = (top + bottom) / 2
            // A voice message shows its length (5"). OCR may drop the quote mark ("2•"), so a short
            // number with a “转文字” button on its right counts too.
            let buttonBeside = buttons.contains { abs($0.y - midY) < 14 && $0.x > right }
            let voice = Voice.seconds(in: line.text) ?? (buttonBeside ? Voice.bareSeconds(in: line.text) : nil)
            let text = voice.map(Voice.label) ?? line.text
            if voice != nil, Voice.hasButton(line.text) {   // button read into the same line: right end
                buttons.append(CGPoint(x: right - 22, y: midY))
            }
            let anchor = CGPoint(x: (left + right) / 2, y: midY)
            let green = pixels?.isGreenBubble(left: left, right: right, top: top, bottom: bottom) ?? false
            if green || (relRight > 0.7 && relLeft >= 0.3) {
                return Placed(fromMe: true, text: text, top: top, bottom: bottom, voice: voice, anchor: anchor)
            }
            if relLeft < 0.3 {
                return Placed(fromMe: false, text: text, top: top, bottom: bottom, voice: voice, anchor: anchor)
            }
            if relRight > 0.7 {
                return Placed(fromMe: true, text: text, top: top, bottom: bottom, voice: voice, anchor: anchor)
            }
            return nil // centered text such as timestamps
        }
        .sorted { $0.top < $1.top }

        var bubbles: [ChatBubble] = []
        var bottoms: [CGFloat] = []
        var lastBottom: CGFloat = -1000
        for p in placed {
            let lineHeight = p.bottom - p.top
            // A voice message always starts its own bubble; its “转文字” text joins it.
            if let prev = bubbles.last, prev.fromMe == p.fromMe, p.voice == nil,
               p.top - lastBottom < lineHeight * (prev.voiceSeconds == nil ? 0.8 : 1.6) {
                bubbles[bubbles.count - 1] = ChatBubble(fromMe: prev.fromMe, text: prev.text + p.text, top: prev.top,
                                                        voiceSeconds: prev.voiceSeconds, anchor: prev.anchor)
                bottoms[bottoms.count - 1] = p.bottom
            } else {
                bubbles.append(ChatBubble(fromMe: p.fromMe, text: p.text, top: p.top, voiceSeconds: p.voice,
                                          anchor: p.anchor))
                bottoms.append(p.bottom)
            }
            lastBottom = p.bottom
        }
        for i in bubbles.indices where bubbles[i].voiceSeconds != nil {
            let a = bubbles[i].anchor
            bubbles[i].transcribeButton = buttons.first { abs($0.y - a.y) < 14 && $0.x > a.x }
        }
        guard let image else { return Conversation(bubbles: bubbles, title: title) }
        return Conversation(bubbles: addMedia(to: Array(zip(bubbles, bottoms)), lines: lines, windowSize: windowSize,
                                              layout: layout, image: image), title: title)
    }

    /// Puts pictures and stickers in among the text bubbles (by height) and marks messages WeChat
    /// shows with a red “!” as not sent.
    private static func addMedia(to placed: [(ChatBubble, CGFloat)], lines: [OCRLine], windowSize: CGSize,
                                 layout: ChatLayout, image: CGImage) -> [ChatBubble] {
        let w = windowSize.width, h = windowSize.height
        let textRects = lines.compactMap { l -> CGRect? in
            let r = CGRect(x: l.box.minX * w, y: (1 - l.box.maxY) * h, width: l.box.width * w, height: l.box.height * h)
            return r.minX >= layout.sidebarWidth && r.minY >= layout.headerHeight && r.maxY <= h - layout.inputHeight ? r : nil
        }
        let scan = MediaScan(image: image, windowSize: windowSize, layout: layout, textRects: textRects)
        var all = placed
        for b in scan.blocks {
            var bubble = ChatBubble(fromMe: b.fromMe, text: b.kind == .sticker ? "[表情]" : "[图片]", top: b.rect.minY,
                                    anchor: CGPoint(x: b.rect.midX, y: b.rect.midY), media: b.kind)
            bubble.frame = b.rect
            all.append((bubble, b.rect.maxY))
        }
        all.sort { $0.0.top < $1.0.top }
        for y in scan.failMarks {
            let mine = all.indices.filter { all[$0].0.fromMe && all[$0].0.top - 12 <= y && y <= all[$0].1 + 30 }
            if let i = mine.min(by: { abs(all[$0].1 - y) < abs(all[$1].1 - y) }) { all[i].0.failed = true }
        }
        return all.map(\.0)
    }
}

/// Reads bubble colors from a window screenshot.
struct PixelSampler {
    private let px: [UInt8]
    private let width: Int, height: Int
    private let scale: CGFloat

    init(_ image: CGImage, windowWidth: CGFloat) {
        width = image.width
        height = image.height
        scale = CGFloat(image.width) / max(1, windowWidth)
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        if let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        px = buf
    }

    /// True when the background behind a text line (window points, top-left) is WeChat's green.
    func isGreenBubble(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Bool {
        var r = 0, g = 0, b = 0, n = 0
        for i in 0..<12 {
            for j in 0..<3 {
                let x = Int((left + (right - left) * (CGFloat(i) + 0.5) / 12) * scale)
                let y = Int((top + (bottom - top) * (CGFloat(j) + 0.5) / 3) * scale)
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let k = (y * width + x) * 4
                let pr = Int(px[k]), pg = Int(px[k + 1]), pb = Int(px[k + 2])
                guard (pr + pg + pb) / 3 > 110 else { continue }   // skip the dark text itself
                r += pr; g += pg; b += pb; n += 1
            }
        }
        guard n >= 6 else { return false }
        r /= n; g /= n; b /= n
        return g - r > 30 && g - b > 40
    }
}

public enum TextMatch {
    /// Drops spaces and punctuation so small OCR differences don't matter.
    public static func normalize(_ s: String) -> String {
        String(s.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        })
    }

    /// True when `seen` (normalized text read off the screen) shows the reply `text`: its first or
    /// last six characters, or its whole first or last line when that line is shorter (a window
    /// of six would then reach into the next line, which the screen may show apart or not at all).
    public static func shows(_ seen: String, _ text: String) -> Bool {
        let n = normalize(text)
        guard !seen.isEmpty, n.count >= 2 else { return false }
        if n.count <= 6 { return seen.contains(n) }
        if seen.contains(String(n.prefix(6))) || seen.contains(String(n.suffix(6))) { return true }
        let lines = text.components(separatedBy: .newlines).map(normalize).filter { !$0.isEmpty }
        guard lines.count > 1, let first = lines.first, let last = lines.last else { return false }
        return (first.count >= 3 && seen.contains(first)) || (last.count >= 3 && seen.hasSuffix(last))
    }

    /// True when two normalized texts are the same message read twice by OCR.
    public static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return Double(prev[y.count]) / Double(max(x.count, y.count)) <= 0.15
    }
}
