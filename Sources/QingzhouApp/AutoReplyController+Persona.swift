import Foundation
import QingzhouCore

/// What “从我的聊天学” proposes; it is only used once the owner says so.
struct LearnedPersona: Equatable {
    let text: String
    let fromChats: Int
    let fromImport: Int
    var total: Int { fromChats + fromImport }
}

enum PersonaLearnError: LocalizedError {
    case noSamples
    case emptyAnswer

    var errorDescription: String? {
        switch self {
        case .noSamples: return "还没有你的聊天记录，先开自动回复一段时间，或导入聊天记录"
        case .emptyAnswer: return "模型没有写出人设，再试一次"
        }
    }
}

/// 店铺人设和话术: learning how the owner talks from the messages they sent themselves.
extension AutoReplyController {
    /// The owner's own messages in remembered chats, newest first. People on the 不自动回复 list
    /// are left out, and so is what the assistant wrote this session.
    func ownMessages() -> [String] {
        let kinds: Set<Activity.Kind> = [.replied, .outreach, .drafted]
        let written = activity.filter { kinds.contains($0.kind) }.map(\.detail)
            + (UserDefaults.standard.stringArray(forKey: Self.sentKey) ?? [])
        return PersonaSamples.fromChats(memory.all.filter { !isNeverReply($0.name) }, excluding: written)
    }

    private static let sentKey = "assistantSentTexts"

    /// Remembers what the assistant itself sent (the newest 500), so “从我的聊天学” learns only
    /// the owner's own words, also after a restart.
    func noteAssistantSent(_ text: String) {
        guard Self.saveSettings else { return }
        let list = (UserDefaults.standard.stringArray(forKey: Self.sentKey) ?? []) + [text]
        UserDefaults.standard.set(Array(list.suffix(500)), forKey: Self.sentKey)
    }

    /// Asks the model for 店铺人设和话术 learned from the owner's messages and imported lines,
    /// improving the current one if there is one. Nothing is saved here.
    func learnPersona(imported: [String]) async throws -> LearnedPersona {
        let samples = PersonaSamples.combine(imported: imported, chats: ownMessages())
        guard !samples.lines.isEmpty else { throw PersonaLearnError.noSamples }
        add(.info, "从你发过的 \(samples.lines.count) 条消息学说话方式…")
        do {
            let prompt = PromptBuilder.learnStyle(samples: samples.lines, existing: options.persona)
            let raw = try await makeEngine().reply(to: prompt)
            let text = PersonaSamples.cleanAnswer(raw.text)
            guard !text.isEmpty else { throw PersonaLearnError.emptyAnswer }
            add(.info, "学好了店铺人设，等你确认后才用：\(text.prefix(40))")
            return LearnedPersona(text: text, fromChats: samples.fromChats, fromImport: samples.fromImport)
        } catch {
            add(.error, "学说话方式没成功：\(error.localizedDescription)")
            throw error
        }
    }

    /// Reads a chat export the owner picked; its lines join the next learning.
    func importChatExport(_ url: URL) throws -> [String] {
        do {
            let lines = try PersonaSamples.readExport(at: url)
            add(.info, "导入聊天记录「\(url.lastPathComponent)」：\(lines.count) 条")
            return lines
        } catch {
            add(.warn, "导入聊天记录「\(url.lastPathComponent)」没成功：\(error.localizedDescription)")
            throw error
        }
    }
}
