import Foundation

/// “✨ 跟轻舟说”: the owner says what to change in plain words; the model turns it into a list of
/// changes; the app shows the list and changes nothing until the owner confirms.
/// It can change rules, knowledge (answers and prices), the persona and the reply switches —
/// never API keys, alert addresses, files, or messages to customers.
public enum SettingChange: Equatable {
    case addWords(rule: String, words: [String])
    case removeWords(rule: String, words: [String])
    case newRule(name: String, words: [String], text: String?)     // text nil → hand over to the owner
    case toggleRule(rule: String, on: Bool)
    case addAnswer(question: String, answer: String)
    case setPrice(item: String, spec: String, price: String)
    case setPersona(String)
    case replyAll(Bool)            // true: 全回, false: 稳妥
    case confirmFirst(Bool)        // 发之前让我确认
    case replyToGroups(Bool)
    case voiceToText(Bool)
    case outreach(Bool)            // 到货和新品通知
    case revisit(Bool)             // 问候老客户
    case alerts(Bool)              // 手机提醒
    case maxPerHour(Int)
    case maxPerChatPerHour(Int)
    case neverReplyAdd([String])
    case neverReplyRemove([String])
    case soldOut([String])        // names from the price table
    case backInStock([String])

    /// One line for the confirmation card.
    public var summary: String {
        func onOff(_ on: Bool) -> String { on ? "打开" : "关掉" }
        switch self {
        case .addWords(let r, let w): return "关键词「\(r)」加上：\(w.joined(separator: "、"))"
        case .removeWords(let r, let w): return "关键词「\(r)」去掉：\(w.joined(separator: "、"))"
        case .newRule(let n, let w, let t):
            return "新规则「\(n)」：说到 \(w.joined(separator: "、")) → " + (t.map { "回“\($0)”" } ?? "交给你")
        case .toggleRule(let r, let on): return "\(onOff(on))关键词「\(r)」"
        case .addAnswer(let q, let a): return "知识库加一条：问“\(q)” → 答“\(a)”"
        case .setPrice(let i, let s, let p): return "价格表：\(i)\(s.isEmpty ? "" : "（\(s)）") 改成 \(p)"
        case .setPersona: return "说话风格改成新的写法（见下）"
        case .replyAll(let all): return "回复范围改成：" + (all ? "全回" : "稳妥（只回有把握的）")
        case .confirmFirst(let on): return on ? "改成发之前让你确认" : "改成写好自动发"
        case .replyToGroups(let on): return "\(onOff(on))回复群聊"
        case .voiceToText(let on): return "\(onOff(on))语音自动转文字"
        case .outreach(let on): return "\(onOff(on))到货和新品通知"
        case .revisit(let on): return "\(onOff(on))主动问候老客户"
        case .alerts(let on): return "\(onOff(on))手机提醒"
        case .maxPerHour(let n): return "每小时最多发 \(n) 条"
        case .maxPerChatPerHour(let n): return "每位客户每小时最多 \(n) 条"
        case .neverReplyAdd(let n): return "不自动回复：加上 \(n.joined(separator: "、"))"
        case .neverReplyRemove(let n): return "不自动回复：去掉 \(n.joined(separator: "、"))"
        case .soldOut(let n): return "标成卖完：\(n.joined(separator: "、"))"
        case .backInStock(let n): return "标成有货：\(n.joined(separator: "、"))"
        }
    }
}

/// What the model is told about the current settings, and what the changes are checked against.
public struct SettingsSnapshot {
    public var rules: [TriggerRule]
    public var persona: String
    public var priceItems: [Catalog.Item]
    public var neverReply: [String]
    public var replyAll: Bool
    public var confirmFirst: Bool
    public var replyToGroups: Bool
    public var maxPerHour: Int
    public var maxPerChatPerHour: Int
    public var alertsAvailable: Bool   // a phone-alert address is saved
    /// Which page the owner is on (“客户”), so “这个” can be understood.
    public var page: String = ""
    /// How today went, for questions (“今天回了多少？谁在等我？”).
    public var facts: String = ""
    /// Names on the price table the owner marked as sold out.
    public var soldOut: [String] = []

    public init(rules: [TriggerRule], persona: String, priceItems: [Catalog.Item], neverReply: [String],
                replyAll: Bool, confirmFirst: Bool, replyToGroups: Bool, maxPerHour: Int, maxPerChatPerHour: Int,
                alertsAvailable: Bool) {
        self.rules = rules
        self.persona = persona
        self.priceItems = priceItems
        self.neverReply = neverReply
        self.replyAll = replyAll
        self.confirmFirst = confirmFirst
        self.replyToGroups = replyToGroups
        self.maxPerHour = maxPerHour
        self.maxPerChatPerHour = maxPerChatPerHour
        self.alertsAvailable = alertsAvailable
    }
}

/// What came back from the model: the changes that passed the checks, the ones that did not
/// (with why), and the model's own short answer.
public struct SettingsPlan: Equatable {
    public var changes: [SettingChange]
    public var problems: [String]
    public var reply: String
    /// When the owner wants to see how a customer would be answered: the customer's words.
    public var customerQuestion: String?

    public init(changes: [SettingChange], problems: [String], reply: String, customerQuestion: String? = nil) {
        self.changes = changes
        self.problems = problems
        self.reply = reply
        self.customerQuestion = customerQuestion
    }
}

public enum SettingsAssistant {
    // MARK: Prompt

    public static func prompt(request: String, snapshot s: SettingsSnapshot, history: [ChatTurn] = []) -> String {
        let rules = s.rules.map { r in
            "- 「\(r.displayName)」\(r.enabled ? "" : "（关着）")：\(r.action.kind == .handOver ? "交给店主" : r.action.kind.rawValue)；词：\(r.keywordText)"
        }.joined(separator: "\n")
        let prices = s.priceItems.prefix(60).map { "- \($0.name)\($0.spec.isEmpty ? "" : "（\($0.spec)）")：\($0.price)" }
            .joined(separator: "\n")
        return """
        你是“轻舟助手”的设置助理。店主用一句话告诉你想怎么改设置，你把它变成修改单。只改店主明确说的，不要自作主张。

        【现在的关键词规则】
        \(rules.isEmpty ? "（没有）" : rules)

        【价格表】
        \(prices.isEmpty ? "（没有价格表）" : prices)

        【说话风格】
        \(s.persona.isEmpty ? "（没写）" : s.persona)

        【开关】回复范围：\(s.replyAll ? "全回" : "稳妥")；发之前确认：\(s.confirmFirst ? "是" : "否")；回群聊：\(s.replyToGroups ? "是" : "否")；每小时最多 \(s.maxPerHour) 条；每人每小时最多 \(s.maxPerChatPerHour) 条
        【卖完了的】\(s.soldOut.isEmpty ? "（没有，价格表上的都有货）" : s.soldOut.joined(separator: "、"))
        【不自动回复的人】\(s.neverReply.isEmpty ? "（没有）" : s.neverReply.joined(separator: "、"))
        【今天的情况】\(s.facts.isEmpty ? "（没有记录）" : s.facts)
        【店主现在在】\(s.page.isEmpty ? "（不知道）" : s.page + "页")

        店主也可能只是问问题（今天回了多少、谁在等他、某样东西卖多少、价格表多久没改……）：这时 actions 留空，在 reply 里用上面的资料直接回答，简短口语，不要编资料里没有的。

        店主想看你怎么回客人（“客人问水蜜桃多少钱你怎么回”“试试客人问…”“假如有人说…”）：把客人那句话原样放进 as_customer，actions 留空，reply 写一句“我按回客人的样子试一下”之类。系统会用真正回客人的方式答给他看。

        只输出一个 JSON，不要别的字：
        {"reply": "一句话告诉店主你打算改什么，或者回答他的问题（口语、简短）", "actions": [ ... ], "as_customer": "只有试客人问时才写，否则不写"}

        actions 里每一项是下面其中一种（rule 要用上面规则的名字）：
        {"type":"add_words","rule":"售后","words":["发霉","有异味"]}
        {"type":"remove_words","rule":"讲价","words":["优惠点"]}
        {"type":"new_rule","name":"自提","words":["自提","到店拿"],"text":null}   （text 为 null 表示交给店主；写了 text 就是自动回这句话）
        {"type":"toggle_rule","rule":"讲价","on":false}
        {"type":"add_answer","question":"周日发货吗","answer":"周日不发货，周一统一发"}
        {"type":"set_price","item":"水蜜桃","spec":"","price":"88元/斤"}   （spec 是规格，同名商品有几种规格时必须写）
        {"type":"set_persona","text":"完整的新说话风格"}   （在现有写法上改，保留没让改的部分）
        {"type":"set","key":"replyAll|confirmFirst|replyToGroups|voiceToText|outreach|revisit|alerts","value":true}
        {"type":"set","key":"maxPerHour|maxPerChatPerHour","value":30}
        {"type":"sold_out","items":["水蜜桃"]}   （店主说某样货卖完了、没货了；items 用价格表里的品名）
        {"type":"in_stock","items":["水蜜桃"]}   （店主说又有货了、到货了）
        {"type":"never_reply_add","names":["老妈"]}
        {"type":"never_reply_remove","names":["老妈"]}

        店主让你“补全”某条规则的说法时：想 8–15 个客人真的会说的、短的说法，用 add_words，不要和已有的重复，不要容易误判的日常词。
        改不了的事（比如密钥、发消息、删文件），actions 留空，在 reply 里说明。

        \(history.isEmpty ? "" : "【前面聊过的（用来理解“再加”“那个”“刚才那条”指什么；之前确认过的已经改好了，不要重复改）】\n" + history.map { ($0.mine ? "店主：" : "你：") + $0.text }.joined(separator: "\n") + "\n\n")店主说：\(request)
        """
    }

    // MARK: Reading the answer

    /// Reads the model's JSON and checks every change against the current settings.
    public static func plan(from raw: String, snapshot s: SettingsSnapshot) -> SettingsPlan {
        guard let json = jsonObject(in: raw) else {
            return SettingsPlan(changes: [], problems: ["没看懂模型的回答，换个说法再试一次"], reply: "")
        }
        let reply = (json["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var changes: [SettingChange] = []
        var problems: [String] = []
        for item in (json["actions"] as? [[String: Any]]) ?? [] {
            if let type = item["type"] as? String, type == "sold_out" || type == "in_stock" {
                let checked = stock(item, soldOut: type == "sold_out", s)
                if let c = checked.change { changes.append(c) }
                problems += checked.problems
                continue
            }
            switch check(item, s) {
            case .success(let c): changes.append(c)
            case .failure(let p): problems.append(p.text)
            }
        }
        let asked = ((json["as_customer"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsPlan(changes: changes, problems: problems, reply: reply, customerQuestion: asked.isEmpty ? nil : asked)
    }

    struct Problem: Error { let text: String }

    /// 卖完 / 有货: the names are matched to the price table; ones not on it are said, the rest kept.
    private static func stock(_ a: [String: Any], soldOut out: Bool, _ s: SettingsSnapshot) -> (change: SettingChange?, problems: [String]) {
        let said = ((a["items"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var names: Set<String> = [], unknown: [String] = []
        for w in said {
            let hits = s.priceItems.filter { $0.name.contains(w) || w.contains($0.name) }.map(\.name)
            if hits.isEmpty { unknown.append(w) } else { names.formUnion(hits) }
        }
        let changing = names.sorted().filter { out != s.soldOut.contains($0) }   // only what changes
        var problems = unknown.isEmpty ? [] : ["价格表里没有“\(unknown.joined(separator: "、"))”"]
        if changing.isEmpty, unknown.isEmpty { problems.append(out ? "这些已经标成卖完了" : "这些本来就是有货的") }
        return (changing.isEmpty ? nil : (out ? .soldOut(changing) : .backInStock(changing)), problems)
    }

    private static func check(_ a: [String: Any], _ s: SettingsSnapshot) -> Result<SettingChange, Problem> {
        func words(_ key: String) -> [String] {
            ((a[key] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        func text(_ key: String) -> String { ((a[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func rule(_ name: String) -> TriggerRule? { findRule(name, in: s.rules) }

        switch a["type"] as? String ?? "" {
        case "add_words":
            guard let r = rule(text("rule")) else { return .failure(Problem(text: "没有叫「\(text("rule"))」的规则")) }
            let new = words("words").filter { w in !r.keywords.contains { TextMatch.normalize($0) == TextMatch.normalize(w) } }
            guard !new.isEmpty else { return .failure(Problem(text: "「\(r.displayName)」已经有这些词了")) }
            return .success(.addWords(rule: r.displayName, words: new))
        case "remove_words":
            guard let r = rule(text("rule")) else { return .failure(Problem(text: "没有叫「\(text("rule"))」的规则")) }
            let gone = words("words").filter { w in r.keywords.contains { TextMatch.normalize($0) == TextMatch.normalize(w) } }
            guard !gone.isEmpty else { return .failure(Problem(text: "「\(r.displayName)」里没有这些词")) }
            return .success(.removeWords(rule: r.displayName, words: gone))
        case "new_rule":
            let name = text("name"), w = words("words")
            guard !name.isEmpty, !w.isEmpty else { return .failure(Problem(text: "新规则没写名字或关键词")) }
            guard rule(name) == nil else { return .failure(Problem(text: "已经有「\(name)」这条规则了")) }
            let reply = text("text")
            return .success(.newRule(name: name, words: w, text: reply.isEmpty ? nil : reply))
        case "toggle_rule":
            guard let r = rule(text("rule")) else { return .failure(Problem(text: "没有叫「\(text("rule"))」的规则")) }
            return .success(.toggleRule(rule: r.displayName, on: a["on"] as? Bool ?? true))
        case "add_answer":
            let q = text("question"), ans = text("answer")
            guard !q.isEmpty, !ans.isEmpty else { return .failure(Problem(text: "问答没写全")) }
            return .success(.addAnswer(question: q, answer: ans))
        case "set_price":
            let item = text("item"), spec = text("spec"), price = text("price")
            guard !item.isEmpty, !price.isEmpty else { return .failure(Problem(text: "改价没写商品或价格")) }
            let hits = s.priceItems.filter { $0.name.contains(item) && (spec.isEmpty || $0.spec.contains(spec)) }
            if hits.isEmpty { return .failure(Problem(text: "价格表里没有“\(item)”")) }
            if hits.count > 1 {
                return .failure(Problem(text: "“\(item)”有 \(hits.count) 种规格（\(hits.map(\.spec).joined(separator: "、"))），说清楚改哪种"))
            }
            return .success(.setPrice(item: hits[0].name, spec: hits[0].spec, price: price))
        case "set_persona":
            let t = text("text")
            guard !t.isEmpty else { return .failure(Problem(text: "说话风格没写内容")) }
            return .success(.setPersona(String(t.prefix(1200))))
        case "set":
            let key = text("key")
            if let n = (a["value"] as? NSNumber)?.intValue, !(a["value"] is Bool) {
                switch key {
                case "maxPerHour": return .success(.maxPerHour(min(max(n, 5), 60)))
                case "maxPerChatPerHour": return .success(.maxPerChatPerHour(min(max(n, 1), 20)))
                default: break
                }
            }
            guard let on = a["value"] as? Bool else { return .failure(Problem(text: "看不懂要怎么改“\(key)”")) }
            switch key {
            case "replyAll": return .success(.replyAll(on))
            case "confirmFirst": return .success(.confirmFirst(on))
            case "replyToGroups": return .success(.replyToGroups(on))
            case "voiceToText": return .success(.voiceToText(on))
            case "outreach": return .success(.outreach(on))
            case "revisit": return .success(.revisit(on))
            case "alerts":
                if on, !s.alertsAvailable { return .failure(Problem(text: "手机提醒还没填地址，要先在设置里填好")) }
                return .success(.alerts(on))
            default: return .failure(Problem(text: "“\(key)”不能用说话改"))
            }
        case "never_reply_add":
            let n = words("names").filter { !s.neverReply.contains($0) }
            guard !n.isEmpty else { return .failure(Problem(text: "这些人已经在不回名单里了")) }
            return .success(.neverReplyAdd(n))
        case "never_reply_remove":
            let n = words("names").filter { s.neverReply.contains($0) }
            guard !n.isEmpty else { return .failure(Problem(text: "不回名单里没有这些人")) }
            return .success(.neverReplyRemove(n))
        default:
            return .failure(Problem(text: "有一项改不了，已跳过"))
        }
    }

    /// A rule by the name the owner (or model) used: its display name, or its hand-over reason.
    static func findRule(_ name: String, in rules: [TriggerRule]) -> TriggerRule? {
        let n = TextMatch.normalize(name)
        guard !n.isEmpty else { return nil }
        return rules.first { TextMatch.normalize($0.displayName) == n }
            ?? rules.first { r in
                if case .handOver(let reason) = r.action { return TextMatch.normalize(reason).contains(n) }
                return false
            }
            ?? rules.first { TextMatch.normalize($0.displayName).contains(n) || n.contains(TextMatch.normalize($0.displayName)) }
    }

    /// The JSON object in a model's answer (it may be wrapped in a code fence or a sentence).
    static func jsonObject(in raw: String) -> [String: Any]? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else { return nil }
        let data = Data(raw[start...end].utf8)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Applying

    /// The rules after the changes (only rule changes are applied here).
    public static func apply(_ changes: [SettingChange], to rules: [TriggerRule]) -> [TriggerRule] {
        var out = rules
        func index(_ name: String) -> Int? {
            guard let r = findRule(name, in: out) else { return nil }
            return out.firstIndex { $0.id == r.id }
        }
        for c in changes {
            switch c {
            case .addWords(let name, let w):
                if let i = index(name) { out[i].keywords += w }
            case .removeWords(let name, let w):
                if let i = index(name) {
                    let drop = Set(w.map(TextMatch.normalize))
                    out[i].keywords.removeAll { drop.contains(TextMatch.normalize($0)) }
                }
            case .newRule(let name, let w, let text):
                let rule = TriggerRule(keywords: w, action: text.map { .sendText($0) } ?? .handOver(reason: name))
                // Hand-over rules go first, so they win over automatic answers.
                if text == nil { out.insert(rule, at: 0) } else { out.append(rule) }
            case .toggleRule(let name, let on):
                if let i = index(name) { out[i].enabled = on }
            default: break
            }
        }
        return out
    }
}

extension TriggerRule {
    /// A short name for the rule: “售后”, “找真人”, “价格表”, or the first word it listens for.
    public var displayName: String {
        switch action {
        case .handOver(let reason):
            guard !reason.isEmpty else { return "交给你处理" }
            var short = reason   // “客人要找真人” → “找真人”, “售后问题” → “售后”
            for prefix in ["客人要", "客人在", "客人"] where short.hasPrefix(prefix) { short = String(short.dropFirst(prefix.count)); break }
            if short.hasSuffix("问题") { short = String(short.dropLast(2)) }
            return short.isEmpty ? reason : short
        case .sendCatalog: return "价格表"
        case .sendText, .sendImage: return keywords.first.map { "问“\($0)”" } ?? "新规则"
        }
    }
}

extension Catalog {
    /// The price table with one item's price changed. Nil when no single row matches.
    public static func settingPrice(csv: String, item: String, spec: String, to price: String) -> String? {
        var rows = csv.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let header = rows.first?.split(separator: ",", omittingEmptySubsequences: false).map({ $0.trimmingCharacters(in: .whitespaces) }),
              let nameCol = header.firstIndex(where: { h in ["品名", "商品", "名称", "产品", "品种"].contains { h.contains($0) } }),
              let priceCol = header.firstIndex(where: { h in ["价格", "单价", "售价"].contains { h.contains($0) } }) else { return nil }
        let specCol = header.firstIndex { $0.contains("规格") }
        var hit: Int?
        for i in rows.indices.dropFirst() {
            let cells = rows[i].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cells.count > max(nameCol, priceCol), cells[nameCol].trimmingCharacters(in: .whitespaces) == item else { continue }
            if let specCol, !spec.isEmpty, specCol < cells.count, cells[specCol].trimmingCharacters(in: .whitespaces) != spec { continue }
            if hit != nil { return nil }   // more than one row: not sure which
            hit = i
        }
        guard let i = hit else { return nil }
        var cells = rows[i].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        cells[priceCol] = price.replacingOccurrences(of: ",", with: "，")
        rows[i] = cells.joined(separator: ",")
        return rows.joined(separator: "\n")
    }
}

/// One line of the talk with 小轻舟.
public struct ChatTurn: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var mine: Bool
    public var text: String
    public var at: Date

    public init(mine: Bool, text: String, at: Date = Date()) {
        self.mine = mine
        self.text = text
        self.at = at
    }
}

/// The talk with 小轻舟, kept on this Mac (the newest 100 lines) so it is still there next time.
public final class ChatLog {
    public static let keep = 100
    public private(set) var turns: [ChatTurn] = []
    private let file: URL

    public init(folder: URL) {
        file = folder.appendingPathComponent("小轻舟对话.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file), let saved = try? dec.decode([ChatTurn].self, from: data) { turns = saved }
    }

    public func append(_ turn: ChatTurn) {
        turns = Array((turns + [turn]).suffix(Self.keep))
        save()
    }

    public func clear() {
        turns = []
        save()
    }

    /// The last `rounds` exchanges (owner + answer each), oldest first, for the model.
    public func recent(rounds: Int) -> [ChatTurn] { Array(turns.suffix(rounds * 2)) }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(turns).write(to: file, options: .atomic)
    }
}
