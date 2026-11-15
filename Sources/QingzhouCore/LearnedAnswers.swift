import Foundation

/// A question the assistant could not answer and what the owner wrote back. It goes into the
/// knowledge base only after the owner approves it on 首页. While `answer` is empty the owner
/// has not replied yet (the assistant is still waiting for it).
public struct AnswerSuggestion: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var chat: String       // ChatID
    public var who: String
    public var question: String
    public var answer: String = ""
    public var at: Date
    /// True for a chat handed to the owner by a rule (讲价, 售后…): what is learned is his wording,
    /// not a fact for the knowledge base. Nil in files saved before this was added.
    public var manner: Bool?

    public init(chat: String, who: String, question: String, at: Date = Date(), manner: Bool = false) {
        self.chat = chat
        self.who = who
        self.question = question
        self.at = at
        self.manner = manner ? true : nil
    }

    public var isManner: Bool { manner == true }

    public var isReady: Bool { !answer.isEmpty }
}

public enum OwnerAnswer {
    /// Short words that carry no knowledge (“好的”“稍等”), and pictures, stickers and voice.
    private static let filler: Set<String> = ["好", "好的", "嗯", "嗯嗯", "哦", "收到", "ok", "OK", "稍等", "稍等一下",
                                              "等一下", "我看看", "我查一下", "我问一下", "图片", "表情"]

    /// Words that promise money or goods; an answer with one of them, or with any number, is not
    /// learned by itself.
    private static let promises = ["退", "赔", "补", "送", "免", "包邮", "抹", "优惠", "便宜", "折", "减", "降", "算你", "给你算"]

    /// True when the owner should look before this is learned: it names a number or promises
    /// something (a price for one customer must not become what every customer is told).
    public static func needsApproval(_ answer: String) -> Bool {
        answer.contains(where: \.isNumber) || "一二两三四五六七八九十半".contains(where: { n in
            ["块", "元", "斤", "只", "条", "折"].contains { answer.contains("\(n)\($0)") }
        }) || promises.contains { answer.contains($0) }
    }

    /// What the owner wrote back to `question`: their own messages after it, up to the customer's
    /// next message, leaving out what the assistant itself sent. Nil when there is nothing yet.
    public static func find(question: String, in messages: [StoredMessage], assistantSent: [String]) -> String? {
        let asked = StoredMessage(fromMe: false, text: question.components(separatedBy: " / ").last ?? question)
        guard let i = messages.lastIndex(where: { !$0.fromMe && MemoryMerge.same($0, asked) }) else { return nil }
        let sent = assistantSent.map(TextMatch.normalize).filter { !$0.isEmpty }
        var lines: [String] = []
        for m in messages[(i + 1)...] {
            guard m.fromMe else { break }
            let n = TextMatch.normalize(m.text)
            if n.isEmpty || filler.contains(n) || m.text.hasPrefix("[语音") { continue }
            if sent.contains(where: { $0 == n || $0.contains(n) }) { continue }
            lines.append(m.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// Questions waiting for the owner's answer, and answers waiting for approval, in one JSON file.
public final class AnswerSuggestionStore {
    public static let keep = 50
    public private(set) var items: [AnswerSuggestion] = []
    private let file: URL

    public init(folder: URL) {
        file = folder.appendingPathComponent("待确认的问答.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file), let saved = try? dec.decode([AnswerSuggestion].self, from: data) {
            items = saved
        }
    }

    /// Starts waiting for the owner's answer to a question. A chat waits for one question at a
    /// time: a newer one replaces an older one that got no answer.
    public func watch(chat: String, who: String, question: String, manner: Bool = false) {
        let kept = items.filter { !(ChatID.same($0.chat, chat) && !$0.isReady) }
        items = Array((kept + [AnswerSuggestion(chat: chat, who: who, question: question, manner: manner)]).suffix(Self.keep))
        save()
    }

    /// Questions in this chat still waiting for an answer.
    public func waiting(in chat: String) -> [AnswerSuggestion] {
        items.filter { ChatID.same($0.chat, chat) && !$0.isReady }
    }

    /// Everything in this chat not yet approved: the owner may still be adding to an answer.
    public func open(in chat: String) -> [AnswerSuggestion] {
        items.filter { ChatID.same($0.chat, chat) }
    }

    public func setAnswer(_ answer: String, for id: UUID) {
        items = items.map { s in
            guard s.id == id else { return s }
            var updated = s
            updated.answer = answer
            return updated
        }
        save()
    }

    public func remove(_ id: UUID) {
        items = items.filter { $0.id != id }
        save()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        try? enc.encode(items).write(to: file, options: .atomic)
    }
}

/// The knowledge file the approved questions and answers are added to.
public enum LearnedQA {
    public static let fileName = "从我的回复学的问答.csv"

    /// Adds one row (问题,回答) to the file in the knowledge folder, creating it when missing.
    public static func append(question: String, answer: String, to folder: URL) throws {
        let url = folder.appendingPathComponent(fileName)
        let row = cell(question) + "," + cell(answer) + "\n"
        guard let old = try? String(contentsOf: url, encoding: .utf8) else {
            try ("问题,回答\n" + row).write(to: url, atomically: true, encoding: .utf8)
            return
        }
        try (old + (old.hasSuffix("\n") || old.isEmpty ? "" : "\n") + row).write(to: url, atomically: true, encoding: .utf8)
    }

    /// The knowledge files split rows at commas and line breaks, so a cell must hold neither.
    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: "，")
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "；")
    }
}
