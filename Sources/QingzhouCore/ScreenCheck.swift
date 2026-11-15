import CoreGraphics
import Foundation

/// 读屏自检: before replying, make sure the chat window still reads the way it should. After a
/// WeChat update the layout may move, and a wrong reading must stop auto-reply, not answer wrongly.
public enum ScreenCheck {
    public struct Facts: Equatable {
        public var lines: Int          // lines of text read in the window
        public var listNames: Int      // contact rows read in the list on the left
        public var title: String       // whose chat is open ("" when none)
        public var bubbles: Int        // messages read in the open chat
        public var windowSize: CGSize

        public init(lines: Int, listNames: Int, title: String, bubbles: Int, windowSize: CGSize) {
            self.lines = lines
            self.listNames = listNames
            self.title = title
            self.bubbles = bubbles
            self.windowSize = windowSize
        }
    }

    /// What is wrong with the reading, in the owner's words. Empty = it reads fine.
    public static func problems(_ f: Facts, layout: ChatLayout) -> [String] {
        if f.windowSize.width < layout.sidebarWidth + 300 || f.windowSize.height < layout.headerHeight + layout.inputHeight + 150 {
            return ["窗口太小，聊天内容显示不全，把它拉大一点"]
        }
        if f.lines == 0 { return ["窗口里一个字都没读到"] }
        var found: [String] = []
        if f.listNames == 0 { found.append("左边的聊天列表没读到") }
        if f.bubbles > 0, f.title.trimmingCharacters(in: .whitespaces).isEmpty { found.append("读到了聊天内容，但没读到是谁的聊天") }
        return found
    }

    /// “4.1.15 → 4.2.0” when the chat app was updated since the last good check; nil when it is the
    /// same, or seen for the first time.
    public static func update(lastChecked: String?, now: String?) -> String? {
        guard let old = lastChecked, let new = now, !old.isEmpty, !new.isEmpty, old != new else { return nil }
        return "\(old) → \(new)"
    }
}
