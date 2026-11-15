import Foundation

/// One remembered message of a customer chat.
public struct StoredMessage: Codable, Equatable {
    public var fromMe: Bool
    public var text: String
    public var seenAt: Date

    public init(fromMe: Bool, text: String, seenAt: Date = Date()) {
        self.fromMe = fromMe
        self.text = text
        self.seenAt = seenAt
    }
}

/// Something the customer asked us to keep for them (“帮我留两箱红富士”).
public struct Reservation: Codable, Equatable, Identifiable {
    public enum Status: String, Codable { case waiting, notified, cancelled }
    public var id = UUID()
    public var item: String            // e.g. “红富士，两箱”
    public var quote: String           // the customer's own words
    public var createdAt: Date
    public var status: Status = .waiting
    public var notifiedAt: Date?

    public init(item: String, quote: String, createdAt: Date = Date()) {
        self.item = item
        self.quote = quote
        self.createdAt = createdAt
    }
}

/// The customer clearly said we may tell them about new things (“有好东西联系我”).
public struct Consent: Codable, Equatable {
    public var interests: String       // what they want to hear about (“水果”, “都可以”)
    public var quote: String           // the customer's own words
    public var grantedAt: Date

    public init(interests: String, quote: String, grantedAt: Date = Date()) {
        self.interests = interests
        self.quote = quote
        self.grantedAt = grantedAt
    }
}

/// Everything remembered about one private chat, kept on this Mac only.
public struct CustomerRecord: Codable, Equatable {
    public var chatID: String          // ChatID ("人|…")
    public var name: String            // chat title as last seen
    public var firstSeen: Date
    public var lastSeen: Date
    public var messages: [StoredMessage]
    public var summary: String = ""     // AI-written key points ("要点")
    public var sinceSummary: Int = 0    // messages added since the summary was written
    /// Permission to contact them first: only for a reservation, or after they asked for news.
    public var reservations: [Reservation] = []
    public var consent: Consent?
    /// When they said not to message them first (“别发了”); this cancels any consent.
    public var optedOutAt: Date?
    /// Their avatar as shown in the chat app, cut from its contact list (file in `avatars/`).
    public var avatarFile: String?
    /// When 主动智能 last greeted them after a quiet spell.
    public var lastRevisitAt: Date?

    public init(chatID: String, name: String, now: Date = Date()) {
        self.chatID = chatID
        self.name = name
        firstSeen = now
        lastSeen = now
        messages = []
    }

    private enum CodingKeys: String, CodingKey {
        case chatID, name, firstSeen, lastSeen, messages, summary, sinceSummary, reservations, consent, optedOutAt,
             avatarFile, lastRevisitAt
    }

    /// Older files lack the newer fields; they load with defaults instead of failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chatID = try c.decode(String.self, forKey: .chatID)
        name = try c.decode(String.self, forKey: .name)
        firstSeen = try c.decode(Date.self, forKey: .firstSeen)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        messages = try c.decodeIfPresent([StoredMessage].self, forKey: .messages) ?? []
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sinceSummary = try c.decodeIfPresent(Int.self, forKey: .sinceSummary) ?? 0
        reservations = try c.decodeIfPresent([Reservation].self, forKey: .reservations) ?? []
        consent = try c.decodeIfPresent(Consent.self, forKey: .consent)
        optedOutAt = try c.decodeIfPresent(Date.self, forKey: .optedOutAt)
        avatarFile = try c.decodeIfPresent(String.self, forKey: .avatarFile)
        lastRevisitAt = try c.decodeIfPresent(Date.self, forKey: .lastRevisitAt)
    }

    /// May we message this customer first about new products? Only with consent, never after an opt-out.
    public var welcomesNews: Bool { consent != nil && optedOutAt == nil }

    /// Should this news go to them: they agreed, and it is about something they said they like
    /// (or they said anything is fine).
    public func wantsNews(about text: String) -> Bool {
        guard welcomesNews, let c = consent else { return false }
        if ["都", "所有", "任何", "什么都"].contains(where: c.interests.contains) { return true }
        // Compare product words, not whole phrases: “新到的水蜜桃” fits “今天到了一批当季水蜜桃”.
        let t = TextMatch.normalize(text)
        let filler: Set<String> = ["新到", "到的", "的梭", "新货", "有新", "东西", "好东", "记得", "告诉", "通知", "以后", "最新"]
        return BM25Index.tokens(c.interests).contains { $0.count >= 2 && !filler.contains($0) && t.contains($0) }
    }
}

public enum MemoryMerge {
    /// Same message read twice (OCR may differ a little; a voice message gains its words later).
    static func same(_ a: StoredMessage, _ b: StoredMessage) -> Bool {
        guard a.fromMe == b.fromMe else { return false }
        let x = TextMatch.normalize(a.text), y = TextMatch.normalize(b.text)
        guard x.count >= 1, y.count >= 1 else { return x == y }
        return TextMatch.similar(x, y) || (min(x.count, y.count) >= 2 && (x.hasPrefix(y) || y.hasPrefix(x)))
    }

    /// Adds the messages now on screen to what was stored, without repeating the ones already
    /// there. The top visible bubble may be cut off, so alignment may skip up to two of them.
    /// Returns the merged list and how many messages are new.
    public static func merge(_ stored: [StoredMessage], visible: [StoredMessage]) -> ([StoredMessage], Int) {
        guard !visible.isEmpty else { return (stored, 0) }
        guard !stored.isEmpty else { return (visible, visible.count) }
        var result = stored
        for skip in 0...min(2, visible.count - 1) {
            let v = Array(visible.dropFirst(skip))
            for k in stride(from: min(stored.count, v.count), through: 1, by: -1) {
                let tail = stored.suffix(k)
                guard zip(tail, v.prefix(k)).allSatisfy({ same($0, $1) }) else { continue }
                // Keep the longer reading (e.g. a voice message that now shows its words).
                for (index, newer) in zip(tail.indices, v.prefix(k)) where newer.text.count > result[index].text.count {
                    result[index].text = newer.text
                }
                let new = Array(v.dropFirst(k))
                return (result + new, new.count)
            }
        }
        // No overlap: the screen shows a different stretch of the chat. Add it as it is.
        return (result + visible, visible.count)
    }
}

/// Stores customer records as JSON files in a folder (one file per chat).
public final class CustomerMemoryStore {
    public let folder: URL
    private var records: [String: CustomerRecord] = [:]   // file name → record
    public static let keep = 500                          // messages kept per customer

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("轻舟助手/客户记忆", isDirectory: true)
    }

    public init(folder: URL = CustomerMemoryStore.defaultFolder) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let r = try? dec.decode(CustomerRecord.self, from: data) {
                records[url.lastPathComponent] = r
            }
        }
    }

    public var count: Int { records.count }

    /// The record of a chat; names read by OCR may differ a little, so they are matched loosely.
    public func record(for chatID: String) -> CustomerRecord? {
        records.values.first { ChatID.same($0.chatID, chatID) }
    }

    /// Remembers what is on screen for this chat. Returns the updated record.
    @discardableResult
    public func remember(chatID: String, name: String, visible: [ChatBubble], now: Date = Date()) -> CustomerRecord {
        let file = fileName(for: chatID)
        var r = records[file] ?? CustomerRecord(chatID: chatID, name: name, now: now)
        let seen = visible.map { StoredMessage(fromMe: $0.fromMe, text: $0.text, seenAt: now) }
        let (merged, added) = MemoryMerge.merge(r.messages, visible: seen)
        guard added > 0 || merged != r.messages || r.messages.isEmpty else { return r }
        r.messages = Array(merged.suffix(Self.keep))
        r.sinceSummary += added
        r.lastSeen = now
        if !name.isEmpty { r.name = name }
        save(r, as: file)
        return r
    }

    /// Older messages read from the chat (读以前的聊天) put in front of what is remembered.
    /// Returns how many were new.
    @discardableResult
    public func addHistory(chatID: String, name: String, messages: [StoredMessage], now: Date = Date()) -> Int {
        let file = fileName(for: chatID)
        var r = records[file] ?? CustomerRecord(chatID: chatID, name: name, now: now)
        let joined = HistoryStitch.stitch(older: messages, newer: r.messages)
        let added = joined.count - r.messages.count
        guard added > 0 else { return 0 }
        r.messages = Array(joined.suffix(Self.keep))
        if r.name.isEmpty { r.name = name }
        save(r, as: file)
        return added
    }

    /// All remembered customers (for the panel).
    public var all: [CustomerRecord] { records.values.sorted { $0.lastSeen > $1.lastSeen } }

    /// Changes a customer's record (creating it if needed) and saves it.
    @discardableResult
    public func update(chatID: String, name: String, _ change: (inout CustomerRecord) -> Void) -> CustomerRecord {
        let file = fileName(for: chatID)
        var r = records[file] ?? CustomerRecord(chatID: chatID, name: name)
        if !name.isEmpty { r.name = name }
        change(&r)
        save(r, as: file)
        return r
    }

    /// Saves a customer's avatar picture next to their record.
    public func saveAvatar(_ png: Data, for chatID: String, name: String) {
        let dir = folder.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = fileName(for: chatID).replacingOccurrences(of: ".json", with: ".png")
        guard (try? png.write(to: dir.appendingPathComponent(file))) != nil else { return }
        update(chatID: chatID, name: name) { $0.avatarFile = file }
    }

    public func avatarURL(of record: CustomerRecord) -> URL? {
        record.avatarFile.map { folder.appendingPathComponent("avatars", isDirectory: true).appendingPathComponent($0) }
    }

    public func setSummary(_ summary: String, for chatID: String) {
        let file = fileName(for: chatID)
        guard var r = records[file] else { return }
        r.summary = summary
        r.sinceSummary = 0
        save(r, as: file)
    }

    /// Remembered messages from before what is on screen now (most recent `limit`).
    public static func earlier(in record: CustomerRecord, visible: [ChatBubble], limit: Int = 30) -> [StoredMessage] {
        let seen = visible.map { StoredMessage(fromMe: $0.fromMe, text: $0.text) }
        guard let first = seen.dropFirst(seen.count > 1 ? 1 : 0).first,
              let at = record.messages.lastIndex(where: { MemoryMerge.same($0, first) }) else {
            return Array(record.messages.suffix(limit))
        }
        let cut = seen.count > 1 ? max(0, at - 1) : at   // the top visible bubble may be cut off
        return Array(record.messages[..<cut].suffix(limit))
    }

    private func fileName(for chatID: String) -> String {
        if let existing = records.first(where: { ChatID.same($0.value.chatID, chatID) }) { return existing.key }
        let safe = chatID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return "\(safe.prefix(60))-\(UUID().uuidString.prefix(8)).json"
    }

    private func save(_ r: CustomerRecord, as file: String) {
        records[file] = r
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(r) { try? data.write(to: folder.appendingPathComponent(file)) }
    }
}
