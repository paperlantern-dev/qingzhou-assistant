import CoreGraphics
import Foundation

/// Finds red unread badges in the contact list of a chat window screenshot.
/// Only looks in the avatar top-right band (so red in icons or avatar photos is ignored)
/// and only accepts round, solid blobs of WeChat's badge red.
public enum UnreadDetector {
    /// Vertical centers (window points from the top) of badges, top first.
    public static func badgeRows(in image: CGImage, windowSize: CGSize, layout: ChatLayout) -> [CGFloat] {
        let scale = CGFloat(image.width) / max(1, windowSize.width)
        let x0 = max(0, Int(layout.badgeMinX * scale))
        let x1 = min(image.width, Int(min(layout.badgeMaxX, layout.sidebarWidth) * scale))
        let width = image.width, height = image.height
        guard x1 > x0, height > 0 else { return [] }

        var px = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        func isBadgeRed(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
            // WeChat badge red is about (250, 81, 81).
            return r > 225 && abs(g - 81) < 32 && abs(b - 81) < 32
        }

        // Rows that contain badge-red pixels inside the band, grouped into blobs.
        var result: [CGFloat] = []
        var blob: (top: Int, minX: Int, maxX: Int, count: Int)?
        for y in Int(layout.listTop * scale)...height {
            var rowMin = Int.max, rowMax = -1, rowCount = 0
            if y < height {
                for x in x0..<x1 where isBadgeRed(x, y) {
                    rowMin = min(rowMin, x); rowMax = max(rowMax, x); rowCount += 1
                }
            }
            if rowCount > 0 {
                if let b = blob {
                    blob = (b.top, min(b.minX, rowMin), max(b.maxX, rowMax), b.count + rowCount)
                } else {
                    blob = (y, rowMin, rowMax, rowCount)
                }
            } else if let b = blob {
                let h = CGFloat(y - b.top) / scale, w = CGFloat(b.maxX - b.minX + 1) / scale
                let fill = CGFloat(b.count) / (CGFloat(y - b.top) * CGFloat(b.maxX - b.minX + 1))
                // A badge: 6–30 pt, roughly round (or a short pill for "99+"), mostly solid.
                let sticksOut = CGFloat(b.maxX) / scale >= layout.avatarRight + 3
                if sticksOut, h >= 6, h <= 30, w >= 6, w <= 40, w / h >= 0.7, w / h <= 2.4, fill >= 0.45 {
                    result.append(CGFloat(b.top + y) / 2 / scale)
                }
                blob = nil
            }
        }
        return result
    }
}

/// A contact row with a red unread badge, as read from the list on the left.
public struct UnreadRow: Equatable {
    public let y: CGFloat        // vertical center of the badge, window points from the top
    public let name: String      // first line: chat name
    public let preview: String   // second line: last message preview ("" if not read)

    public init(y: CGFloat, name: String, preview: String) {
        self.y = y
        self.name = name
        self.preview = preview
    }
}

public enum UnreadRowReader {
    /// For each badge, reads that row's name (first line) and preview (the line below).
    /// The time column on the right ("07:16", "2024/02/17") is left out.
    public static func rows(badges: [CGFloat], lines: [OCRLine], windowSize: CGSize, layout: ChatLayout) -> [UnreadRow] {
        badges.map { y in
            let inRow = lines.filter { l in
                let x = l.box.minX * windowSize.width, mid = (1 - l.box.midY) * windowSize.height
                return x >= layout.rowTextMinX && x < layout.sidebarWidth - 50
                    && mid > y - 15 && mid < y + 45 && !GroupChat.isTimeOrDate(l.text)
            }
            .sorted { $0.box.maxY > $1.box.maxY }
            let top = { (l: OCRLine) in (1 - l.box.maxY) * windowSize.height }
            // The name sits level with the badge (top line of the row). If it is not there,
            // the row was not read cleanly (e.g. the list was moving): return an empty name.
            guard let nameLine = inRow.first(where: { abs(top($0) - y) <= 14 }) else {
                return UnreadRow(y: y, name: "", preview: "")
            }
            let preview = inRow.first { top($0) > top(nameLine) + 8 }
            return UnreadRow(y: y, name: nameLine.text, preview: preview?.text ?? "")
        }
    }
}
