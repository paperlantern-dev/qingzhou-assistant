import Foundation
import Testing
@testable import QingzhouCore

private func m(_ me: Bool, _ t: String) -> StoredMessage { StoredMessage(fromMe: me, text: t) }

@Test("Screens read while scrolling up are joined into one chat, oldest first, without repeats")
func historyPagesJoined() {
    let newest = [m(false, "四四"), m(true, "五五"), m(false, "六六六")]
    let middle = [m(false, "二二"), m(true, "三三三"), m(false, "四四")]
    let oldest = [m(true, "一一"), m(false, "二二")]
    let all = HistoryStitch.join(pagesNewestFirst: [newest, middle, oldest]).map(\.text)
    #expect(all == ["一一", "二二", "三三三", "四四", "五五", "六六六"])
    // The top bubble of a screen may be cut off: only its end shows.
    let cut = [m(false, "甜的吗"), m(true, "三三三"), m(false, "四四")]
    #expect(HistoryStitch.stitch(older: [m(true, "一一"), m(false, "脐橙是甜的吗")], newer: cut).map(\.text)
            == ["一一", "脐橙是甜的吗", "三三三", "四四"])
    // One tiny message alike is not enough to join on.
    #expect(HistoryStitch.stitch(older: [m(false, "好")], newer: [m(false, "好")]).count == 2)
    // Nothing more above: the same screen again adds nothing.
    #expect(HistoryStitch.join(pagesNewestFirst: [newest, newest]).count == 3)
}

@Test("History goes in front of what was already remembered, and newer remembered messages stay")
func historyBeforeMemory() {
    let history = [m(true, "早上好"), m(false, "脐橙还有吗"), m(true, "有的"), m(false, "那来两斤")]
    let stored = [m(false, "脐橙还有吗"), m(true, "有的"), m(false, "那来两斤"), m(true, "好，下午发")]
    #expect(HistoryStitch.stitch(older: history, newer: stored).map(\.text) == ["早上好", "脐橙还有吗", "有的", "那来两斤", "好，下午发"])
}

@Test("Owner's messages with an address, phone or tracking number are left out of learning")
func historyCleaning() {
    #expect(HistoryClean.learnable("行，下午给你发") == "行，下午给你发")
    // Made-up addresses: 示例市 / 示例路 do not exist.
    #expect(HistoryClean.learnable("收货地址：示例省示例市示例区示例路88号") == nil)
    #expect(HistoryClean.learnable("示例市示例区示例路88号3栋") == nil)
    #expect(HistoryClean.learnable("你电话是13812345678吗") == nil)
    #expect(HistoryClean.learnable("单号 SF1234567890123 你查一下") == nil)
    #expect(HistoryClean.learnable("好") == nil)
    #expect(HistoryClean.learnable("[图片]") == nil)
}

@Test("A customer's question and the owner's answer become a lesson; prices and promises are not learned")
func historyPairs() {
    let chat = [m(false, "你好"), m(true, "在"),
                m(false, "脐橙是现摘的吗"), m(true, "对，现摘的"), m(true, "个个都是好的"),
                m(false, "多少钱一斤"), m(true, "90一斤"),
                m(false, "坏了能退吗"), m(true, "拍照给我，退给你"),
                m(false, "地址发你了"), m(true, "收到，示例市示例区示例路88号对吧")]
    let pairs = HistoryClean.pairs(chat)
    #expect(pairs.map(\.question) == ["脐橙是现摘的吗"])
    #expect(pairs.first?.answer == "对，现摘的\n个个都是好的")
}

@Test("Of the text in the chat list, only each row's name is kept (not the preview under it)")
func chatListNames() {
    let lines = [UnreadRow(y: 60, name: "客户·王女士", preview: ""), UnreadRow(y: 80, name: "好的谢谢", preview: ""),
                 UnreadRow(y: 122, name: "客户·李先生", preview: ""), UnreadRow(y: 143, name: "[语音]", preview: ""),
                 UnreadRow(y: 184, name: "文件传输助手", preview: "")]
    #expect(HistoryStitch.rowNames(lines).map(\.name) == ["客户·王女士", "客户·李先生", "文件传输助手"])
}

@Test("Old messages read from the chat go in front of the remembered ones, once")
func memoryTakesHistory() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = CustomerMemoryStore(folder: dir)
    _ = store.remember(chatID: "c", name: "王女士", visible: [ChatBubble(fromMe: false, text: "那来两斤", top: 0),
                                                              ChatBubble(fromMe: true, text: "好，下午发", top: 1)])
    let old = [m(false, "脐橙还有吗"), m(true, "有的"), m(false, "那来两斤")]
    #expect(store.addHistory(chatID: "c", name: "王女士", messages: old) == 2)
    #expect(store.addHistory(chatID: "c", name: "王女士", messages: old) == 0)
    #expect(CustomerMemoryStore(folder: dir).record(for: "c")?.messages.map(\.text) == ["脐橙还有吗", "有的", "那来两斤", "好，下午发"])
}

@Test("Only real questions with a real answer are learned; replies like 好的 or 可以啊 are not")
func historyPairsAreReal() {
    let chat = [m(false, "可以啊"), m(true, "好的"),
                m(false, "今天的吗"), m(true, "是的"),
                m(false, "百香果可以泡水吗"), m(true, "可以"),
                m(false, "杨梅有吗"), m(true, "季节过了，不收了"),
                m(false, "杨梅有吗？"), m(true, "没了"),
                m(false, "可以"), m(true, "地址")]
    let pairs = HistoryClean.pairs(chat)
    #expect(pairs.map(\.question) == ["百香果可以泡水吗", "杨梅有吗"])
}
