import Foundation

/// Hides addresses, phone numbers, emails, WeChat IDs, stated names and ID numbers before any text leaves this
/// Mac (cloud model, phone alerts). What stays on the Mac (customer memory) is not changed.
public enum Privacy {
    public static let phone = "［电话］", address = "［地址］", name = "［姓名］", idNumber = "［证件号］"
    public static let email = "［邮箱］", weChat = "［微信号］"

    /// The text with private details replaced, and whether anything was replaced.
    public static func redact(_ text: String) -> (text: String, changed: Bool) {
        var s = text
        s = replace(#"(收货人|收件人|联系人|姓名|名字|称呼)(\s*[:：]\s*)[^\s,，;；。]+"#, in: s, with: "$1$2\(name)")
        s = replace(#"我叫(?![你他她它我人了咱大])[\u4e00-\u9fa5·]{2,4}(?=[\s,，。.!！、]|$)"#, in: s, with: "我叫\(name)")
        s = replace(#"((?i:my name is)\s+)[A-Z][a-z]+(?:\s[A-Z][a-z]+)?"#, in: s, with: "$1\(name)")
        s = replace(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"#, in: s, with: email)
        s = replace(#"(微信号?|[vV]信)(\s*(?:号|id|ID)?\s*[:：是]?\s*)[A-Za-z][A-Za-z0-9_-]{5,19}(?![A-Za-z0-9_-])"#, in: s, with: "$1$2\(weChat)")
        s = replace(#"(?i)(?<![a-z0-9])(vx|wx|weixin|wechat)(\s*(?:号|id)?\s*[:：]\s*)[a-z][a-z0-9_-]{5,19}(?![a-z0-9_-])"#, in: s, with: "$1$2\(weChat)")
        s = replace(#"(所在地区|详细地址|收货地址|收件地址|地址)(\s*[:：]\s*)[^\n]+"#, in: s, with: "$1$2\(address)")
        s = replace(#"(?<![0-9A-Za-z])\d{17}[0-9Xx](?![0-9A-Za-z])"#, in: s, with: idNumber)
        s = replace(#"(?<!\d)(?:\+?86[\s-]?)?1[3-9]\d(?:[\s-]?\d){8}(?!\d)"#, in: s, with: phone)
        s = replace(#"(?<!\d)0\d{2,3}-\d{7,8}(?!\d)"#, in: s, with: phone)
        // Other countries: “+44 20 7946 0958”, “(415) 555-0132”, “415-555-0132”.
        s = replace(#"(?<![\dA-Za-z])\+\d{1,3}[\s-]?\d(?:[\s-]?\d){6,12}(?!\d)"#, in: s, with: phone)
        s = replace(#"(?<![\dA-Za-z])(?:\(\d{3}\)\s?|\d{3}[-.])\d{3}[-.\s]\d{4}(?!\d)"#, in: s, with: phone)
        s = hideStreetAddresses(s)
        return (s, s != text)
    }

    /// A reply that would show a hidden placeholder to the customer must not be sent.
    public static func containsPlaceholder(_ text: String) -> Bool {
        [phone, address, name, idNumber, email, weChat].contains { text.contains($0) }
    }

    /// The prompt as it may go to a cloud model: details hidden, with a note telling the model why.
    public static func forCloud(_ prompt: String) -> String {
        let r = redact(prompt)
        guard r.changed else { return prompt }
        return "（注意：内容里的\(address)\(phone)\(name)\(idNumber)\(email)\(weChat)是为了保护隐私隐藏掉的，不要猜，也不要在回复里写出来。）\n" + r.text
    }

    // MARK: - Street addresses without a label

    /// Words that make a stretch of text look like a street address.
    private static let markers = ["省", "自治区", "市", "区", "县", "镇", "乡", "街道", "路", "街", "大道", "巷", "弄",
                                  "号", "栋", "幢", "单元", "室", "楼", "小区", "花园", "大厦", "广场", "公寓", "村"]

    /// A stretch between punctuation with three address words, or two and a number, is hidden whole.
    /// (“示例市示例新区” alone stays: a city or district is needed to answer shipping questions.)
    private static func hideStreetAddresses(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"[^\s，,。；;！!？?、：:]+"#) else { return text }
        var out = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: out.length))
        for m in matches.reversed() {
            let piece = out.substring(with: m.range)
            let count = markers.filter { piece.contains($0) }.count
            let hasDigit = piece.rangeOfCharacter(from: .decimalDigits) != nil
            if count >= 3 || (count >= 2 && hasDigit) {
                out = out.replacingCharacters(in: m.range, with: address) as NSString
            }
        }
        return out as String
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}
