import Foundation
import Testing
@testable import QingzhouCore

private let table = """
品名,规格,价格,说明
特级红富士,10斤装一箱,560元/斤,当季特级，数量少
当季脐橙,中果,60元/斤,家常吃
小番茄,,68元/斤,生吃
空价格,一条,,不该出现
特级红富士礼盒,2箱装,598元/盒,含礼品包装
"""

@Test("The price list has every priced row, one per line, gift boxes on their own")
func catalogText() throws {
    let items = Catalog.items(csv: table)
    #expect(items.count == 4)
    let text = try #require(Catalog.text(items))
    #expect(text.contains("· 特级红富士　10斤装一箱　560元/斤"))
    #expect(text.contains("· 小番茄　68元/斤"))
    #expect(text.contains("【礼盒】\n· 特级红富士礼盒　2箱装　598元/盒"))
    #expect(!text.contains("空价格") && !text.contains("当季特级"))   // no price, no row; notes stay out
    #expect(text.hasPrefix("现在有这些") && text.hasSuffix("要哪种直接说。"))
}

@Test("A table without name and price columns, or no table at all, gives no price list")
func catalogNeedsATable() {
    #expect(Catalog.items(csv: "问题,答案\n发货,48小时").isEmpty)
    #expect(Catalog.text([]) == nil)
}

@Test("The sample shop knowledge base gives the full list")
func catalogFromSampleKnowledge() throws {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("test-fixtures/shop-knowledge")   // not the owner's own files
    let kb = KnowledgeBase.load(folder: folder)
    let text = try #require(Catalog.text(folder: kb.folder, files: kb.files))
    #expect(text.components(separatedBy: "\n").filter { $0.hasPrefix("· ") }.count == 16)
    print(text)
}

@Test("Typed in pieces, a long list never has a piece starting with a line break (that would send it early)")
func typingPiecesKeepLineBreaksInside() throws {
    let text = try #require(Catalog.text(Catalog.items(csv: table)))
    let pieces = AutoSender.pieces(text)
    #expect(pieces.joined() == text)
    #expect(pieces.allSatisfy { !($0.first?.isNewline ?? false) })
    #expect(pieces.allSatisfy { $0.utf16.count <= 20 })
}
