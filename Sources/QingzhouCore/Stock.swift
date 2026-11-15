import Foundation

/// 有没有货: the shop stocks each thing in its best season, so what is on the price table is in
/// stock until the owner says it is sold out (and stays sold out until he says it is back).
public enum Stock {
    /// For the reply prompt.
    public static func note(soldOut: [String]) -> String {
        let base = "【有没有货】价格表上有的就是有货，客户问有没有，直接答有，不要说“我确认一下”。"
        guard !soldOut.isEmpty else { return base }
        return base + "下面这些卖完了：\(soldOut.joined(separator: "、"))。客户问到就直接说这一季卖完了、要等下一季，不要报价，也不要让他下单；可以说一样价格表上还有的同类货。"
    }

    public static func isSoldOut(_ item: Catalog.Item, _ soldOut: [String]) -> Bool { soldOut.contains(item.name) }

    public static func available(_ items: [Catalog.Item], soldOut: [String]) -> [Catalog.Item] {
        items.filter { !isSoldOut($0, soldOut) }
    }
}
