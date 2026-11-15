import CoreGraphics
import Foundation
import QingzhouCore

/// 看图: the customer's new pictures and stickers, looked at before the AI replies.
struct PicturePrep {
    /// The chat with each new picture replaced by what was seen (“[图片1：见附图1；本机看到：fruit]”).
    let conversation: Conversation
    /// Pictures the model may look at (temporary files; never ones with an address or phone in them).
    let files: [URL]
    /// They only sent stickers: nothing to answer.
    let stickersOnly: Bool
}

extension AutoReplyController {
    /// Cuts out each new picture, reads it on this Mac, and decides whether the model may see it.
    func preparePictures(_ snap: Snapshot) async -> PicturePrep {
        let conv = snap.conversation
        let pending = conv.pendingIncoming
        let stickersOnly = !pending.isEmpty && pending.allSatisfy { $0.media == .sticker }
        var bubbles = conv.bubbles
        var files: [URL] = []
        var number = 0
        let scale = CGFloat(snap.image.width) / max(1, snap.window.frame.width)
        for i in (bubbles.count - pending.count)..<bubbles.count where bubbles[i].media == .picture {
            guard let frame = bubbles[i].frame,
                  let crop = snap.image.cropping(to: CGRect(x: frame.minX * scale, y: frame.minY * scale,
                                                            width: frame.width * scale, height: frame.height * scale))
            else { continue }
            number += 1
            let info = await Task.detached { PictureReader.read(crop) }.value
            var attached = false
            if options.picturesToModel, info.mayGoToCloud, let png = WindowCapture.pngData(crop) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("qingzhou-pic-\(UUID().uuidString).png")
                do {
                    try png.write(to: url)
                    files.append(url)
                    attached = true
                } catch {
                    add(.warn, "图片没能存成临时文件：\(error.localizedDescription)")
                }
            }
            let note = info.note(number: number, attached: attached)
            add(.info, "看图：\(note)")
            step("看图", note)
            var seen = ChatBubble(fromMe: false, text: note, top: bubbles[i].top, anchor: bubbles[i].anchor, media: .picture)
            seen.frame = frame
            bubbles[i] = seen
        }
        return PicturePrep(conversation: Conversation(bubbles: bubbles, title: conv.title), files: files,
                           stickersOnly: stickersOnly)
    }

    func removePictureFiles(_ files: [URL]) {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
