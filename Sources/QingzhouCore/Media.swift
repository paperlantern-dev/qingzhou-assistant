import CoreGraphics
import Foundation

/// A message OCR can't read: a picture or a sticker (表情).
public enum MediaKind: Equatable {
    case picture, sticker
}

/// Looks at the message pane's pixels for what OCR misses: pictures and stickers (blocks that are
/// neither text bubbles nor avatars), and WeChat's red “!” next to a message that was not sent.
struct MediaScan {
    struct Block {
        let rect: CGRect      // window points, top-left origin
        let kind: MediaKind
        let fromMe: Bool
    }

    private(set) var blocks: [Block] = []
    /// Vertical centres (window points) of red “!” marks on my side.
    private(set) var failMarks: [CGFloat] = []

    private let cell: CGFloat = 3

    init(image: CGImage, windowSize: CGSize, layout: ChatLayout, textRects: [CGRect]) {
        let pane = CGRect(x: layout.sidebarWidth + 2, y: layout.headerHeight + 2,
                          width: windowSize.width - layout.sidebarWidth - 4,
                          height: windowSize.height - layout.headerHeight - layout.inputHeight - 4)
        guard pane.width > 60, pane.height > 60 else { return }
        let pixels = Pixels(image, windowWidth: windowSize.width)
        let cols = Int(pane.width / cell), rows = Int(pane.height / cell)
        let background = pixels.commonColor(in: pane)
        let masks = textRects.map { $0.insetBy(dx: -16, dy: -16) }
        var content = [Bool](repeating: false, count: cols * rows)
        var red = [Bool](repeating: false, count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let p = CGPoint(x: pane.minX + (CGFloat(c) + 0.5) * cell, y: pane.minY + (CGFloat(r) + 0.5) * cell)
                guard let rgb = pixels.color(at: p) else { continue }
                if rgb.r > 200, rgb.g < 120, rgb.b < 120 { red[r * cols + c] = true; continue }
                let diff = max(abs(rgb.r - background.r), abs(rgb.g - background.g), abs(rgb.b - background.b))
                if diff > 12, !masks.contains(where: { $0.contains(p) }) { content[r * cols + c] = true }
            }
        }
        let grid = Grid(cols: cols, rows: rows, origin: pane.origin, cell: cell)
        blocks = grid.components(content).compactMap { Self.block($0, pane: pane, textRects: textRects) }
        failMarks = grid.components(red).compactMap { comp in
            let rect = comp.rect
            guard (10...28).contains(rect.width), (10...28).contains(rect.height),
                  rect.midX > pane.midX, rect.maxX < pane.maxX - 60,
                  !blocks.contains(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(CGPoint(x: rect.midX, y: rect.midY)) })
            else { return nil }
            return rect.midY
        }
    }

    /// A picture or sticker, or nil for avatars, leftovers of text bubbles and small marks.
    private static func block(_ comp: Grid.Component, pane: CGRect, textRects: [CGRect]) -> Block? {
        let r = comp.rect
        let nearEdge = r.minX - pane.minX < 36 || pane.maxX - r.maxX < 36
        if nearEdge, (24...50).contains(r.width), (24...50).contains(r.height), abs(r.width - r.height) <= 10 {
            return nil   // an avatar
        }
        guard r.width >= 40, r.height >= 40, r.width < pane.width * 0.9 else { return nil }
        let fromMe = r.midX > pane.midX
        // Part of a text bubble (a voice message's tail, a long bubble's edge): it shares a line's height.
        let besideText = textRects.contains { t in
            (t.midX > pane.midX) == fromMe && t.minY <= r.midY && r.midY <= t.maxY
        }
        guard !besideText else { return nil }
        let sticker = comp.fill < 0.85 && max(r.width, r.height) <= 130
        return Block(rect: r, kind: sticker ? .sticker : .picture, fromMe: fromMe)
    }
}

/// Connected cells of a boolean grid laid over the window.
private struct Grid {
    struct Component {
        let rect: CGRect
        let fill: Double   // share of the bounding box that is set
    }

    let cols: Int, rows: Int
    let origin: CGPoint
    let cell: CGFloat

    func components(_ set: [Bool]) -> [Component] {
        var seen = [Bool](repeating: false, count: set.count)
        var out: [Component] = []
        for start in set.indices where set[start] && !seen[start] {
            var stack = [start], count = 0
            var minC = cols, maxC = 0, minR = rows, maxR = 0
            seen[start] = true
            while let i = stack.popLast() {
                count += 1
                let r = i / cols, c = i % cols
                minC = min(minC, c); maxC = max(maxC, c); minR = min(minR, r); maxR = max(maxR, r)
                for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                    let nr = r + dr, nc = c + dc
                    guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                    let j = nr * cols + nc
                    if set[j], !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            let w = maxC - minC + 1, h = maxR - minR + 1
            out.append(Component(rect: CGRect(x: origin.x + CGFloat(minC) * cell, y: origin.y + CGFloat(minR) * cell,
                                              width: CGFloat(w) * cell, height: CGFloat(h) * cell),
                                 fill: Double(count) / Double(w * h)))
        }
        return out
    }
}

/// Colours of a window screenshot, read in window points (top-left origin).
struct Pixels {
    struct RGB { let r: Int, g: Int, b: Int }
    private let px: [UInt8]
    let width: Int, height: Int
    let scale: CGFloat

    /// How far apart two neighbouring pixels are (0 = the same colour). Pixel coordinates.
    func step(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) -> Int {
        guard x1 >= 0, x2 >= 0, y1 >= 0, y2 >= 0, x1 < width, x2 < width, y1 < height, y2 < height else { return 0 }
        let a = (y1 * width + x1) * 4, b = (y2 * width + x2) * 4
        return abs(Int(px[a]) - Int(px[b])) + abs(Int(px[a + 1]) - Int(px[b + 1])) + abs(Int(px[a + 2]) - Int(px[b + 2]))
    }

    init(_ image: CGImage, windowWidth: CGFloat) {
        width = image.width
        height = image.height
        scale = CGFloat(image.width) / max(1, windowWidth)
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        if let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        px = buf
    }

    func color(at p: CGPoint) -> RGB? {
        let x = Int(p.x * scale), y = Int(p.y * scale)
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let k = (y * width + x) * 4
        return RGB(r: Int(px[k]), g: Int(px[k + 1]), b: Int(px[k + 2]))
    }

    /// The pane's background: its most common colour (rounded), sampled every 8 points.
    func commonColor(in rect: CGRect) -> RGB {
        var counts: [Int: Int] = [:]
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                if let c = color(at: CGPoint(x: x, y: y)) { counts[(c.r / 4) << 16 | (c.g / 4) << 8 | c.b / 4, default: 0] += 1 }
                x += 8
            }
            y += 8
        }
        let key = counts.max { $0.value < $1.value }?.key ?? 0
        return RGB(r: (key >> 16 & 0xFF) * 4 + 2, g: (key >> 8 & 0xFF) * 4 + 2, b: (key & 0xFF) * 4 + 2)
    }
}
