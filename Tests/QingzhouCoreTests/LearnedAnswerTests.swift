import Foundation
import Testing
@testable import QingzhouCore

private func msg(_ fromMe: Bool, _ text: String) -> StoredMessage { StoredMessage(fromMe: fromMe, text: text) }

@Test("The owner's answer is what they wrote after the question, before the customer's next message")
func ownerAnswerFound() {
    let chat = [msg(false, "你好"), msg(true, "您好～"), msg(false, "能寄到新疆吗"), msg(true, "我确认一下再回复您"),
                msg(true, "好的"), msg(true, "新疆可以寄，顺丰空运3天左右"), msg(true, "运费另算"), msg(false, "好的谢谢")]
    let answer = OwnerAnswer.find(question: "能寄到新疆吗", in: chat, assistantSent: ["我确认一下再回复您"])
    #expect(answer == "新疆可以寄，顺丰空运3天左右\n运费另算")
}

@Test("No answer yet, only filler, or a question not in the chat give nothing")
func ownerAnswerMissing() {
    let asked = [msg(false, "能寄到新疆吗")]
    #expect(OwnerAnswer.find(question: "能寄到新疆吗", in: asked, assistantSent: []) == nil)
    #expect(OwnerAnswer.find(question: "能寄到新疆吗", in: asked + [msg(true, "稍等"), msg(true, "[图片]")], assistantSent: []) == nil)
    #expect(OwnerAnswer.find(question: "有现摘的吗", in: asked + [msg(true, "可以寄")], assistantSent: []) == nil)
}

@Test("A batch of questions is matched by its newest message")
func ownerAnswerToBatch() {
    let chat = [msg(false, "在吗"), msg(false, "能开发票吗"), msg(true, "可以开，下单后发我抬头")]
    #expect(OwnerAnswer.find(question: "在吗 / 能开发票吗", in: chat, assistantSent: []) == "可以开，下单后发我抬头")
}

@Test("Waiting questions are kept on disk, one per chat, and get their answer")
func suggestionStore() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = AnswerSuggestionStore(folder: dir)
    store.watch(chat: "人|王女士", who: "王女士", question: "能寄到新疆吗")
    store.watch(chat: "人|王女士", who: "王女士", question: "能开发票吗")
    #expect(store.waiting(in: "人|王女士").map(\.question) == ["能开发票吗"])
    let id = try #require(store.items.first?.id)
    store.setAnswer("可以开", for: id)
    #expect(store.waiting(in: "人|王女士").isEmpty && store.open(in: "人|王女士").count == 1)
    #expect(AnswerSuggestionStore(folder: dir).items.first?.answer == "可以开")
    store.remove(id)
    #expect(AnswerSuggestionStore(folder: dir).items.isEmpty)
}

@Test("Approved answers become rows of a knowledge file the assistant can search")
func learnedRowsAreKnowledge() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try LearnedQA.append(question: "能寄到新疆吗", answer: "可以寄，顺丰空运\n运费另算", to: dir)
    try LearnedQA.append(question: "能开发票吗", answer: "可以开,下单后发抬头", to: dir)
    let kb = KnowledgeBase.load(folder: dir)
    #expect(kb.chunks.map(\.text) == ["问题：能寄到新疆吗；回答：可以寄，顺丰空运；运费另算",
                                      "问题：能开发票吗；回答：可以开，下单后发抬头"])
    #expect(kb.search("寄新疆要几天").first?.chunk.text.contains("新疆") == true)
    #expect(Catalog.text(folder: dir, files: kb.files) == nil)   // not a price table
}
