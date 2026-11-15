import Foundation

/// The full price list, written straight from the knowledge base's price table (csv), so nothing
/// is left out, no price is made up, and nothing goes to the cloud.
public enum Catalog {
    public struct Item: Equatable {
        public let name: String
        public let spec: String
        public let price: String
    }

    private static let nameColumns = ["品名", "商品", "名称", "产品", "品种"]
    private static let specColumns = ["规格"]
    private static let priceColumns = ["价格", "单价", "售价"]

    /// Rows of a price table. A table without a name and a price column gives nothing.
    public static func items(csv: String) -> [Item] {
        let rows = csv.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n").map(String.init)
        guard let header = rows.first.map(cells) else { return [] }
        func column(_ names: [String]) -> Int? { header.firstIndex { cell in names.contains { cell.contains($0) } } }
        guard let name = column(nameColumns), let price = column(priceColumns) else { return [] }
        let spec = column(specColumns)
        return rows.dropFirst().compactMap { row in
            let c = cells(row)
            func at(_ i: Int?) -> String { i.flatMap { $0 < c.count ? c[$0] : nil } ?? "" }
            guard !at(name).isEmpty, !at(price).isEmpty else { return nil }
            return Item(name: at(name), spec: at(spec), price: at(price))
        }
    }

    /// Every price table among the knowledge files (without what is sold out), or nil when there is none.
    public static func text(folder: URL, files: [String], soldOut: [String] = []) -> String? {
        let all = files.filter { $0.lowercased().hasSuffix(".csv") }.flatMap { file -> [Item] in
            guard let csv = KnowledgeBase.readText(folder.appendingPathComponent(file)) else { return [] }
            return items(csv: csv)
        }
        return text(Stock.available(all, soldOut: soldOut))
    }

    /// One line per item, gift boxes on their own, easy to read in a chat:
    ///
    ///     现在有这些：
    ///
    ///     · 特级红富士　5斤装一箱　280元/斤
    ///     …
    ///     【礼盒】
    ///     · 当季水果礼盒（家庭装）　368元/盒
    public static func text(_ items: [Item]) -> String? {
        guard !items.isEmpty else { return nil }
        func line(_ i: Item) -> String { "· " + [i.name, i.spec, i.price].filter { !$0.isEmpty }.joined(separator: "　") }
        let boxes = items.filter { $0.name.contains("礼盒") || $0.name.contains("提货卡") }
        let goods = items.filter { !boxes.contains($0) }
        var parts = ["现在有这些："]
        if !goods.isEmpty { parts.append(goods.map(line).joined(separator: "\n")) }
        if !boxes.isEmpty { parts.append("【礼盒】\n" + boxes.map(line).joined(separator: "\n")) }
        parts.append("要哪种直接说。")
        return parts.joined(separator: "\n\n")
    }

    private static func cells(_ row: String) -> [String] {
        row.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
