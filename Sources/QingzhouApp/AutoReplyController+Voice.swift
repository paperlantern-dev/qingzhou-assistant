import Foundation
import QingzhouCore

/// Voice messages: get their words with the chat app's own “转文字”.
extension AutoReplyController {
    /// Clicks “转文字” next to the voice bubble (or chooses it from the right-click menu), and waits
    /// for the words to appear.
    func transcribe(_ voice: ChatBubble, in snap: Snapshot) async -> Bool {
        guard let pid = snap.window.owningApplication?.processID,
              await waitForIdle(before: "转文字") else { return false }
        let f = snap.window.frame
        let point = CGPoint(x: f.minX + voice.anchor.x, y: f.minY + voice.anchor.y)
        // Then click the input box in the same visit, so the reply can be typed in the background.
        let input = CGPoint(x: f.minX + target.layout.sidebarWidth + (f.width - target.layout.sidebarWidth) / 2,
                            y: f.maxY - target.layout.inputClickFromBottom)
        do {
            if let b = voice.transcribeButton {   // WeChat 4.1: the button right next to the voice message
                try await AutoSender.click(CGPoint(x: f.minX + b.x, y: f.minY + b.y), inPID: pid, windowFrame: f,
                                           then: input)
            } else if try await !AutoSender.chooseFromContextMenu("转文字", at: point, inPID: pid, windowFrame: f,
                                                                    then: input) {
                add(.info, "右键菜单里没找到“转文字”")
                add(.debug, "菜单诊断：" + AutoSender.lastTrace)
                return false
            }
        } catch {
            add(.error, "转文字失败：\(error.localizedDescription)")
            return false
        }
        for _ in 0..<8 {   // the words can take a few seconds to come back
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let now = await read(forceOCR: true), now.conversation.pendingIncoming.last?.needsTranscript == false {
                return true
            }
        }
        return false
    }
}

/// WeChat showed a red “!” beside what we sent: it did not go out (blocked, deleted, offline…).
struct WeChatRefused: LocalizedError {
    var errorDescription: String? { "微信没发出去（红色感叹号）" }
}
