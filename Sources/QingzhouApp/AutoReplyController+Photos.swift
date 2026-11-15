import AppKit
import QingzhouCore

/// 商品照片: a customer who asks to see a product gets the owner's own photo of it after the reply.
extension AutoReplyController {
    /// 知识库文件夹/商品照片: one picture per product, named after it (“芒果.jpg”, “春见 2.jpg”).
    var photoFolder: URL { kbFolder.appendingPathComponent(ProductPhotos.folderName, isDirectory: true) }

    var productPhotos: [ProductPhotos.Photo] { ProductPhotos.list(folder: photoFolder) }

    /// “打开照片文件夹”: made on first use, so the owner has somewhere to drop the pictures.
    func openPhotoFolder() {
        do {
            try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(photoFolder)
        } catch {
            add(.error, "照片文件夹没建成：\(error.localizedDescription)")
        }
    }

    /// The photo to send after this reply, or nil: they asked to see a product there is a photo of,
    /// and it has not gone to them today.
    func productPhoto(for snap: Snapshot) -> ProductPhotos.Photo? {
        let conv = snap.conversation
        let pending = conv.pendingIncoming.map(\.text)
        let earlier = conv.bubbles.dropLast(pending.count).map(\.text)
        guard let photo = ProductPhotos.pick(pending: pending, earlier: Array(earlier), photos: productPhotos,
                                             soldOut: options.soldOut) else { return nil }
        if let sent = photoSent[photoKey(photo, chat: snap.chat)], Calendar.current.isDateInToday(sent) { return nil }
        return photo
    }

    private func photoKey(_ photo: ProductPhotos.Photo, chat: String) -> String { chat + "|" + photo.file.lastPathComponent }

    /// Sends it a moment after the reply, unless they wrote again or the limit is reached. It is
    /// tried once: a picture that may have gone out is never pasted again.
    func sendProductPhoto(_ photo: ProductPhotos.Photo, chat: String, who: String) async {
        let name = photo.file.lastPathComponent
        if let why = limiter.blockReason(chat: chat) {
            add(.info, "【\(who)】「\(photo.product)」的照片先不发：\(why)")
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 1.5...3) * 1_000_000_000))
        guard isRunning, let now = await read(forceOCR: true), ChatID.same(now.chat, chat),
              now.conversation.pendingIncoming.isEmpty else {
            add(.info, "【\(who)】对方又发了消息或换了会话，「\(photo.product)」的照片先不发")
            return
        }
        photoSent[photoKey(photo, chat: chat)] = Date()
        do {
            step("发照片", name)
            guard let method = try await deliverImage(photo.file, in: now, chat: chat) else {
                add(.warn, "【\(who)】「\(photo.product)」的照片没有确认发出，不再重发")
                return
            }
            limiter.record(chat: chat)
            sentCount += 1
            add(.sent, "【\(who)】我：[图片] \(name)\n商品照片 · \(method) · 已在窗口中确认")
            note(.replied, who: who, title: "发了照片", detail: "「\(photo.product)」\(name)")
        } catch {
            refreshPermissions()
            add(.warn, "【\(who)】「\(photo.product)」的照片没发出去：\(error.localizedDescription)")
        }
    }
}
