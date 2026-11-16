import AppKit
import QingzhouCore
import UniformTypeIdentifiers

/// Sending pictures: a foreground paste, checked on screen (OCR can't read pictures).
extension AutoReplyController {
    /// Keeps a copy of a picture the owner picked in ~/Library/Application Support/轻舟助手/图片
    /// (same name, numbered if taken), so saved rules and messages keep working. Returns the copy.
    static func importPicture(_ url: URL) throws -> URL {
        try PictureLibrary.importPicture(url)
    }

    /// “选图片…”: the owner picks a picture, and a copy is kept in the app's folder. nil = cancelled.
    static func choosePicture() throws -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = PictureLibrary.fileTypes.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "用这张图片"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try importPicture(url)
    }

    /// Sends a picture into the open chat and checks it arrived. Returns how it was sent, or nil when it
    /// was not sent (other chat open, text in the input box, the user kept working) or not confirmed.
    /// Throws for a missing or unreadable picture and for send errors. Callers record the limiter.
    func deliverImage(_ file: URL, in snap: Snapshot, chat: String) async throws -> String? {
        let name = file.lastPathComponent
        guard PictureLibrary.isPicture(file) else { throw PictureError.notAPicture(name) }
        guard FileManager.default.fileExists(atPath: file.path) else { throw PictureError.missing(name) }
        guard snap.window.owningApplication?.processID != nil else { throw SendError.appNotRunning }
        if backgroundMode { guard await waitForIdle(before: "发图片") else { return nil } }
        // Look again right before pasting: the chat may have changed while waiting.
        guard let now = await read(forceOCR: true) else {
            add(.warn, "发图片前没能看清聊天窗口，先不发")
            return nil
        }
        guard isRunning else { return nil }
        guard ChatID.same(now.chat, chat), let pid = now.window.owningApplication?.processID else {
            add(.warn, "要发图片时，当前会话已不是「\(snap.conversation.title)」，先不发")
            return nil
        }
        let key = snap.conversation.pendingKey
        if let why = SendCheck.problem(chat: chat, pendingKey: key, nowChat: now.chat,
                                       nowPendingKey: now.conversation.pendingKey, nowInput: "") {
            add(.warn, "要发图片时又看了一眼：\(why)，先不发")
            return nil
        }
        guard PictureCheck.inputLooksEmpty(now.inputText) else {
            add(.warn, "输入框里有字，先不发图片（免得把字一起发出去）")
            return nil
        }
        let f = now.window.frame
        let point = CGPoint(x: f.minX + target.layout.sidebarWidth + (f.width - target.layout.sidebarWidth) / 2,
                            y: f.maxY - target.layout.inputClickFromBottom)
        let before = PictureCheck.paneFingerprint(now.image, windowSize: f.size, layout: target.layout)
        add(.debug, "发图片 \(name)：窗口 \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height))，点击输入框 \(Int(point.x)),\(Int(point.y))")
        // Pasted, not yet sent: one more look, then Return. (A picture in the box can't be read, so the box
        // is left as it is when the send is called off.)
        let pressed = try await AutoSender.sendImage(file, toPID: pid, windowFrame: f, clickPoint: point) { [self] in
            await holdForTest()
            let pasted = await read(forceOCR: true)
            let why = pasted == nil ? "没能看清聊天窗口" : !isRunning ? "已暂停"
                : SendCheck.problem(chat: chat, pendingKey: key, nowChat: pasted!.chat,
                                    nowPendingKey: pasted!.conversation.pendingKey, nowInput: "")
            guard let why else { return true }
            add(.warn, "按发送前又看了一眼：\(why)，图片没有发出（还在输入框里，请你看一下）")
            return false
        }
        guard pressed else { return nil }
        lastSendAt = Date()   // the minimum gap between sends counts pictures too
        add(.debug, "发送时：" + AutoSender.lastTrace)
        return await pictureArrived(name, before: before, in: now, chat: chat) ? "前台粘贴图片" : nil
    }

    /// The pane changed and nothing else explains it. Looks twice: a picture can take a moment to show.
    private func pictureArrived(_ name: String, before: [UInt8], in snap: Snapshot, chat: String) async -> Bool {
        for wait: UInt64 in [900_000_000, 1_500_000_000] {
            try? await Task.sleep(nanoseconds: wait)
            guard let after = await read(forceOCR: true) else { continue }
            guard ChatID.same(after.chat, chat), after.window.frame.size == snap.window.frame.size else {
                add(.warn, "发图片后窗口变了（换了会话或改了大小），没法确认图片发出")
                return false
            }
            if let last = after.conversation.bubbles.last, last.fromMe, last.failed {   // WeChat's red “!”
                add(.warn, "图片旁边是红色感叹号：微信没发出去")
                return false
            }
            if let last = after.conversation.bubbles.last, last.fromMe, last.media != nil, after.inputText.count < 2 {
                return true   // my picture is now the newest message
            }
            let pane = PictureCheck.paneFingerprint(after.image, windowSize: after.window.frame.size, layout: target.layout)
            if PictureCheck.confirmed(before: snap.conversation, after: after.conversation,
                                      paneChanged: PictureCheck.changed(before, pane),
                                      inputText: after.inputText, fileName: name) {
                return true
            }
        }
        return false
    }
}
