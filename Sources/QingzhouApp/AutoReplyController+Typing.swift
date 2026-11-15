import Foundation
import QingzhouCore

/// Typing a reply into the open chat in the background, and checking it landed.
extension AutoReplyController {
    /// True when the input box shows the reply: a long reply may show only its start or its end.
    static func inputShows(_ input: String, _ text: String) -> Bool {
        TextMatch.shows(TextMatch.normalize(input), text)
    }

    /// Types the reply into the open chat without touching mouse, keyboard or clipboard, checks it
    /// really landed in the input box, then presses Return. false = not sent (use the fallback).
    func sendInBackground(_ text: String, pid: pid_t, snapshot: Snapshot, chat: String) async -> Bool {
        guard snapshot.inputText.count < 2 else {
            add(.info, "输入框里已有内容，这条改用前台发送")
            return false
        }
        await AutoSender.typeInBackground(text, toPID: pid)
        // Give the app time to show it; look twice before deciding it did not arrive.
        try? await Task.sleep(nanoseconds: UInt64(400_000_000 + text.count * 8_000_000))   // looked at again below if not yet
        var typed = await read(forceOCR: true)
        if let t = typed, !Self.inputShows(t.inputText, text) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            typed = await read(forceOCR: true)
        }
        guard let typed else { return false }
        guard Self.inputShows(typed.inputText, text) else {
            if typed.inputText.count >= 2 {   // something landed but not what we expect: remove it
                await AutoSender.keyInBackground(51, toPID: pid, times: text.count + 2)
            }
            add(.info, "后台打字没有进到输入框，这条改用前台发送")
            return false
        }
        guard ChatID.same(typed.chat, chat) else {   // another chat was opened while typing: never press Return there
            await AutoSender.keyInBackground(51, toPID: pid, times: text.count + 2)
            add(.warn, "打字时当前会话换了，这条没有发出（已从输入框删掉）")
            return false
        }
        guard isRunning else {   // paused while typing: take the text back out instead of sending it
            await AutoSender.keyInBackground(51, toPID: pid, times: text.count + 2)
            add(.info, "已暂停，这条没有发出（已从输入框删掉）")
            return false
        }
        await AutoSender.keyInBackground(36, toPID: pid)   // Return
        return true
    }
}
