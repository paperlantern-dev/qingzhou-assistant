import AppKit
import Foundation
import PDFKit

/// One searchable passage from a knowledge file.
public struct KnowledgeChunk: Identifiable, Equatable {
    public let id: Int
    public let source: String   // file name
    public let text: String
}

public struct KnowledgeBase {
    public let folder: URL
    public let files: [String]
    public let chunks: [KnowledgeChunk]
    public let skipped: [String]       // files that could not be read
    public let signature: String       // changes when any file changes
    let index: BM25Index

    public var isEmpty: Bool { chunks.isEmpty }

    public static let supportedExtensions: Set<String> = ["txt", "md", "markdown", "csv", "pdf", "docx", "doc", "rtf"]

    /// Reads every supported file in the folder (not recursive into hidden files).
    public static func load(folder: URL) -> KnowledgeBase {
        let fm = FileManager.default
        let urls = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                 options: [.skipsHiddenFiles])) ?? [])
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var chunks: [KnowledgeChunk] = []
        var files: [String] = []
        var skipped: [String] = []
        for url in urls {
            guard let text = readText(url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                skipped.append(url.lastPathComponent)
                continue
            }
            files.append(url.lastPathComponent)
            let pieces = url.pathExtension.lowercased() == "csv" ? csvRows(text) : split(text)
            for p in pieces {
                chunks.append(KnowledgeChunk(id: chunks.count + 1, source: url.lastPathComponent, text: p))
            }
        }
        return KnowledgeBase(folder: folder, files: files, chunks: chunks, skipped: skipped,
                             signature: signature(folder: folder), index: BM25Index(chunks.map(\.text)))
    }

    /// Cheap fingerprint of file names, sizes and modification dates.
    public static func signature(folder: URL) -> String {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.map { u -> String in
            let v = try? u.resourceValues(forKeys: Set(keys))
            return "\(u.lastPathComponent)|\(v?.fileSize ?? 0)|\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        .sorted().joined(separator: ";")
    }

    /// Top matches for a question. Only passages sharing real terms with it are returned.
    public func search(_ query: String, limit: Int = 4) -> [(chunk: KnowledgeChunk, score: Double)] {
        index.search(query, limit: limit).map { (chunks[$0.doc], $0.score) }
    }

    /// Up to this many characters, the model reads the whole knowledge base for every question:
    /// it can then sum up (“有什么产品” → the full price list) and link facts across files.
    static let wholeLimit = 8000

    /// What the model reads for a question. A small knowledge base goes along whole. A big one:
    /// the best matches, and for list questions (“有什么产品”“价格表”) every product row too,
    /// since such questions share no words with the rows themselves.
    public func passages(for query: String) -> [KnowledgeChunk] {
        if chunks.reduce(0, { $0 + $1.text.count }) <= Self.wholeLimit { return chunks }
        var picked = search(query, limit: 6).map(\.chunk)
        if Self.asksForList(query) {
            var room = Self.wholeLimit / 2
            for c in chunks where Self.isProduct(c) && !picked.contains(c) && room >= c.text.count {
                picked.append(c)
                room -= c.text.count
            }
        }
        return picked
    }

    private static let listWords = ["什么产品", "什么商品", "什么货", "哪些", "卖什么", "卖啥", "卖些", "有啥", "有什么",
                                    "都有", "价格表", "价目", "报价", "菜单", "清单", "目录", "产品", "商品", "推荐"]

    static func asksForList(_ query: String) -> Bool { listWords.contains { query.contains($0) } }

    /// A row of the product list: from a table, or a passage with a price in it.
    static func isProduct(_ chunk: KnowledgeChunk) -> Bool {
        (chunk.source.lowercased().hasSuffix(".csv") && chunk.source != LearnedQA.fileName) || chunk.text.range(of: #"\d+\s*元"#, options: .regularExpression) != nil
    }

    // MARK: - Reading files

    static func readText(_ url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return PDFDocument(url: url)?.string
        case "docx", "doc", "rtf":
            return (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        default:
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
            let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            return try? String(contentsOf: url, encoding: String.Encoding(rawValue: gb))
        }
    }

    /// Splits by blank lines / headings into passages of at most ~400 characters.
    static func split(_ text: String, maxLength: Int = 400) -> [String] {
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var result: [String] = []
        var current = ""
        for p in paragraphs {
            let isHeading = p.hasPrefix("#")
            if !current.isEmpty, isHeading || current.count + p.count > maxLength {
                result.append(current)
                current = ""
            }
            if p.count > maxLength {
                var rest = Substring(p)
                while !rest.isEmpty {
                    result.append(String(rest.prefix(maxLength)))
                    rest = rest.dropFirst(maxLength)
                }
            } else {
                current += current.isEmpty ? p : "\n" + p
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Each CSV row (e.g. question,answer) becomes one passage; the header row labels it.
    static func csvRows(_ text: String) -> [String] {
        let rows = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n").map(String.init)
        guard let header = rows.first else { return [] }
        let names = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return rows.dropFirst().compactMap { row in
            let cells = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let parts = cells.enumerated().map { i, c in i < names.count ? "\(names[i])：\(c)" : c }
            let joined = parts.joined(separator: "；").trimmingCharacters(in: .whitespaces)
            return joined.isEmpty ? nil : joined
        }
    }
}

// MARK: - Local search (BM25 over Chinese character pairs + latin/number words)

struct BM25Index {
    private let docs: [[String: Int]]
    private let lengths: [Double]
    private let df: [String: Int]
    private let avgLength: Double

    init(_ texts: [String]) {
        docs = texts.map { Self.counts(Self.tokens($0)) }
        lengths = docs.map { Double($0.values.reduce(0, +)) }
        avgLength = lengths.isEmpty ? 1 : max(1, lengths.reduce(0, +) / Double(lengths.count))
        var df: [String: Int] = [:]
        for d in docs { for t in d.keys { df[t, default: 0] += 1 } }
        self.df = df
    }

    func search(_ query: String, limit: Int) -> [(doc: Int, score: Double)] {
        let terms = Set(Self.tokens(query))
        let n = Double(docs.count)
        let k1 = 1.4, b = 0.75
        var scored: [(Int, Double)] = []
        for i in docs.indices {
            var s = 0.0
            for t in terms {
                guard let count = docs[i][t], let dft = df[t] else { continue }
                let tf = Double(count)
                let dfd = Double(dft)
                let idf: Double = log(1.0 + (n - dfd + 0.5) / (dfd + 0.5))
                let norm: Double = k1 * (1.0 - b + b * lengths[i] / avgLength)
                s += idf * tf * (k1 + 1.0) / (tf + norm)
            }
            scored.append((i, s))
        }
        return scored.filter { $0.1 > 0.5 }.sorted { $0.1 > $1.1 }.prefix(limit).map { (doc: $0.0, score: $0.1) }
    }

    /// Words a question shares with a passage. Chinese has no spaces, so overlapping
    /// character pairs are used ("发货时间" → 发货, 货时, 时间).
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var han: [Character] = []
        var word = ""
        func flushHan() {
            if han.count == 1 { out.append(String(han[0])) }
            for i in 0..<max(0, han.count - 1) { out.append(String(han[i...i + 1])) }
            han.removeAll()
        }
        func flushWord() { if !word.isEmpty { out.append(word.lowercased()); word = "" } }
        for ch in text {
            if ch.unicodeScalars.allSatisfy({ (0x4E00...0x9FFF).contains($0.value) }) {
                flushWord(); han.append(ch)
            } else if ch.isLetter || ch.isNumber {
                flushHan(); word.append(ch)
            } else {
                flushHan(); flushWord()
            }
        }
        flushHan(); flushWord()
        return out.filter { !stopwords.contains($0) }
    }

    private static let stopwords: Set<String> = [
        "你们", "我们", "请问", "一下", "什么", "怎么", "可以", "吗", "的", "了", "是", "我", "你", "有", "在",
        "好的", "谢谢", "那能", "能开", "另外", "问一", "想问", "这个", "那个",
    ]

    private static func counts(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}

/// Bringing files into the knowledge folder (picked or dragged in).
public enum KnowledgeImport {
    /// Whether a file can be read as knowledge.
    public static func isSupported(_ url: URL) -> Bool {
        KnowledgeBase.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// The name to save a file under: its own, or “name 2.ext”, “name 3.ext”… when taken.
    public static func destinationName(for name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !existing.contains(candidate) { return candidate }
            n += 1
        }
    }
}
