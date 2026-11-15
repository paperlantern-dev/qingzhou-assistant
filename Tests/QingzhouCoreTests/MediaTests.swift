import AppKit
import Foundation
import Testing
@testable import QingzhouCore

/// The mock chat (`--demo-media`): her photo, her question, my picture that failed (red “!”), her sticker.
private func demoChat() throws -> Conversation {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("test-fixtures/screens/mock-media.png")
    let image = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let size = CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
    let ocr = try OCRService.recognize(image)
    return ChatParser.parse(ocr.lines, windowSize: size, layout: ChatTarget.mockWeChat.layout, image: image)
}

@Test("A customer's photo shows up as a picture message, in its place")
func mediaFindsTheirPhoto() throws {
    let bubbles = try demoChat().bubbles
    let photo = try #require(bubbles.firstIndex { !$0.fromMe && $0.media == .picture })
    let question = try #require(bubbles.firstIndex { $0.text.contains("多少钱") })
    #expect(photo < question)
    #expect(bubbles[photo].text == "[图片]")
}

@Test("A sticker is told apart from a photo, and the newest message is her sticker")
func mediaFindsSticker() throws {
    let conv = try demoChat()
    let last = try #require(conv.bubbles.last)
    #expect(!last.fromMe && last.media == .sticker && last.text == "[表情]")
    #expect(conv.pendingIncoming.map(\.text) == ["[表情]"])
}

@Test("My message with WeChat's red “!” is marked as not sent")
func mediaFindsFailedSend() throws {
    let bubbles = try demoChat().bubbles
    let question = try #require(bubbles.firstIndex { $0.text.contains("多少钱") })
    let failed = bubbles.enumerated().filter { $0.element.fromMe && $0.element.failed }.map(\.offset)
    #expect(!failed.isEmpty)
    #expect(failed.allSatisfy { $0 > question })
    #expect(!bubbles.contains { $0.text.contains("在的") && $0.failed })
}

@Test("Avatars and plain text bubbles are not taken for pictures")
func mediaIgnoresAvatars() throws {
    let bubbles = try demoChat().bubbles
    #expect(bubbles.filter { $0.media != nil && !$0.fromMe }.count == 2)   // her photo and her sticker
    #expect(bubbles.contains { $0.text.contains("在的") && $0.media == nil })
}
