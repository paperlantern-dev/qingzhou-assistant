import AppKit
import QingzhouCore

/// 读屏自检: the first reading after 开始 is checked. A wrong reading (the chat app was updated and
/// its layout moved) stops auto-reply and tells the owner, instead of answering the wrong chat.
extension AutoReplyController {
    private static let versionKey = "checkedAppVersion."

    /// true = go on. false = the reading is wrong and auto-reply was stopped.
    func checkScreenOnce(_ snap: Snapshot) -> Bool {
        guard !screenChecked else { return true }
        screenChecked = true
        let broken = CommandLine.arguments.contains("--break-reading")   // tests: as if the layout moved
        let facts = ScreenCheck.Facts(lines: windowText.count, listNames: broken ? 0 : snap.listNames.count,
                                      title: snap.conversation.title, bubbles: snap.conversation.bubbles.count,
                                      windowSize: snap.window.frame.size)
        let problems = ScreenCheck.problems(facts, layout: target.layout)
        let version = snap.window.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID) }?
            .bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        let key = Self.versionKey + target.id
        let update = ScreenCheck.update(lastChecked: UserDefaults.standard.string(forKey: key), now: version)
        guard problems.isEmpty else {
            let what = problems.joined(separator: "；")
            let why = update.map { "\(target.name)更新了（\($0)），界面可能变了。" } ?? ""
            stop()
            screenProblem = what
            add(.error, "读屏自检没通过，已停止自动回复：\(what)。\(why)")
            NSSound.beep()
            alertIfWanted(chat: "", who: "轻舟助手", message: "读屏自检没通过：\(what)", reason: "已停止自动回复，请看一下\(target.name)窗口")
            return false
        }
        add(.info, "读屏自检通过：读到 \(facts.listNames) 个聊天、当前会话 \(facts.bubbles) 条消息"
            + (version.map { " · \(target.name) \($0)" } ?? ""))
        if let update {
            updateNotice = "\(target.name)更新了（\(update)），读屏检查通过。头几条回复留意一下"
            add(.warn, updateNotice ?? "")
        }
        if let version, Self.saveSettings { UserDefaults.standard.set(version, forKey: key) }
        return true
    }

    /// 自己找分隔线: the contact list and the input box are read as wide and high as they are on
    /// screen now. Where no clear line is found, the measured size stays.
    func followDividers(_ image: CGImage, windowSize: CGSize) {
        guard target.supportsAutoReply else { return }
        let base = target.measured
        let found = LayoutFinder.find(in: image, windowSize: windowSize, base: base)
        let now = base.resized(sidebarWidth: found.sidebarWidth, inputHeight: found.inputHeight)
        guard now.sidebarWidth != target.layout.sidebarWidth || now.inputHeight != target.layout.inputHeight else { return }
        add(.info, "分隔线变了：聊天列表宽 \(Int(target.layout.sidebarWidth)) → \(Int(now.sidebarWidth))，"
            + "输入框高 \(Int(target.layout.inputHeight)) → \(Int(now.inputHeight))")
        target = target.with(layout: now)
    }
}
