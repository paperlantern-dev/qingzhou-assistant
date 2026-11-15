import Foundation

/// A ready-made 店铺人设和话术 to start from; the owner edits it to fit the shop.
public struct PersonaTemplate: Identifiable, Equatable {
    public let name: String
    public let text: String
    public var id: String { name }
}

/// Ready-made personas. Each keeps the owner's rules: only reply, never chase customers, and
/// facts (prices, stock) only from the knowledge base.
public enum PersonaTemplates {
    public static let all: [PersonaTemplate] = [fresh, onlineShop, fruitSnacks, localBooking]

    static let fresh = PersonaTemplate(name: "生鲜小店", text: """
    我们是生鲜小店，替店主回客户消息。
    称呼客户用“你”，亲切、实在，像熟人聊天。
    一次回一两句，短一点，像手机上随手打字。
    不夸大、不打包票，不说“最新鲜”“绝对不坏”这类话。
    只回客户问的，不追单、不催单；客户说再想想，就回“好的，有需要随时找我”。
    可以提醒保存和吃法；价格、库存、发货时间只按知识库说。
    客户讲价、问能不能便宜：客气地婉拒，说已经是实在价了；不要说“确认一下”，也不要自己答应优惠。
    客户不满意或投诉，先道歉，说马上帮你核实；怎么赔、怎么退由店主定，不要自己答应。
    """)

    static let onlineShop = PersonaTemplate(name: "通用网店客服", text: """
    替店主回买家消息，像网店里耐心的客服。
    称呼买家用“你”，礼貌、简短，不说太客套的长句。
    先回答买家问的那件事，一次一两句。
    商品参数、价格、优惠、发货时间只按知识库说，没有就说“我确认一下再回复你”。
    不夸大效果，不承诺知识库里没有的东西。
    不催单、不追问；买家说再看看，就回“好的，有需要随时找我”。
    退换货和投诉先道歉，说会尽快处理，具体方案交给店主。
    """)

    static let fruitSnacks = PersonaTemplate(name: "水果零食店", text: """
    我们是水果零食小店，语气轻松热情，可以带“呀”“哈”。
    称呼客户用“你”，一次一两句，像朋友推荐。
    可以说口感、吃法和保存方法，但不夸大，不说“包甜”“全网最低”。
    价格、规格、产地、发货时间只按知识库说。
    不催单、不追问；客户说再想想，就回“好的，想吃随时找我呀”。
    坏果、少发、不好吃，先道歉，请对方拍张照片，怎么处理交给店主。
    """)

    static let localBooking = PersonaTemplate(name: "本地预约服务", text: """
    我们做本地预约服务（到店或上门），替店主回客户消息。
    称呼客户用“你”，耐心、专业、简短。
    客户想约时间，先问清哪天、几点、几位，再按知识库里的营业时间回答。
    价格和能不能约上只按知识库说，拿不准就说“我确认一下再回复你”，不要自己定时间。
    不催客户下单，不反复推荐套餐。
    改约、取消、投诉先道歉，说会尽快安排，交给店主处理。
    """)
}

/// Picking the owner's own messages to learn how they talk (店铺人设和话术 → 从我的聊天学).
public enum PersonaSamples {
    public static let maxFromChats = 120          // messages taken from remembered chats
    public static let maxImportLines = 300        // lines taken from a chat export
    public static let maxImportBytes = 200 * 1024 // only the end of a bigger export is read
    public static let maxLength = 120             // characters kept of one message

    /// Messages from two sources, without repeats.
    public struct Picked: Equatable {
        public let lines: [String]
        public let fromImport: Int
        public var fromChats: Int { lines.count - fromImport }
    }

    public enum ExportError: LocalizedError, Equatable {
        case unreadable(String)
        case notText
        case empty

        public var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "打不开这个文件：\(why)"
            case .notText: return "这个文件不是文字，请导出成 txt 或 csv 再试"
            case .empty: return "文件里没有找到可以学的聊天文字"
            }
        }
    }

    // MARK: Remembered chats

    /// The owner's own messages (fromMe) in remembered chats, newest first: no one-word answers,
    /// placeholders or bare numbers, no repeats, and none of `written` (what the assistant sent
    /// itself; a message counts as written when it shows up inside one of those texts).
    public static func fromChats(_ records: [CustomerRecord], excluding written: [String] = [],
                                 limit: Int = maxFromChats) -> [String] {
        let assistant = written.map(TextMatch.normalize).filter { !$0.isEmpty }
        var mine: [(at: Date, order: Int, text: String)] = []
        for r in records {
            for m in r.messages where m.fromMe { mine.append((m.seenAt, mine.count, m.text)) }
        }
        // Messages first seen together keep their chat order: the later one is newer.
        mine.sort { $0.at != $1.at ? $0.at > $1.at : $0.order > $1.order }
        var seen = Set<String>()
        var picked: [String] = []
        for m in mine {
            guard picked.count < limit else { break }
            guard let text = HistoryClean.learnable(m.text) else { continue }   // nothing private
            let key = TextMatch.normalize(text)
            guard !assistant.contains(where: { $0.contains(key) }), seen.insert(key).inserted else { continue }
            picked.append(text)
        }
        return picked
    }

    /// Imported lines first (the owner chose them), then chat messages; no repeats, at most `limit`.
    public static func combine(imported: [String], chats: [String], limit: Int = maxImportLines) -> Picked {
        var seen = Set<String>()
        var lines: [String] = []
        var fromImport = 0
        for (i, text) in (imported + chats).enumerated() where lines.count < limit {
            let key = TextMatch.normalize(text)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            lines.append(text)
            if i < imported.count { fromImport += 1 }
        }
        return Picked(lines: lines, fromImport: fromImport)
    }

    /// The model's answer as a persona: plain lines, without code fences or blank lines.
    public static func cleanAnswer(_ raw: String) -> String {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") }
            .joined(separator: "\n")
    }

    /// One message as a sample: on one line, at most `maxLength` characters. nil when it tells
    /// nothing about how one talks (“嗯”, “[图片]”, “280”).
    static func sample(_ raw: String) -> String? {
        let text = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let key = TextMatch.normalize(text)
        guard key.count >= 2, key.unicodeScalars.contains(where: isChinese),
              text.range(of: #"^\[[^\]]{1,10}\]$"#, options: .regularExpression) == nil else { return nil }
        return String(text.prefix(maxLength))
    }

    private static func isChinese(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
    }

    // MARK: Chat exports

    /// Reads a chat export the owner picked (.txt / .md / .csv): at most its last `maxImportBytes`,
    /// the newest part of a long export.
    public static func readExport(at url: URL) throws -> [String] {
        let data: Data
        do {
            data = try tail(of: url, limit: maxImportBytes)
        } catch {
            throw ExportError.unreadable(error.localizedDescription)
        }
        guard let text = decode(data) else { throw ExportError.notText }
        let lines = fromExport(text)
        guard !lines.isEmpty else { throw ExportError.empty }
        return lines
    }

    /// The owner's lines in a chat export: those marked “我：…” (marker removed) when there are
    /// any, else every line. Useful lines only, no repeats, the last `limit` (newest) of the file.
    public static func fromExport(_ text: String, limit: Int = maxImportLines) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        let marked = lines.compactMap(ownLine)
        var seen = Set<String>()
        let picked = (marked.isEmpty ? lines : marked).compactMap(sample).filter {
            seen.insert(TextMatch.normalize($0)).inserted
        }
        return Array(picked.suffix(limit))
    }

    /// “我：好的”, “我 : 好的”, or in Markdown “- 我：好的” / “**我**：好的” → “好的”; nil for anyone else's line.
    static func ownLine(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        let mark = #"^(?:[-*>•]\s*)?(?:\*\*)?我(?:\*\*)?\s*[：:]\s*(?:\*\*)?"#
        guard let marker = t.range(of: mark, options: .regularExpression) else { return nil }
        return String(t[marker.upperBound...])
    }

    /// The text of an export: UTF-8 (BOM dropped) or GB18030, which Windows tools often write.
    /// nil for anything that is not text.
    public static func decode(_ data: Data) -> String? {
        guard !data.contains(0),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb18030) else { return nil }
        return text.unicodeScalars.first == "\u{FEFF}" ? String(text.unicodeScalars.dropFirst()) : text
    }

    private static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    /// The last `limit` bytes of a file, from the start of a whole line (the cut may split a character).
    static func tail(of url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size > UInt64(limit) else {
            try handle.seek(toOffset: 0)
            return try handle.readToEnd() ?? Data()
        }
        try handle.seek(toOffset: size - UInt64(limit))
        let data = try handle.readToEnd() ?? Data()
        guard let newline = data.firstIndex(of: 0x0A) else { return Data() }
        return Data(data[(newline + 1)...])
    }
}
