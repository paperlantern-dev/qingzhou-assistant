import Testing
@testable import QingzhouCore

// MARK: 群里只回@我

@Test("“@我” is recognised however WeChat and OCR write it", arguments: [
    "@店小二 多少钱一斤",           // as WeChat writes it
    "＠店小二 多少钱一斤",           // full-width @
    "@ 店小二 多少钱一斤",           // a space after @
    "@店小二多少钱一斤",             // OCR dropped the space after the name
    "@店小二，在吗？",               // punctuation right after the name
    "@店小二",                       // only the mention
    "脐橙还有吗@店小二",             // at the end
    "@张三 @店小二 一起看看",        // one of several mentions
    "张三@店小二 多少钱",            // the sender's nickname read into the same line
])
func mentionsMe(text: String) {
    #expect(Mentions.mentions(me: "店小二", in: text))
}

@Test("Messages that don't @ me", arguments: [
    "店小二 多少钱一斤",             // my name, but no @
    "@张三 多少钱一斤",
    "@所有人 今晚八点开团",
    "@店小 在吗",                    // only part of my name
    "@店长 多少钱",
    "多少钱一斤",
    "",
    "发到 abc@qq.com",
])
func notMentioningMe(text: String) {
    #expect(!Mentions.mentions(me: "店小二", in: text))
}

@Test("Emoji, spaces, a typed @ and letter case in my name don't matter")
func nameVariants() {
    #expect(Mentions.mentions(me: "店小二🍎", in: "@店小二🍎 多少钱"))
    #expect(Mentions.mentions(me: "店小二🍎", in: "@店小二 多少钱"))               // OCR dropped the emoji
    #expect(Mentions.mentions(me: "店小二", in: "@店小二🍎 多少钱"))
    #expect(Mentions.mentions(me: "店小二🍎新鲜水果", in: "@店小二2新鲜水果 在吗"))  // emoji read as “2”
    #expect(Mentions.mentions(me: " 店小二 ", in: "@店小二 在吗"))
    #expect(Mentions.mentions(me: "@店小二", in: "@店小二 在吗"))
    #expect(Mentions.mentions(me: "Tom", in: "@tom 在吗"))
    #expect(Mentions.mentions(me: "龙", in: "@龙 在吗"))                          // a one-character nickname
}

@Test("Without a name nothing counts as “@我”")
func emptyName() {
    #expect(!Mentions.mentions(me: "", in: "@店小二 在吗"))
    #expect(!Mentions.mentions(me: "  ", in: "@ 在吗"))
    #expect(!Mentions.mentions(me: "🍎", in: "@🍎 在吗"))
}

@Test("A long name survives one OCR slip; a short one must match exactly")
func ocrSlips() {
    #expect(Mentions.mentions(me: "店小二新鲜水果店", in: "@店小二新鮮水果店 在吗"))
    #expect(!Mentions.mentions(me: "店小二", in: "@店小三 在吗"))
}

/// Decision: OCR usually drops the narrow space WeChat puts after a mention, so “@店小二二号” reads
/// the same as “@店小二” followed by “二号…”. They can't be told apart, and it counts as “@我”.
@Test("A longer name that starts with mine counts as “@我” (can't be told apart)")
func longerNameCounts() {
    #expect(Mentions.mentions(me: "店小二", in: "@店小二二号 在吗"))
}

// MARK: 只回这些人 (matched like the never-reply list)

@Test("The “只回这些人” list matches chat titles and contact rows like the never-reply list")
func onlyListMatching() {
    let list = NeverReplyList(["客户·王女士", "水果团购群"])
    #expect(list.contains("客户·王女士"))
    #expect(list.contains("客户·王…"))          // cut off in the contact list
    #expect(list.contains("水果团购群(23)"))    // a group title carries its member count
    #expect(!list.contains("客户·李先生"))
    #expect(!NeverReplyList([]).contains("客户·王女士"))
}
