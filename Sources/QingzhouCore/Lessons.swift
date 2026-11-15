import Foundation

/// What the shop owner taught the assistant through drafts (辅助模式): a reply they rewrote
/// before sending, one they liked, or one they turned down and why.
public struct Lesson: Codable, Equatable {
    /// `ownerSaid`: the owner answered a customer himself (a chat handed to him); `final` is what he wrote.
    public enum Kind: String, Codable { case rewritten, liked, rejected, ownerSaid }
    public var kind: Kind
    public var question: String     // what the customer said
    public var draft: String        // what the assistant wrote
    public var final: String?       // what the owner sent instead
    public var reason: String?      // why it was turned down
    public var at: Date

    public init(kind: Kind, question: String, draft: String, final: String? = nil, reason: String? = nil,
                at: Date = Date()) {
        self.kind = kind
        self.question = question
        self.draft = draft
        self.final = final
        self.reason = reason
        self.at = at
    }
}

/// Keeps the newest lessons in one JSON file on this Mac.
public final class LessonStore {
    public static let keep = 200
    public private(set) var lessons: [Lesson] = []
    private let file: URL

    public init(folder: URL) {
        file = folder.appendingPathComponent("lessons.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file), let saved = try? dec.decode([Lesson].self, from: data) {
            lessons = saved
        }
    }

    public func add(_ lesson: Lesson) {
        lessons = Array((lessons + [lesson]).suffix(Self.keep))
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        try? enc.encode(lessons).write(to: file, options: .atomic)
    }

    /// The lessons to show for this customer message: the ones about the most similar questions
    /// first (old ones too), then the newest ("" when there are none).
    public func promptText(for question: String = "", limit: Int = 6) -> String {
        let asked = Self.pairs(question)
        let ranked = lessons.enumerated().map { (i, l) in (lesson: l, score: Self.overlap(asked, Self.pairs(l.question)), age: i) }
        let alike = ranked.filter { $0.score >= 0.25 }.sorted { ($0.score, $0.age) > ($1.score, $1.age) }.prefix(limit)
        let newest = ranked.reversed().filter { r in !alike.contains { $0.age == r.age } }.prefix(limit - alike.count)
        let lines = (alike + newest).map(\.lesson).map { l -> String in
            let q = "客户说“\(l.question.prefix(40))”"
            switch l.kind {
            case .rewritten: return "- \(q)，我原本想回“\(l.draft.prefix(60))”，店主改成了“\((l.final ?? "").prefix(80))”"
            case .liked: return "- \(q)，店主觉得这样回很好：“\(l.draft.prefix(80))”"
            case .ownerSaid: return "- \(q)，店主自己是这样回的：“\((l.final ?? "").prefix(80))”"
            case .rejected: return "- \(q)，店主不喜欢这样回：“\(l.draft.prefix(60))”" + (l.reason.map { "，原因：\($0)" } ?? "")
            }
        }
        guard !lines.isEmpty else { return "" }
        return "【店主教过的说法】客户问的是同一类事时，照店主的意思和说法回，不要再说“我确认一下”（这是店主的原话，不算编造）。里面的价格和数字不要照搬，价格、库存、时间等事实仍以知识库为准。\n" + lines.joined(separator: "\n")
    }

    /// Neighbouring characters of a text, to tell how alike two questions are.
    private static func pairs(_ text: String) -> Set<String> {
        let c = Array(TextMatch.normalize(text))
        guard c.count > 1 else { return [] }
        return Set((0..<c.count - 1).map { String(c[$0...$0 + 1]) })
    }

    /// Share of the smaller set that both have (0 when either is empty).
    private static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }
}
