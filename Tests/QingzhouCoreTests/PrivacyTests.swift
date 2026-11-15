import Foundation
import Testing
@testable import QingzhouCore

// Every address, name and phone number in these tests is made up (示例省 / 示例市 / 示例路 do not exist).

@Test("Phone numbers are hidden, with or without spaces and +86")
func privacyHidesPhones() {
    #expect(Privacy.redact("李四13900000001").text == "李四［电话］")
    #expect(Privacy.redact("手机号码: 139 0000 0003").text == "手机号码: ［电话］")
    #expect(Privacy.redact("+86 13900000002").text == "［电话］")
    #expect(Privacy.redact("座机 0591-87654321").text == "座机 ［电话］")
    #expect(Privacy.redact("订单 QZ-1608，单价 280 元").text == "订单 QZ-1608，单价 280 元")
}

@Test("Labelled address lines are hidden whole, with the recipient's name")
func privacyHidesLabelledAddresses() {
    let order = "收货人: 张三\n手机号码: 13800000000\n所在地区: 示例省示例市示例区示例街道\n详细地址: 示例路100号示例大厦A座1001"
    let r = Privacy.redact(order)
    #expect(r.changed)
    #expect(!r.text.contains("张三") && !r.text.contains("13800000000") && !r.text.contains("示例路100号"))
    #expect(!r.text.contains("示例区"))
    #expect(Privacy.redact("地址：示例市示例区示例路1号示例花园2号楼101 王").text == "地址：［地址］")
}

@Test("Unlabelled street addresses are hidden; a city alone is kept")
func privacyHidesStreetAddresses() {
    let r = Privacy.redact("示例省示例市示例区示例花园1栋二单元102 李四13900000001")
    #expect(!r.text.contains("示例花园") && !r.text.contains("102") && !r.text.contains("13900000001"))
    #expect(Privacy.redact("发到示例市示例新区能到吗？").text == "发到示例市示例新区能到吗？")
    #expect(Privacy.redact("示例市区能发货吗").text == "示例市区能发货吗")
    #expect(Privacy.redact("示例新区示例路100号").text == "［地址］")
}

@Test("ID card numbers are hidden; ordinary chat is untouched")
func privacyHidesIDsOnly() {
    #expect(Privacy.redact("身份证 11010119900101123X").text == "身份证 ［证件号］")
    let plain = "特级红富士多少钱一斤？两箱10斤装的，帮我留着"
    #expect(Privacy.redact(plain).text == plain)
    #expect(!Privacy.redact(plain).changed)
}

@Test("A reply that contains a hidden placeholder is caught")
func privacyFindsPlaceholdersInReplies() {
    #expect(Privacy.containsPlaceholder("好的，发到［地址］"))
    #expect(!Privacy.containsPlaceholder("好的，今天发货"))
}

@Test("Prompts for the cloud get a note when something was hidden")
func privacyCloudPrompt() {
    let safe = Privacy.forCloud("对方：我的电话13900000001")
    #expect(!safe.contains("13900000001") && safe.contains("隐私"))
    #expect(Privacy.forCloud("对方：你好") == "对方：你好")
}

@Test("Emails, WeChat IDs and foreign phone numbers are hidden")
func privacyHidesEmailsWeChatAndForeignPhones() {
    #expect(Privacy.redact("发票发到 zhang.san@example.com 谢谢").text == "发票发到 ［邮箱］ 谢谢")
    #expect(Privacy.redact("加我微信：apple_shop2024").text == "加我微信：［微信号］")
    #expect(Privacy.redact("我的微信号是 fruit-lover88").text == "我的微信号是 ［微信号］")
    #expect(Privacy.redact("vx: Applefan_01").text == "vx: ［微信号］")
    #expect(Privacy.redact("call (415) 555-0132").text == "call ［电话］")
    #expect(Privacy.redact("电话 +1 415-555-0132").text == "电话 ［电话］")
    #expect(Privacy.redact("+44 20 7946 0958").text == "［电话］")
    #expect(Privacy.containsPlaceholder("发到［邮箱］") && Privacy.containsPlaceholder("加［微信号］"))
    // Not private: payment words, prices, order numbers.
    #expect(Privacy.redact("微信支付宝都可以").text == "微信支付宝都可以")
    #expect(Privacy.redact("5斤装 39.9 元，订单 QZ-1608").text == "5斤装 39.9 元，订单 QZ-1608")
}

@Test("A name the customer gives with a label or “我叫” is hidden")
func privacyHidesStatedNames() {
    #expect(Privacy.redact("姓名：王小明").text == "姓名：［姓名］")
    #expect(Privacy.redact("我叫王小明，上次买过").text == "我叫［姓名］，上次买过")
    #expect(Privacy.redact("my name is John Smith").text == "my name is ［姓名］")
    #expect(Privacy.redact("我叫你发货了吗").text == "我叫你发货了吗")
}
