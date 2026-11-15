import Foundation
import QingzhouCore

/// The knowledge base: where it lives, loading it, and the “试问一句” test.
extension AutoReplyController {
    /// The folder the user picked last time; else `<project>/knowledge` next to the build folder;
    /// else (the downloaded app) `~/Documents/轻舟助手知识库`, started from the samples in the app.
    static var defaultKBFolder: URL {
        if let saved = UserDefaults.standard.string(forKey: "kbFolder") { return URL(fileURLWithPath: saved) }
        let fm = FileManager.default
        let project = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("knowledge")
        if fm.fileExists(atPath: project.path) { return project }
        let mine = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/轻舟助手知识库")
        if !fm.fileExists(atPath: mine.path), let samples = Bundle.main.resourceURL?.appendingPathComponent("示例知识库"),
           fm.fileExists(atPath: samples.path) {
            try? fm.copyItem(at: samples, to: mine)   // no samples copied = an empty knowledge base, shown as such
        }
        return mine
    }

    func setKBFolder(_ url: URL) {
        kbFolder = url
        UserDefaults.standard.set(url.path, forKey: "kbFolder")
        reloadKB()
    }

    func reloadKB() {
        let loaded = KnowledgeBase.load(folder: kbFolder)
        kb = loaded
        add(.info, "知识库已加载：\(loaded.files.count) 个文件，\(loaded.chunks.count) 段"
            + (loaded.skipped.isEmpty ? "" : "（无法读取：\(loaded.skipped.joined(separator: "、"))）"))
    }

    /// Reloads when any file in the folder was added, removed or edited.
    func ensureKBFresh() {
        if kb == nil || kb?.signature != KnowledgeBase.signature(folder: kbFolder) { reloadKB() }
    }

    /// Answers one typed question with the knowledge base, without sending anything.
    func askTest(_ question: String) async -> (hits: [(chunk: KnowledgeChunk, score: Double)], reply: ParsedReply?, error: String?) {
        ensureKBFresh()
        guard let kb, !kb.isEmpty else { return ([], nil, "知识库为空") }
        let hits = kb.passages(for: question).map { (chunk: $0, score: 0.0) }
        let conv = Conversation(bubbles: [ChatBubble(fromMe: false, text: question, top: 0)])
        do {
            let raw = try await makeEngine().reply(to: PromptBuilder.build(conversation: conv, knowledge: hits.map(\.chunk),
                                                                           lessons: lessons.promptText(for: question),
                                                                           persona: replyPersona))
            guard let parsed = ReplyParser.parse(raw.text, allowed: Set(hits.map(\.chunk.id))) else {
                return (hits, nil, "模型没有按格式回答：\(raw.text)")
            }
            return (hits, parsed, nil)
        } catch {
            return (hits, nil, error.localizedDescription)
        }
    }

}

/// 知识库 tab: adding files, and what the page shows about each one.
extension AutoReplyController {
    /// Copies files into the knowledge folder (never over one already there) and reloads.
    /// Returns how many were added.
    @discardableResult
    func addKnowledgeFiles(_ urls: [URL]) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: kbFolder, withIntermediateDirectories: true)
        var existing = Set((try? fm.contentsOfDirectory(atPath: kbFolder.path)) ?? [])
        var added = 0
        for url in urls {
            guard KnowledgeImport.isSupported(url) else {
                add(.warn, "「\(url.lastPathComponent)」不是能读的文件（支持 txt、md、csv、pdf、docx）")
                continue
            }
            let name = KnowledgeImport.destinationName(for: url.lastPathComponent, existing: existing)
            do {
                try fm.copyItem(at: url, to: kbFolder.appendingPathComponent(name))
                existing.insert(name)
                added += 1
            } catch {
                add(.error, "没能加进知识库「\(url.lastPathComponent)」：\(error.localizedDescription)")
            }
        }
        if added > 0 {
            reloadKB()
            add(.info, "加进知识库 \(added) 个文件")
        }
        return added
    }

    /// When a knowledge file was last changed.
    func modified(_ file: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: kbFolder.appendingPathComponent(file).path))?[.modificationDate] as? Date
    }

    /// Number of items in a price table (0 when the file is not one).
    func priceItems(in file: String) -> Int {
        guard file.lowercased().hasSuffix(".csv"),
              let text = try? String(contentsOf: kbFolder.appendingPathComponent(file), encoding: .utf8) else { return 0 }
        return Catalog.items(csv: text).count
    }
}
