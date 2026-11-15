import Foundation

/// 商品照片: the owner's own photos, one file per product (“芒果.jpg”, “春见 2.jpg”) in a folder
/// inside the knowledge folder. A customer who asks to see a product gets its photo after the reply.
public enum ProductPhotos {
    public static let folderName = "商品照片"

    public struct Photo: Equatable {
        public let product: String
        public let file: URL
    }

    /// “春见 2.jpg”, “春见-1.png”, “春见(3).jpg” → “春见”.
    public static func product(fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let cut = base.replacingOccurrences(of: #"[\s_\-（(]*\d+[)）]?\s*$"#, with: "", options: .regularExpression)
        return cut.trimmingCharacters(in: .whitespaces)
    }

    /// The pictures in `folder`, by file name. A missing folder has none.
    public static func list(folder: URL) -> [Photo] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.filter(PictureLibrary.isPicture)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                let name = product(fileName: url.lastPathComponent)
                return TextMatch.normalize(name).count >= 2 ? Photo(product: name, file: url) : nil
            }
    }

    /// They want to see it: “有图吗”, “发张照片”, “看看”, “长什么样”, “多大”. Not “我再看看”, and not a
    /// picture of their own (“[图片…]”).
    public static func asksToSee(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("["), !t.contains("再看"), !t.contains("看看再"), !t.contains("想想") else { return false }
        return ["图", "照片", "看看", "看下", "看一下", "看一眼", "什么样", "啥样", "长啥", "多大", "实拍"].contains { t.contains($0) }
    }

    /// The photo to send after the reply, or nil. `pending` are their unanswered messages; `earlier`
    /// the messages before, oldest first (“芒果有吗” … “发张图看看”). Sold-out products send nothing.
    public static func pick(pending: [String], earlier: [String] = [], photos: [Photo], soldOut: [String] = []) -> Photo? {
        guard pending.contains(where: asksToSee) else { return nil }
        let gone = soldOut.map(TextMatch.normalize).filter { !$0.isEmpty }
        let offered = photos.filter { p in
            let name = TextMatch.normalize(p.product)
            return !gone.contains { name.contains($0) || $0.contains(name) }
        }
        .sorted { $0.product.count > $1.product.count }   // “特级砂糖橘” before “砂糖橘”
        func named(in text: String) -> Photo? {
            let t = TextMatch.normalize(text)
            return offered.first { t.contains(TextMatch.normalize($0.product)) }
        }
        if let hit = pending.reversed().lazy.compactMap(named).first { return hit }
        return earlier.suffix(6).reversed().lazy.compactMap(named).first
    }

    /// Goes into the reply prompt when a photo will follow, so the reply doesn't say “没有图”.
    public static func promptNote(_ photo: Photo) -> String {
        "【照片】这条回复发出后，会自动发一张「\(photo.product)」的实拍照片给客户。回复里不要说没有图，也不要说“确认一下”，可以说“发你看下”。"
    }
}
