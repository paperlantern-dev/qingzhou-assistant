import Foundation

/// An app whose chat window the assistant watches and replies in.
public struct ChatTarget: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let tested: Bool
    public let layout: ChatLayout

    public static func == (a: ChatTarget, b: ChatTarget) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    public static let mockWeChat = ChatTarget(
        id: "mock", name: "模拟微信（测试）", bundleID: "com.qingzhou.mock-wechat", tested: true,
        layout: ChatLayout(sidebarWidth: 220, headerHeight: 86, inputHeight: 150, inputClickFromBottom: 112,
                           titleBarHeight: 28, listTop: 84, badgeMinX: 36, badgeMaxX: 66, rowTextMinX: 50, avatarRight: 48,
                           inputTextFromBottom: 88...125)
    )
    /// WeChat for Mac 4.1: icon bar 0–60, chat list 60–300, chat pane 300+.
    /// Measured on 4.1.15: header 0–52, input box 495–640 (text area on top, toolbar at the bottom).
    public static let weChat = ChatTarget(
        id: "wechat", name: "微信", bundleID: "com.tencent.xinWeChat", tested: true,
        layout: ChatLayout(sidebarWidth: 300, headerHeight: 52, inputHeight: 145, inputClickFromBottom: 105,
                           titleBarHeight: 0, listTop: 50, badgeMinX: 94, badgeMaxX: 128, rowTextMinX: 112, avatarRight: 108,
                           inputTextFromBottom: 45...140)
    )
    public static let all = [mockWeChat, weChat]

    /// The target for a picked window. Apps whose layout is not calibrated yet get a generic
    /// target that can be watched (screenshot, text) but is never auto-replied to.
    public static func forApp(bundleID: String, name: String) -> ChatTarget {
        if let known = all.first(where: { $0.bundleID == bundleID }) { return known }
        return ChatTarget(id: "app:" + bundleID, name: name.isEmpty ? bundleID : name, bundleID: bundleID,
                          tested: false, layout: weChat.layout)
    }

    /// The measured layout of this app, before any divider was dragged.
    public var measured: ChatLayout { Self.all.first { $0.id == id }?.layout ?? layout }

    /// The same app, read with `layout` (the dividers as they are on screen now).
    public func with(layout: ChatLayout) -> ChatTarget {
        ChatTarget(id: id, name: name, bundleID: bundleID, tested: tested, layout: layout)
    }

    /// Only calibrated apps may be auto-replied to (clicks and typing land in known places).
    public var supportsAutoReply: Bool { tested }
}
