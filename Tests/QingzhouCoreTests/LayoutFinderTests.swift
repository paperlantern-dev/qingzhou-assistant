import CoreGraphics
import Foundation
import Testing
@testable import QingzhouCore

/// A chat window drawn at 2×: a list on the left, a chat pane with bubbles, an input box below a hairline.
private func window(size: CGSize = CGSize(width: 1000, height: 700), sidebar: CGFloat, input: CGFloat,
                    sameBackground: Bool = false, extraLine: CGFloat? = nil) throws -> CGImage {
    let scale: CGFloat = 2
    let w = Int(size.width * scale), h = Int(size.height * scale)
    let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.scaleBy(x: scale, y: scale)
    func fill(_ gray: CGFloat, _ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        ctx.setFillColor(gray: gray, alpha: 1)
        ctx.fill(CGRect(x: x, y: size.height - top - height, width: width, height: height))   // top-left origin
    }
    fill(0.93, 0, 0, size.width, size.height)                                  // chat pane
    fill(sameBackground ? 0.93 : 0.97, 0, 0, sidebar, size.height)             // contact list
    fill(0.85, sidebar, 0, 1, size.height)                                     // divider
    fill(0.80, 10, 100, 40, 40)                                                // an avatar
    fill(1.0, sidebar + 60, 120, 300, 40)                                      // their bubble
    fill(0.6, size.width - 360, 200, 300, 40)                                  // my bubble
    fill(0.85, sidebar + 1, size.height - input, size.width - sidebar - 1, 1)  // line above the input box
    if let extraLine { fill(0.85, extraLine, 0, 1, size.height) }
    return try #require(ctx.makeImage())
}

private let base = ChatTarget.weChat.layout   // list 300 wide, input box 145 high
private let size = CGSize(width: 1000, height: 700)

@Test("The dividers are found where they are, dragged or not", arguments: [
    (CGFloat(300), CGFloat(145)), (380, 145), (240, 220), (300, 300), (420, 110),
])
func findsDividers(sidebar: CGFloat, input: CGFloat) throws {
    let found = LayoutFinder.find(in: try window(sidebar: sidebar, input: input), windowSize: size, base: base)
    #expect(abs((found.sidebarWidth ?? 0) - sidebar) <= 1)
    #expect(abs((found.inputHeight ?? 0) - input) <= 1)
}

@Test("A hairline is enough when list and chat have the same background")
func findsHairline() throws {
    let found = LayoutFinder.find(in: try window(sidebar: 350, input: 180, sameBackground: true), windowSize: size, base: base)
    #expect(abs((found.sidebarWidth ?? 0) - 350) <= 1 && abs((found.inputHeight ?? 0) - 180) <= 1)
}

@Test("No clear line, or two of them: nothing is guessed and the measured layout stays")
func keepsMeasuredWhenUnsure() throws {
    let w = 2000, h = 1400
    let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(gray: 0.9, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let blank = try #require(ctx.makeImage())
    #expect(LayoutFinder.find(in: blank, windowSize: size, base: base) == LayoutFinder.Found())
    let two = try window(sidebar: 300, input: 145, extraLine: 450)
    #expect(LayoutFinder.find(in: two, windowSize: size, base: base).sidebarWidth == nil)
    let kept = LayoutFinder.layout(for: blank, windowSize: size, base: base)
    #expect(kept.sidebarWidth == base.sidebarWidth && kept.inputHeight == base.inputHeight)
}

@Test("A taller input box moves where typed text is looked for; the click stays inside it")
func resizedLayout() {
    let tall = base.resized(sidebarWidth: 380, inputHeight: 245)
    #expect(tall.sidebarWidth == 380 && tall.inputHeight == 245)
    #expect(tall.inputTextFromBottom == base.inputTextFromBottom.lowerBound...(base.inputTextFromBottom.upperBound + 100))
    #expect(tall.inputClickFromBottom == base.inputClickFromBottom && tall.rowTextMinX == base.rowTextMinX)
    #expect(base.resized(sidebarWidth: nil, inputHeight: 110).inputClickFromBottom == 90)
}
