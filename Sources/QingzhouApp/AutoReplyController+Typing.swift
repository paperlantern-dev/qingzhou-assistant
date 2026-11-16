import Foundation
import QingzhouCore

/// Typing a reply into the open chat in the background, and checking it landed.
extension AutoReplyController {
    /// True when the input box shows the reply: a long reply may show only its start or its end.
    static func inputShows(_ input: String, _ text: String) -> Bool {
        TextMatch.shows(TextMatch.normalize(input), text)
    }

    /// How a background send ended.
    enum BackgroundSend { case sent, useForeground, calledOff }

    /// Test runs: seconds to wait right before the last look and Return (`--hold-before-send`), so a test can
    /// change the chat in that moment; and whether to pause the assistant during that wait (`--pause-in-hold`).
    static var holdBeforeSend: Double = 0
    static var pauseInHold = false

    /// Replies left in an input box because it was not safe to take them out (another chat was showing,
    /// or the box could not be read). Taken out when that chat is next open and still shows them.
    static var stranded: [(chat: String, text: String)] = []

    func holdForTest() async {
        guard Self.holdBeforeSend > 0 else { return }
        if Self.pauseInHold { stop() }
        try? await Task.sleep(nanoseconds: UInt64(Self.holdBeforeSend * 1e9))
    }

    /// Takes the assistant's reply back out of the input box, but only when this chat is still the one
    /// showing and the box shows that reply. Otherwise nothing is deleted: it could be another chat's
    /// box or the owner's own words. true = the box was cleared.
    @discardableResult
    func takeBack(_ text: String, chat: String, pid: pid_t, seen: Snapshot?) async -> Bool {
        guard let seen, ChatID.same(seen.chat, chat), SendCheck.isAssistantText(input: seen.inputText, reply: text) else {
            if seen.map({ !PictureCheck.inputLooksEmpty($0.inputText) || !ChatID.same($0.chat, chat) }) ?? true {
                Self.stranded.append((chat, text))
                add(.warn, "输入框里的字没有动（看不清，或者已经不是这个会话），回到这个会话时再清")
            }
            return false
        }
        await AutoSender.keyInBackground(51, toPID: pid, times: text.count + 2)
        return true
    }

    /// This chat is open again and its input box still shows a reply left there earlier: take it out.
    /// Returns the screen as it is afterwards.
    func clearStranded(in snap: Snapshot, pid: pid_t) async -> Snapshot {
        guard let i = Self.stranded.firstIndex(where: { ChatID.same($0.chat, snap.chat) }) else { return snap }
        let text = Self.stranded.remove(at: i).text
        guard SendCheck.isAssistantText(input: snap.inputText, reply: text) else { return snap }
        await AutoSender.keyInBackground(51, toPID: pid, times: text.count + 2)
        add(.info, "把之前留在输入框里的回复清掉了")
        try? await Task.sleep(nanoseconds: 400_000_000)
        return await read(forceOCR: true) ?? snap
    }

    /// Types the reply into the open chat without touching mouse, keyboard or clipboard. Right before
    /// Return it looks once more: same chat, no newer message, the box shows this reply, still running.
    func sendInBackground(_ text: String, pid: pid_t, snapshot: Snapshot, chat: String) async -> BackgroundSend {
        guard PictureCheck.inputLooksEmpty(snapshot.inputText) else {
            add(.info, "输入框里已有内容，这条改用前台发送")
            return .useForeground
        }
        await AutoSender.typeInBackground(text, toPID: pid)
        // Give the app time to show it; look twice before deciding it did not arrive.
        try? await Task.sleep(nanoseconds: UInt64(400_000_000 + text.count * 8_000_000))
        var typed = await read(forceOCR: true)
        if let t = typed, !Self.inputShows(t.inputText, text) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            typed = await read(forceOCR: true)
        }
        if Self.holdBeforeSend > 0 {
            await holdForTest()
            typed = await read(forceOCR: true)
        }
        // The last look. Everything below happens without waiting, up to Return.
        guard let typed else {
            add(.warn, "按发送前没能看清聊天窗口，这条先不发")
            Self.stranded.append((chat, text))
            return .calledOff
        }
        if let why = SendCheck.problem(chat: chat, pendingKey: snapshot.conversation.pendingKey, nowChat: typed.chat,
                                       nowPendingKey: typed.conversation.pendingKey, nowInput: "") {
            await takeBack(text, chat: chat, pid: pid, seen: typed)
            add(.warn, "按发送前又看了一眼：\(why)，这条没有发出")
            return .calledOff
        }
        guard Self.inputShows(typed.inputText, text) else {
            if PictureCheck.inputLooksEmpty(typed.inputText) {
                add(.info, "后台打字没有进到输入框，这条改用前台发送")
                return .useForeground
            }
            if await takeBack(text, chat: chat, pid: pid, seen: typed) {   // typed half-way
                add(.info, "后台打字没有打完整，这条改用前台发送")
                return .useForeground
            }
            add(.warn, "输入框里有不是我打的字，这条没有发出")
            return .calledOff
        }
        guard isRunning else {   // paused while typing: take the text back out instead of sending it
            await takeBack(text, chat: chat, pid: pid, seen: typed)
            add(.info, "已暂停，这条没有发出（已从输入框删掉）")
            return .calledOff
        }
        await AutoSender.keyInBackground(36, toPID: pid)   // Return
        return .sent
    }
}
