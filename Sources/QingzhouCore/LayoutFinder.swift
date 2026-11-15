import CoreGraphics
import Foundation

/// 自己找分隔线: where the contact list ends and where the input box starts, read from the
/// screenshot. The user can drag both dividers, so the measured numbers are only where to look first.
public enum LayoutFinder {
    public struct Found: Equatable {
        public var sidebarWidth: CGFloat?
        public var inputHeight: CGFloat?
        public init(sidebarWidth: CGFloat? = nil, inputHeight: CGFloat? = nil) {
            self.sidebarWidth = sidebarWidth
            self.inputHeight = inputHeight
        }
    }

    /// A divider runs along most of the window: this share of the sampled points must lie on an edge.
    static let sidebarShare = 0.6, inputShare = 0.85
    /// Colours this far apart (r+g+b) count as an edge; screenshots of flat backgrounds have none.
    static let edge = 5

    /// The dividers found in `image`. A value is nil when no clear line is there (then the measured
    /// layout is used): better the known place than a guess.
    public static func find(in image: CGImage, windowSize: CGSize, base: ChatLayout) -> Found {
        guard windowSize.width > 0, windowSize.height > 0 else { return Found() }
        let px = Pixels(image, windowWidth: windowSize.width)
        let sidebar = sidebarWidth(px, windowSize: windowSize, base: base)
        let input = inputHeight(px, windowSize: windowSize, base: base, sidebar: sidebar ?? base.sidebarWidth)
        return Found(sidebarWidth: sidebar, inputHeight: input)
    }

    /// The layout to read this screenshot with.
    public static func layout(for image: CGImage, windowSize: CGSize, base: ChatLayout) -> ChatLayout {
        let found = find(in: image, windowSize: windowSize, base: base)
        return base.resized(sidebarWidth: found.sidebarWidth, inputHeight: found.inputHeight)
    }

    /// The column where the list ends: an edge from below the header to the bottom. Only when
    /// exactly one such line is there.
    private static func sidebarWidth(_ px: Pixels, windowSize: CGSize, base: ChatLayout) -> CGFloat? {
        let s = px.scale
        let rows = stride(from: Int((base.headerHeight + 10) * s), to: Int((windowSize.height - 10) * s), by: max(1, Int(3 * s)))
        let from = Int(base.sidebarWidth * 0.6 * s), to = Int(min(base.sidebarWidth * 2, windowSize.width - 300) * s)
        guard rows.underestimatedCount >= 20, from < to else { return nil }
        let need = Int(Double(rows.underestimatedCount) * sidebarShare)
        let hits = (from...to).filter { c in rows.reduce(0) { $0 + (px.step(c - 1, $1, c, $1) >= edge ? 1 : 0) } >= need }
        guard let line = oneLine(hits, within: Int(4 * s)) else { return nil }
        return (CGFloat(line) / s).rounded()
    }

    /// The row where the input box starts: an edge across the chat pane, in the lower part of the
    /// window. With several, the one nearest to the measured place.
    private static func inputHeight(_ px: Pixels, windowSize: CGSize, base: ChatLayout, sidebar: CGFloat) -> CGFloat? {
        let s = px.scale
        let cols = stride(from: Int((sidebar + 12) * s), to: Int((windowSize.width - 12) * s), by: max(1, Int(3 * s)))
        let top = windowSize.height - min(base.inputHeight * 3, windowSize.height * 0.6)
        let from = Int(top * s), to = Int((windowSize.height - 60) * s)
        guard cols.underestimatedCount >= 20, from < to else { return nil }
        let need = Int(Double(cols.underestimatedCount) * inputShare)
        let hits = (from...to).filter { r in cols.reduce(0) { $0 + (px.step($1, r - 1, $1, r) >= edge ? 1 : 0) } >= need }
        let expected = Int((windowSize.height - base.inputHeight) * s)
        guard let line = hits.min(by: { abs($0 - expected) < abs($1 - expected) }) else { return nil }
        return (windowSize.height - CGFloat(line) / s).rounded()
    }

    /// The first of the hit columns when they all belong to one line (a hairline has two edges).
    static func oneLine(_ hits: [Int], within: Int) -> Int? {
        guard let first = hits.first, let last = hits.last, last - first <= within else { return nil }
        return first
    }
}
