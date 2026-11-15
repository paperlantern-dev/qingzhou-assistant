import AppKit
import Testing
@testable import QingzhouCore

private let layout = ChatTarget.mockWeChat.layout
private let win = CGSize(width: 860, height: 640)

/// Draws a mock window at 2x: gray sidebar, optional red badges at the given row centers (points).
private func window(badgesAt rows: [CGFloat], badgeColor: NSColor = NSColor(red: 0.98, green: 0.32, blue: 0.32, alpha: 1)) -> CGImage {
    let scale: CGFloat = 2
    let ctx = CGContext(data: nil, width: Int(win.width * scale), height: Int(win.height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
    ctx.fill(CGRect(origin: .zero, size: win))
    ctx.setFillColor(NSColor(white: 0.91, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: 220, height: win.height))
    // An orange avatar and a green bubble must not count as badges.
    ctx.setFillColor(NSColor.orange.withAlphaComponent(0.45).cgColor)
    ctx.fill(CGRect(x: 12, y: win.height - 300, width: 36, height: 36))
    for y in rows { // CG origin is bottom-left; rows are measured from the top
        ctx.setFillColor(badgeColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: 40, y: win.height - y - 8, width: 16, height: 16))
    }
    return ctx.makeImage()!
}

@Test("Finds red unread badges in the contact list, top first")
func findsBadges() {
    let rows = UnreadDetector.badgeRows(in: window(badgesAt: [200, 330]), windowSize: win, layout: layout)
    #expect(rows.count == 2)
    #expect(abs(rows[0] - 200) < 3)
    #expect(abs(rows[1] - 330) < 3)
}

@Test("No badges means nothing to open")
func noBadges() {
    #expect(UnreadDetector.badgeRows(in: window(badgesAt: []), windowSize: win, layout: layout).isEmpty)
}

@Test("Red above the contact list (search area) is ignored")
func ignoresAboveList() {
    #expect(UnreadDetector.badgeRows(in: window(badgesAt: [40]), windowSize: win, layout: layout).isEmpty)
}

@Test("Reads the open chat's name from the header, not the window title")
func readsChatTitle() {
    func line(_ t: String, x: CGFloat, y: CGFloat) -> OCRLine {
        OCRLine(text: t, confidence: 1,
                box: CGRect(x: x / win.width, y: 1 - (y + 18) / win.height, width: 100 / win.width, height: 18 / win.height))
    }
    let conv = ChatParser.parse([
        line("模拟微信", x: 400, y: 5),        // window title bar
        line("客户·李先生", x: 240, y: 46),     // chat header
        line("满多少包邮", x: 290, y: 120),
    ], windowSize: win, layout: layout)
    #expect(conv.title == "客户·李先生")
    #expect(conv.pendingIncoming.map(\.text) == ["满多少包邮"])
}

@Test("Red inside an avatar photo (e.g. a flag) is not an unread badge")
func ignoresRedInsideAvatar() {
    // Mock avatars span x 12–48; this red blob stays inside, a real badge sticks out past 48.
    let scale: CGFloat = 2
    let ctx = CGContext(data: nil, width: Int(win.width * scale), height: Int(win.height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(NSColor(white: 0.91, alpha: 1).cgColor)
    ctx.fill(CGRect(origin: .zero, size: win))
    ctx.setFillColor(NSColor(red: 0.98, green: 0.32, blue: 0.32, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 32, y: win.height - 240, width: 14, height: 10))
    #expect(UnreadDetector.badgeRows(in: ctx.makeImage()!, windowSize: win, layout: layout).isEmpty)
}
