import CoreGraphics
import Foundation
import Testing
@testable import QingzhouCore

@Test("Group titles end with a member count", arguments: [
    ("客户交流群(12)", true), ("5群店小二水果 (5)", true), ("店小二水果3群（256）", true),
    ("店小二新鲜水果", false), ("客户·王女士", false), ("小明哥 1.1", false), ("订单(未付款)", false),
])
func groupTitle(title: String, isGroup: Bool) {
    #expect(GroupChat.isGroupTitle(title) == isGroup)
}

@Test("Only a “nickname: message” preview looks like a group", arguments: [
    ("小赵: 几点发货？", true), ("张三：收到", true), ("[3条] 小赵: 好的", true),
    // Real WeChat rows that were wrongly treated as groups: times and dates are not previews.
    ("07:18", false), ("06:47", false), ("2024/02/17", false), ("昨天", false),
    ("你那边有什么产品", false), ("回答我一下", false), ("你好", false), ("", false),
])
func groupPreview(preview: String, isGroup: Bool) {
    #expect(GroupChat.looksLikeGroupPreview(preview) == isGroup)
}

@Test("System chats are recognized")
func systemChats() {
    #expect(SystemChat.isSystem("公众号"))
    #expect(SystemChat.isSystem("文件传输助手"))
    #expect(!SystemChat.isSystem("龙辉"))
}

@Test("A group and a person with the same name are different chats")
func sameNameGroupAndPerson() {
    let person = ChatID.make(title: "店小二新鲜水果")
    let group = ChatID.make(title: "店小二新鲜水果 (5)")
    #expect(!ChatID.same(person, group))
    // OCR variants of the same private chat (emoji read differently) are still the same chat.
    #expect(ChatID.same(ChatID.make(title: "店小二2新鲜水果"), ChatID.make(title: "店小二＜新鲜水果")))
    // A group's member count changing is still the same group.
    #expect(ChatID.same(group, ChatID.make(title: "店小二新鲜水果（6）")))
}

@Test("Hourly total limit")
func totalLimit() {
    var l = SendLimiter(maxPerHour: 3, maxPerChatPerHour: 10)
    let t0 = Date()
    for i in 0..<3 { l.record(chat: ChatID.make(title: "客户\(i)"), at: t0) }
    #expect(l.blockReason(chat: ChatID.make(title: "客户9"), now: t0) != nil)
    #expect(l.blockReason(chat: ChatID.make(title: "客户9"), now: t0.addingTimeInterval(3601)) == nil)
}

@Test("Per-chat limit: OCR-tolerant, and a same-name group is counted separately")
func perChatLimit() {
    var l = SendLimiter(maxPerHour: 100, maxPerChatPerHour: 2)
    let t0 = Date()
    l.record(chat: ChatID.make(title: "店小二2新鲜水果"), at: t0)
    l.record(chat: ChatID.make(title: "店小二入新鲜水果"), at: t0)
    #expect(l.blockReason(chat: ChatID.make(title: "店小二新鲜水果"), now: t0) != nil)
    #expect(l.blockReason(chat: ChatID.make(title: "店小二新鲜水果 (5)"), now: t0) == nil)
}

@Test("Reads name and preview of an unread row, ignoring the time column (real WeChat layout)")
func readsUnreadRow() {
    let layout = ChatTarget.weChat.layout
    let win = CGSize(width: 880, height: 640)
    func line(_ t: String, x: CGFloat, y: CGFloat, w: CGFloat = 120) -> OCRLine {
        OCRLine(text: t, confidence: 1,
                box: CGRect(x: x / win.width, y: 1 - (y + 15) / win.height, width: w / win.width, height: 15 / win.height))
    }
    // Positions measured from the real WeChat screenshot (points).
    let lines = [
        line("龙辉", x: 116, y: 140, w: 30), line("07:18", x: 260, y: 143, w: 30), line("你那边有什么产品", x: 117, y: 162),
        line("公众号", x: 117, y: 400, w: 50), line("06:47", x: 259, y: 402, w: 30),
        line("［4条］ 城市晚报新闻：集体公告，…", x: 117, y: 422, w: 130),
    ]
    let rows = UnreadRowReader.rows(badges: [138.5, 399], lines: lines, windowSize: win, layout: layout)
    #expect(rows.map(\.name) == ["龙辉", "公众号"])
    #expect(rows.map(\.preview) == ["你那边有什么产品", "［4条］ 城市晚报新闻：集体公告，…"])
    #expect(!GroupChat.looksLikeGroupPreview(rows[0].preview))
    #expect(SystemChat.isSystem(rows[1].name))
}

@Test("A row whose name line is missing is not trusted (no preview taken as the name)")
func rowWithoutNameLine() {
    let layout = ChatTarget.mockWeChat.layout
    let win = CGSize(width: 860, height: 640)
    func line(_ t: String, y: CGFloat) -> OCRLine {
        OCRLine(text: t, confidence: 1,
                box: CGRect(x: 57 / win.width, y: 1 - (y + 14) / win.height, width: 120 / win.width, height: 14 / win.height))
    }
    // Badge at 223; only the preview line (243) is readable in this frame.
    let rows = UnreadRowReader.rows(badges: [223], lines: [line("你好，我想问一…", y: 243)], windowSize: win, layout: layout)
    #expect(rows == [UnreadRow(y: 223, name: "", preview: "")])
    // With the name line present, both are read.
    let ok = UnreadRowReader.rows(badges: [223], lines: [line("客户•王女士", y: 224), line("你好，我想问一…", y: 243)],
                                  windowSize: win, layout: layout)
    #expect(ok.first?.name == "客户•王女士")
    #expect(ok.first?.preview == "你好，我想问一…")
}

@Test("A picked window of an uncalibrated app is watch-only")
func uncalibratedAppIsWatchOnly() {
    #expect(ChatTarget.forApp(bundleID: "com.alibaba.DingTalkMac", name: "钉钉").supportsAutoReply == false)
    #expect(ChatTarget.forApp(bundleID: "com.tencent.xinWeChat", name: "微信") == .weChat)
    #expect(ChatTarget.forApp(bundleID: "com.qingzhou.mock-wechat", name: "模拟微信").supportsAutoReply)
}
