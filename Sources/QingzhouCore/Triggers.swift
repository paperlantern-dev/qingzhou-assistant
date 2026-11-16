import CoreGraphics
import Foundation

/// 关键词触发: when a customer's newest message contains one of the words, do a fixed action
/// (send a set text or picture, or leave it to the owner) instead of an AI reply.
public struct TriggerRule: Codable, Equatable, Identifiable {
    public enum Action: Codable, Equatable {
        case sendText(String)
        case sendImage(path: String)
        case handOver(reason: String)
        /// The whole price list, written from the knowledge base's price table when it is sent.
        case sendCatalog
    }

    /// The kinds of action, as the settings show them.
    public enum Kind: String, CaseIterable, Identifiable {
        case text = "发一段话"
        case image = "发一张图片"
        case catalog = "发价格表"
        case handOver = "交给我处理"
        public var id: String { rawValue }
    }

    public var id = UUID()
    public var keywords: [String]
    public var action: Action
    public var enabled = true

    public init(keywords: [String], action: Action, enabled: Bool = true) {
        self.keywords = keywords
        self.action = action
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case id, keywords, action, enabled }

    /// Rules saved by an older version keep defaults for what they don't have.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        action = try c.decode(Action.self, forKey: .action)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

// MARK: - Matching

extension TriggerRule {
    /// Ready-made rules for a shop, on from the start (the owner can change or turn off each).
    /// Money and blame go to the owner; a list question gets the whole price list. Order matters:
    /// “货坏了，你们还卖什么” is after-sales first. Words are chosen so everyday questions don't
    /// match (“人工催熟的吗” is not “转人工”, “有什么快递” is not a list question).
    public static var presets: [TriggerRule] {
        [
            TriggerRule(keywords: ["投诉", "退款", "退钱", "坏了", "臭了", "发臭", "变质", "不新鲜", "少发", "漏发",
                                   "发错", "差评"], action: .handOver(reason: "售后问题")),
            TriggerRule(keywords: ["转人工", "人工客服", "找真人", "真人回复", "是机器人", "机器人吗"],
                        action: .handOver(reason: "客人要找真人")),
            TriggerRule(keywords: ["便宜点", "便宜一点", "能便宜", "优惠点", "打个折", "打折吗", "最低价", "抹个零", "抹零"],
                        action: .handOver(reason: "客人在讲价")),
            TriggerRule(keywords: ["怎么付款", "怎么付钱", "付款码", "收款码", "转账", "下单链接", "发个链接"],
                        action: .handOver(reason: "客人要付款或下单")),
            TriggerRule(keywords: ["价格表", "价目表", "报价单", "产品清单", "商品清单", "菜单", "有什么产品", "有什么商品",
                                   "有什么货", "有什么水果", "有哪些产品", "有哪些商品", "有哪些水果",
                                   "卖什么", "卖些什么", "卖啥", "全部产品", "所有产品"], action: .sendCatalog),
        ]
    }

    /// The preset rules not in `rules` yet (same words and action, whatever their on/off).
    public static func missingPresets(in rules: [TriggerRule]) -> [TriggerRule] {
        presets.filter { preset in !rules.contains { $0.sameRule(as: preset) } }
    }

    /// The rule for what the customer sent since my last message (oldest first). Handing over looks at
    /// all of it (“货坏了” followed by “在吗” still goes to the owner); the other rules only at the
    /// newest message, so a question asked after “价格表” is still answered.
    public static func match(_ rules: [TriggerRule], pending: [String]) -> (rule: TriggerRule, keyword: String)? {
        let handOver = rules.filter { $0.action.kind == .handOver }
        return firstMatch(handOver, message: pending.joined(separator: " "))
            ?? firstMatch(rules, message: pending.last ?? "")
    }

    /// The first rule with a keyword in the customer's newest message, and that keyword.
    public static func firstMatch(_ rules: [TriggerRule], message: String) -> (rule: TriggerRule, keyword: String)? {
        for rule in rules {
            if let keyword = rule.keyword(in: message) { return (rule, keyword) }
        }
        return nil
    }

    /// The keyword found in `message`, or nil. Spaces, punctuation and letter case don't count;
    /// empty keywords are ignored; a rule that is off or not filled in never fires.
    public func keyword(in message: String) -> String? {
        guard enabled, isComplete else { return nil }
        let text = Self.fold(message)
        guard !text.isEmpty else { return nil }
        return keywords.first { word in
            let key = Self.fold(word)
            return !key.isEmpty && text.contains(key)
        }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Has a keyword and something to do (a text to send, a picture picked).
    public var isComplete: Bool {
        guard keywords.contains(where: { !Self.fold($0).isEmpty }) else { return false }
        return action.kind == .handOver || action.kind == .catalog || !action.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Why the message goes to the owner: their own reason, or the word the customer used.
    public func handOverReason(keyword: String) -> String {
        if case .handOver(let reason) = action {
            let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !r.isEmpty { return r }
        }
        return "提到“\(keyword)”"
    }

    /// Splits what the owner typed (“投诉，退款、坏了”) into keywords, without repeats.
    public static func keywords(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，、;；").union(.whitespacesAndNewlines)
        var seen: Set<String> = []
        return text.components(separatedBy: separators).filter { word in
            let key = fold(word)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    /// The keywords as the owner edits them.
    public var keywordText: String { keywords.joined(separator: "、") }

    /// The same words and action, whatever its id and on/off (so the common rule is added once).
    public func sameRule(as other: TriggerRule) -> Bool {
        Set(keywords.map(Self.fold)) == Set(other.keywords.map(Self.fold)) && action == other.action
    }

    private static func fold(_ s: String) -> String { TextMatch.normalize(s).lowercased() }
}

extension TriggerRule.Action {
    public init(kind: TriggerRule.Kind, content: String) {
        switch kind {
        case .text: self = .sendText(content)
        case .image: self = .sendImage(path: content)
        case .handOver: self = .handOver(reason: content)
        case .catalog: self = .sendCatalog
        }
    }

    public var kind: TriggerRule.Kind {
        switch self {
        case .sendText: return .text
        case .sendImage: return .image
        case .handOver: return .handOver
        case .sendCatalog: return .catalog
        }
    }

    /// The text to send, the picture's path, or the reason.
    public var content: String {
        switch self {
        case .sendText(let text): return text
        case .sendImage(let path): return path
        case .handOver(let reason): return reason
        case .sendCatalog: return ""
        }
    }

    /// For the run log: “发一段话：…”, “发图片：价目表.png”, “交给我处理”.
    public var summary: String {
        switch self {
        case .sendText(let text): return "发一段话：\(text.prefix(30))"
        case .sendImage(let path): return "发图片：\((path as NSString).lastPathComponent)"
        case .handOver: return "交给我处理"
        case .sendCatalog: return "发完整价格表"
        }
    }
}

// MARK: - Pictures (发图片 rules, picture drafts and 定时群发)

public enum PictureError: LocalizedError, Equatable {
    case notAPicture(String)
    case missing(String)
    case unreadable(String)
    case noFreeName(String)

    public var errorDescription: String? {
        switch self {
        case .notAPicture(let name): return "“\(name)”不是图片文件（可以用 png、jpg、gif、heic 等）"
        case .missing(let name): return "找不到图片“\(name)”，它可能被移走或删掉了"
        case .unreadable(let name): return "图片“\(name)”打不开"
        case .noFreeName(let name): return "图片文件夹里叫“\(name)”的图片太多了"
        }
    }
}

/// Pictures the owner picked, copied into the app's own folder so saved rules and drafts keep working.
public enum PictureLibrary {
    public static let fileTypes = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "tif", "tiff"]

    /// ~/Library/Application Support/轻舟助手/图片
    public static var defaultFolder: URL {
        AppData.root.appendingPathComponent("图片", isDirectory: true)
    }

    /// A common picture file, by its extension (whether or not it exists).
    public static func isPicture(_ url: URL) -> Bool {
        fileTypes.contains(url.pathExtension.lowercased())
    }

    /// Copies a picture into `folder` under its own name (“价目表 2.png” when another picture already
    /// has it) and returns the copy. The same picture picked again, or one already there, is not copied.
    public static func importPicture(_ url: URL, into folder: URL = defaultFolder) throws -> URL {
        let name = url.lastPathComponent
        guard isPicture(url) else { throw PictureError.notAPicture(name) }
        let files = FileManager.default
        guard files.fileExists(atPath: url.path) else { throw PictureError.missing(name) }
        if url.deletingLastPathComponent().resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path {
            return url
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        for n in 1...999 {
            let target = folder.appendingPathComponent(numbered(name, n))
            if !files.fileExists(atPath: target.path) {
                try files.copyItem(at: url, to: target)
                return target
            }
            if files.contentsEqual(atPath: target.path, andPath: url.path) { return target }
        }
        throw PictureError.noFreeName(name)
    }

    /// “价目表.png” as the n-th picture of that name: “价目表 2.png”.
    static func numbered(_ name: String, _ n: Int) -> String {
        guard n > 1 else { return name }
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        return ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
    }
}

/// Checks on screen that a pasted picture was sent. OCR can't read pictures, so it compares the
/// message pane before and after, and makes sure nothing else explains the change.
public enum PictureCheck {
    /// Fingerprint of the message pane only: right of the contact list, between the header and the input box.
    public static func paneFingerprint(_ image: CGImage, windowSize: CGSize, layout: ChatLayout) -> [UInt8] {
        let pane = CGRect(x: layout.sidebarWidth, y: layout.headerHeight, width: windowSize.width - layout.sidebarWidth,
                          height: windowSize.height - layout.headerHeight - layout.inputHeight)
        guard pane.width > 0, pane.height > 0 else { return [] }
        let scale = CGFloat(image.width) / max(1, windowSize.width)
        let rect = CGRect(x: pane.minX * scale, y: pane.minY * scale, width: pane.width * scale, height: pane.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty, let crop = image.cropping(to: rect) else { return [] }
        return WindowCapture.fingerprint(crop)
    }

    /// True when enough of the pane looks different (a picture appeared, the chat moved up), not just a speck.
    public static func changed(_ before: [UInt8], _ after: [UInt8]) -> Bool {
        guard !before.isEmpty, before.count == after.count else { return false }
        let moved = zip(before, after).filter { abs(Int($0) - Int($1)) > 12 }.count
        return moved >= max(8, before.count / 200)
    }

    /// Sent when the pane changed, nothing is left in the input box, and the change is not a new
    /// message from them or the file's name pasted as text.
    public static func confirmed(before: Conversation, after: Conversation, paneChanged: Bool,
                                 inputText: String, fileName: String) -> Bool {
        guard paneChanged, inputLooksEmpty(inputText) else { return false }
        guard let last = after.bubbles.last else { return true }
        if last.fromMe {   // text inside the picture reads as my message; its file name means it went in as text
            let name = TextMatch.normalize((fileName as NSString).deletingPathExtension)
            return name.count < 2 || !TextMatch.normalize(last.text).contains(name)
        }
        guard let theirs = before.bubbles.last(where: { !$0.fromMe }) else { return false }
        return TextMatch.similar(TextMatch.normalize(last.text), TextMatch.normalize(theirs.text))
    }

    /// The input box's OCR text has no real text in it (one stray mark, like the caret, doesn't count).
    public static func inputLooksEmpty(_ inputText: String) -> Bool {
        TextMatch.normalize(inputText).count < 2
    }
}
