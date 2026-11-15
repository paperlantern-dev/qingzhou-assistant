import AppKit
import QingzhouCore
import SwiftUI
import UniformTypeIdentifiers

/// What the persona card is busy with, kept outside the view so switching tabs loses nothing.
@MainActor
final class PersonaWork: ObservableObject {
    static let shared = PersonaWork()
    @Published var learning = false
    @Published var proposal: LearnedPersona?
    @Published var draft = ""                   // the proposal, as the owner edits it
    @Published var problem: String?
    @Published var imported: [String] = []      // lines from chat exports, used when learning
}

/// 店铺人设和话术: how the assistant talks. Written by the owner, started from a template, or
/// learned from the owner's own messages; facts still come only from the knowledge base.
struct PersonaCard: View {
    @EnvironmentObject var ctl: AutoReplyController
    @ObservedObject private var work = PersonaWork.shared
    @State private var replacing: PersonaTemplate?
    @State private var askReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "店铺人设和话术")
            CardBox {
                Text("AI 回复时会照着做；价格等事实仍以知识库为准")
                    .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
                editor
                actions
                if work.learning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在学你的说话方式…").font(.system(size: 12)).foregroundStyle(Theme.sub)
                    }
                }
                if let problem = work.problem {
                    Text(problem).font(.system(size: 12)).foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let proposal = work.proposal { proposalBox(proposal) }
            }
        }
        .alert("换成「\(replacing?.name ?? "")」模板？", isPresented: $askReplace, presenting: replacing) { t in
            Button("替换") { ctl.options.persona = t.text }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("现在写的人设会被替换掉。")
        }
    }

    // MARK: The persona

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $ctl.options.persona)
                .font(.system(size: 14)).scrollContentBackground(.hidden)
                .frame(height: 96).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.neutralSoft))
                .overlay(alignment: .topLeading) {
                    if ctl.options.persona.isEmpty {
                        Text("比如：称呼客户用“你”，一次回一两句，不催单")
                            .font(.system(size: 14)).foregroundStyle(Theme.sub)
                            .padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
                    }
                }
            Text(lengthLine).font(.system(size: 12)).foregroundStyle(length > 300 ? Theme.amber : Theme.sub)
        }
    }

    private var length: Int { ctl.options.persona.trimmingCharacters(in: .whitespacesAndNewlines).count }

    private var lengthLine: String {
        if length == 0 { return "还没写：可以用模板，或让它从你的聊天里学" }
        return length > 300 ? "\(length) 字 · 建议 300 字以内，太长 AI 抓不住重点" : "\(length) 字"
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Menu("用模板") {
                    ForEach(PersonaTemplates.all) { t in Button(t.name) { use(t) } }
                }
                .fixedSize()
                Button(work.learning ? "正在学…" : "从我的聊天学", action: learn)
            }
            HStack(spacing: 10) {
                Button("导入聊天记录…", action: importExport)
                if !work.imported.isEmpty {
                    Text("已导入 \(work.imported.count) 条，学的时候一起用").foregroundStyle(Theme.sub)
                    Button("清除") { work.imported = [] }
                }
            }
            .buttonStyle(.link).font(.system(size: 12))
            Text("用你自己发给客户的消息学，学完你确认了才用"
                 + (ctl.engine.isCloud ? "；这些消息会发到云端模型（地址电话已屏蔽）" : ""))
                .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
        }
        .disabled(work.learning)
    }

    /// Asks before a template replaces what the owner already wrote.
    private func use(_ t: PersonaTemplate) {
        work.problem = nil
        let current = ctl.options.persona.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == t.text {
            ctl.options.persona = t.text
        } else {
            replacing = t
            askReplace = true
        }
    }

    // MARK: Learning

    private func learn() {
        let ctl = self.ctl, work = self.work
        guard !work.learning else { return }
        let imported = work.imported
        work.learning = true
        work.problem = nil
        work.proposal = nil
        Task {
            do {
                let learned = try await ctl.learnPersona(imported: imported)
                work.draft = learned.text
                work.proposal = learned
            } catch {
                work.problem = error.localizedDescription
            }
            work.learning = false
        }
    }

    private func importExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, UTType(filenameExtension: "md") ?? .plainText]
        panel.prompt = "导入"
        panel.message = "选一个聊天记录（txt / md / csv）。标了“我：”的行只取这些，没标就每行都算。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let lines = try ctl.importChatExport(url)
            work.imported = PersonaSamples.combine(imported: lines, chats: work.imported).lines   // newest file first
            work.problem = nil
        } catch {
            work.problem = error.localizedDescription
        }
    }

    private func proposalBox(_ p: LearnedPersona) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("学到的说话方式 · 从 \(p.total) 条消息" + (p.fromImport > 0 ? "（含导入 \(p.fromImport) 条）" : ""))
                .font(.system(size: 13, weight: .semibold))
            TextEditor(text: $work.draft)
                .font(.system(size: 14)).scrollContentBackground(.hidden)
                .frame(height: 120).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft))
            Text("可以先改一改。点“使用”会换掉上面的人设。").font(.system(size: 12)).foregroundStyle(Theme.sub)
            HStack {
                Spacer()
                Button("取消") { work.proposal = nil }
                Button("使用", action: useProposal).buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(work.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.small)
        }
    }

    private func useProposal() {
        ctl.options.persona = work.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        work.proposal = nil
        ctl.add(.info, "店铺人设已换成学到的说法")
    }
}
