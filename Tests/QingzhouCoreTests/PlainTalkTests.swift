import Testing
@testable import QingzhouCore

@Test("Replies lose the punctuation people don't type on a phone")
func plainTalkPunctuation() {
    #expect(ReplyParser.plain("新鲜，当季收的。") == "新鲜，当季收的")
    #expect(ReplyParser.plain("送礼选春见，个大；爱吃甜的选爱媛。") == "送礼选春见，个大，爱吃甜的选爱媛")
    #expect(ReplyParser.plain("对，都是现摘的。当季摘了就发。") == "对，都是现摘的，当季摘了就发")
    #expect(ReplyParser.plain("在的～有什么需要！") == "在的，有什么需要")
    #expect(ReplyParser.plain("您好") == "你好")
    #expect(ReplyParser.plain("好的！") == "好的")
    #expect(ReplyParser.plain("你想要哪种？") == "你想要哪种？")       // a question keeps its mark
    #expect(ReplyParser.plain("说明：两斤不包邮") == "两斤不包邮")
}

@Test("Lists, totals and prices are left as they are")
func plainTalkKeepsLists() {
    let list = "给你配了这些：\n· 当季脐橙 2斤 180元\n· 猕猴桃 1斤 55元\n合计：235 元"
    #expect(ReplyParser.plain(list) == "给你配了这些：\n· 当季脐橙 2斤 180元\n· 猕猴桃 1斤 55元\n合计：235 元")
    #expect(ReplyParser.plain("89.9元一斤。") == "89.9元一斤")
    #expect(ReplyParser.plain("10:30 前下单当天发。") == "10:30 前下单当天发")
}

@Test("Time spent writing the reply counts as reading and typing time: no extra wait after a slow answer")
func pacingCountsWritingTime() {
    // Reading 2 s + typing 3 s; the answer took 6 s to write: send at once.
    #expect(HumanPacer.waitBeforeSending(read: 2, typing: 3, elapsed: 6, gapLeft: 0) == 0)
    // The answer came back in 1 s: wait the remaining 4 s.
    #expect(HumanPacer.waitBeforeSending(read: 2, typing: 3, elapsed: 1, gapLeft: 0) == 4)
    // Too soon after the last message sent: wait for the gap.
    #expect(HumanPacer.waitBeforeSending(read: 1, typing: 1, elapsed: 5, gapLeft: 2.5) == 2.5)
}
