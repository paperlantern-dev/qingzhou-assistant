import AppKit
import QingzhouCore

/// 双击 Esc 暂停: two quick Esc presses, in any app, stop auto-reply.
extension AutoReplyController {
    /// Two Esc presses at most this far apart (seconds) are a double press.
    static let escDoublePress: TimeInterval = 0.5
    private static var escMonitors: [Any] = []
    private static var lastEscAt: TimeInterval?

    /// Listens for Esc while running, when the setting is on. Hearing it while another app is in
    /// front needs 辅助功能 permission; our own window is covered by a local monitor.
    func startEscWatcher() {
        guard options.escToStop, Self.escMonitors.isEmpty else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated { self?.escKeyDown(e) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated { self?.escKeyDown(e) }
            return e
        }
        Self.escMonitors = [global, local].compactMap { $0 }
        if !AutoSender.isTrusted { add(.warn, "没有辅助功能权限：双击 Esc 只在轻舟窗口里有用") }
    }

    func stopEscWatcher() {
        Self.escMonitors.forEach(NSEvent.removeMonitor)
        Self.escMonitors = []
        Self.lastEscAt = nil
    }

    /// “双击 Esc 暂停” was switched: start or stop listening right away.
    func escSettingChanged() {
        if isRunning, options.escToStop { startEscWatcher() } else { stopEscWatcher() }
    }

    private func escKeyDown(_ e: NSEvent) {
        guard e.keyCode == 53, !e.isARepeat, !Self.postedByUs(e) else { return }
        escPressed(at: e.timestamp)
    }

    /// One Esc press by the user (seconds since boot); the second within 0.5 s stops auto-reply.
    func escPressed(at timestamp: TimeInterval) {
        let reading = historyTask != nil
        guard isRunning || reading, options.escToStop else { return }
        guard let last = Self.lastEscAt, timestamp - last <= Self.escDoublePress else {
            Self.lastEscAt = timestamp
            return
        }
        if reading {   // 读以前的聊天
            stopHistory()
            stopEscWatcher()
            add(.info, "双击 Esc，停下读以前的聊天")
            return
        }
        stop()
        status = "双击 Esc，已暂停"
        add(.info, "双击 Esc，已暂停")
        note(.handedOver, who: "", title: "双击 Esc，已暂停", detail: "")
    }

    /// An Esc this app posted itself (AutoSender closes a context menu with Esc), not the user's.
    private static func postedByUs(_ e: NSEvent) -> Bool {
        e.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier)
    }
}
