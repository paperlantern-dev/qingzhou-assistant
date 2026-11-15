import AppKit
import QingzhouCore
import SwiftUI

/// A reply written in 辅助模式: what the customer said, the draft (editable) or the picture, and 发送 / 👍 / 👎.
struct DraftCard: View {
    @EnvironmentObject var ctl: AutoReplyController
    let draft: Draft
    @State private var text: String
    @State private var thumbnail: NSImage?

    init(draft: Draft) {
        self.draft = draft
        _text = State(initialValue: draft.text)
    }

    private var sending: Bool { draft.approved != nil }

    private var kind: String { draft.proactive ? "主动问候" : draft.picture == nil ? "回复草稿" : "发图片" }

    var body: some View {
        CardBox(border: Theme.accent.opacity(0.45)) {
            HStack {
                Text("\(draft.who) · \(kind)").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(draft.time.shortLabel).font(.system(size: 13)).foregroundStyle(Theme.sub)
            }
            if !draft.question.isEmpty {
                Text("“\(draft.question)”").font(.system(size: 14)).foregroundStyle(Theme.sub).lineLimit(3)
                    .textSelection(.enabled)
            }
            if let picture = draft.picture {
                pictureLine(picture)
            } else {
                TextEditor(text: $text)
                    .font(.system(size: 14)).scrollContentBackground(.hidden).scrollIndicators(.never)
                    .frame(minHeight: 44, maxHeight: 96).padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft))
                    .disabled(sending)
            }
            Text(draft.basis + (draft.picture == nil && text.contains("\n\n") ? " · 空一行隔开的分两条发" : ""))
                .font(.system(size: 12)).foregroundStyle(Theme.sub)
            if let problem = draft.problem {
                Text(problem).font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
            buttons
            if !ctl.isRunning {
                Text("开始运行后才能发送").font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button { ctl.approveDraft(draft.id, text: text) } label: {
                Text(sending ? "发送中…" : "发送").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            .disabled(sending || !ctl.isRunning || !canSend)
            if draft.picture != nil {
                Button { ctl.rejectDraft(draft.id, reason: nil) } label: { Label("不发", systemImage: "hand.thumbsdown") }
                    .fixedSize().disabled(sending)
            } else {
                Menu {
                    ForEach(["说错了", "语气不对", "太长了", "不该回"], id: \.self) { reason in
                        Button(reason) { ctl.rejectDraft(draft.id, reason: reason) }
                    }
                    Divider()
                    Button("不发，不用说原因") { ctl.rejectDraft(draft.id, reason: nil) }
                } label: {
                    Label("不发", systemImage: "hand.thumbsdown")
                }
                .fixedSize().disabled(sending)
                Button { ctl.likeDraft(draft.id) } label: {
                    Image(systemName: draft.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .help("这样回很好，以后照这个说法").disabled(draft.liked)
            }
        }
    }

    private var canSend: Bool {
        if let picture = draft.picture { return FileManager.default.fileExists(atPath: picture) }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A small picture and its file name.
    private func pictureLine(_ path: String) -> some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(Theme.sub)
                }
            }
            .frame(width: 56, height: 56)
            .background(Theme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 14))
                    .lineLimit(1).truncationMode(.middle)
                if !FileManager.default.fileExists(atPath: path) {
                    Text("图片找不到了，发不了").font(.system(size: 12)).foregroundStyle(Theme.amber)
                }
            }
            Spacer(minLength: 0)
        }
        .task(id: path) { thumbnail = NSImage(contentsOfFile: path) }
    }
}
