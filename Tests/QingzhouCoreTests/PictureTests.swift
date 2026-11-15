import AppKit
import Foundation
import Testing
@testable import QingzhouCore

private func fixture(_ name: String) throws -> CGImage {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("test-fixtures/images/\(name)")
    return try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
}

@Test("A picture with an address and a phone number is read on this Mac and kept off the cloud")
func pictureWithAddressStaysLocal() throws {
    let info = PictureReader.read(try fixture("address.png"))
    #expect(info.hasPrivateText)
    #expect(!info.mayGoToCloud)
    #expect(!info.text.contains("13600001111") && !info.text.contains("示例路"))
    #expect(info.text.contains(Privacy.phone))
}

@Test("A product photo without private text may be shown to the model")
func productPhotoMayGoToCloud() throws {
    let info = PictureReader.read(try fixture("product.png"))
    #expect(!info.hasPrivateText)
    #expect(info.mayGoToCloud)
}

@Test("The note for the prompt says what was seen, in a few words")
func pictureNote() {
    let info = PictureInfo(text: "红富士 2斤", labels: ["fruit", "apple"], hasPrivateText: false)
    let note = info.note(number: 1, attached: true)
    #expect(note.hasPrefix("[图片1"))
    #expect(note.contains("附图1") && note.contains("红富士 2斤") && note.contains("fruit"))
    #expect(!PictureInfo(text: "", labels: [], hasPrivateText: true).note(number: 2, attached: false).contains("附图"))
}

@Test("A picture this Mac could not read is never sent to the cloud")
func unreadPictureStaysHere() {
    let unread = PictureInfo(text: "", labels: ["document"], hasPrivateText: false, readFailed: true)
    #expect(!unread.mayGoToCloud)
    #expect(unread.note(number: 1, attached: false).contains("没读清"))
    #expect(PictureInfo(text: "红富士", labels: [], hasPrivateText: false).mayGoToCloud)
}
