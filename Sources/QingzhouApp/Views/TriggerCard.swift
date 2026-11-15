import AppKit
import QingzhouCore
import SwiftUI

/// 关键词触发: fixed answers (a text or a picture) or straight to the owner, checked before the AI replies.
struct TriggerCard: View {
    @EnvironmentObject var ctl: AutoReplyController

    /// Set when shown inside 设置: the arrow back to the menu.
    var back: (() -> Void)? = nil
    /// The rule open for editing; the others show as one line each.
    @State private var open: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let back {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent)
                            .frame(width: 24, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("返回设置")
                }
                PageHeader(title: "关键词") {
                    Button("＋ 添加", action: addRule).buttonStyle(PillButtonStyle())
                }
            }
            group("交给你", ctl.options.triggers.filter { $0.action.kind == .handOver })
            group("自动发", ctl.options.triggers.filter { $0.action.kind != .handOver })
            if !missing.isEmpty {
                Button("补上常用规则", action: addCommon).buttonStyle(.link).font(.system(size: 13)).padding(.top, 14)
                    .help("售后、找真人、讲价、付款 → 交给我；问有什么产品 → 发完整价格表")
            }
        }
    }

    /// The rules of one kind under a small heading; rules change by id, so deleting one while typing is safe.
    @ViewBuilder private func group(_ title: String, _ rules: [TriggerRule]) -> some View {
        if !rules.isEmpty {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub).padding(.top, 16).padding(.bottom, 2)
            ForEach(rules) { rule in
                if open == rule.id {
                    TriggerRuleRow(rule: rule, change: { edit in change(rule.id, edit) }, delete: { delete(rule.id) },
                                   done: { withAnimation(.easeOut(duration: 0.2)) { open = nil } })
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                        .padding(.vertical, 6)
                } else {
                    summaryRow(rule)
                }
            }
        }
    }

    /// One rule in a line: what it is, what it does, a few of its words, and its switch. Click to edit.
    private func summaryRow(_ rule: TriggerRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(of: rule)).font(.system(size: 14))
                .foregroundStyle(rule.action.kind == .handOver ? Theme.amber : Theme.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(rule.action.kind == .handOver ? Theme.amberSoft : Theme.accentSoft))
            Button { withAnimation(.easeOut(duration: 0.2)) { open = rule.id } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name(of: rule)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Text(words(of: rule)).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { on in change(rule.id) { $0.enabled = on } }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 0.5) }
        .opacity(rule.enabled ? 1 : 0.55)
    }

    /// A picture of what the rule is about: 售后 a box, 真人 a person, 讲价 a tag, 付款 a wallet…
    private func icon(of rule: TriggerRule) -> String {
        switch rule.action {
        case .handOver(let reason):
            if reason.contains("售后") { return "shippingbox" }
            if reason.contains("真人") { return "person" }
            if reason.contains("讲价") || reason.contains("价") { return "tag" }
            if reason.contains("付款") || reason.contains("下单") { return "creditcard" }
            return "hand.raised"
        case .sendCatalog: return "list.bullet"
        case .sendText: return "text.bubble"
        case .sendImage: return "photo"
        }
    }

    private func name(of rule: TriggerRule) -> String { rule.displayName }

    private func words(of rule: TriggerRule) -> String {
        guard !rule.keywords.isEmpty else { return "还没写关键词，点这里编辑" }
        let shown = rule.keywords.prefix(4).joined(separator: "、")
        return rule.keywords.count > 4 ? "\(shown) 等 \(rule.keywords.count) 个" : shown
    }

    private var missing: [TriggerRule] { TriggerRule.missingPresets(in: ctl.options.triggers) }

    private func addRule() {
        let rule = TriggerRule(keywords: [], action: .sendText(""))
        ctl.options.triggers.append(rule)
        withAnimation(.easeOut(duration: 0.2)) { open = rule.id }
    }

    /// Puts back the preset rules the owner deleted, ahead of their own (handing over comes first).
    private func addCommon() {
        let add = missing
        guard !add.isEmpty else { return }
        ctl.options.triggers = add + ctl.options.triggers
        ctl.add(.info, "已补上 \(add.count) 条常用规则")
    }

    private func change(_ id: UUID, _ edit: (inout TriggerRule) -> Void) {
        guard let i = ctl.options.triggers.firstIndex(where: { $0.id == id }) else { return }   // deleted meanwhile
        edit(&ctl.options.triggers[i])
    }

    private func delete(_ id: UUID) {
        ctl.options.triggers.removeAll { $0.id == id }
    }
}

/// One rule: its words, what to do, on/off and delete.
private struct TriggerRuleRow: View {
    @EnvironmentObject var ctl: AutoReplyController
    let rule: TriggerRule
    let change: ((inout TriggerRule) -> Void) -> Void
    let delete: () -> Void
    let done: () -> Void
    /// Typed as is (so commas can be typed), turned into keywords on every change.
    @State private var words: String
    /// What was written for each kind of action, kept when switching between them.
    @State private var contents: [TriggerRule.Kind: String]
    @State private var thumbnail: NSImage?
    @State private var problem: String?

    init(rule: TriggerRule, change: @escaping ((inout TriggerRule) -> Void) -> Void, delete: @escaping () -> Void,
         done: @escaping () -> Void) {
        self.rule = rule
        self.change = change
        self.delete = delete
        self.done = done
        _words = State(initialValue: rule.keywordText)
        _contents = State(initialValue: [rule.action.kind: rule.action.content])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("关键词，如：多少钱、价格", text: $words)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: words) { change { $0.keywords = TriggerRule.keywords(from: words) } }
                Toggle("", isOn: enabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .help(rule.enabled ? "这条规则开着" : "这条规则关着")
            }
            Picker("", selection: kind) {
                ForEach(TriggerRule.Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            detail
            if let hint { Text(hint).font(.system(size: 13)).foregroundStyle(Theme.amber) }
            HStack {
                Button("删除这条", role: .destructive, action: delete).buttonStyle(.link).font(.system(size: 13))
                Spacer()
                Button("完成", action: done).buttonStyle(PrimaryButtonStyle(height: 28)).fixedSize()
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch rule.action.kind {
        case .text:
            TextField("要发的话，如：价目表发你了～", text: content).textFieldStyle(.roundedBorder)
        case .image:
            pictureLine
        case .handOver:
            TextField("原因（可不填），如：售后问题", text: content).textFieldStyle(.roundedBorder)
        case .catalog:
            Text("把知识库价格表（csv）里的商品一条不落地排好发出去；改了价格表，发出去的也跟着变。")
                .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pictureLine: some View {
        let path = rule.action.content
        return HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(Theme.sub)
                }
            }
            .frame(width: 36, height: 36)
            .background(Theme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(path.isEmpty ? "还没选图片" : URL(fileURLWithPath: path).lastPathComponent)
                .font(.system(size: 13)).foregroundStyle(path.isEmpty ? Theme.sub : Theme.neutralText)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Button(path.isEmpty ? "选图片…" : "换一张…", action: choosePicture).controlSize(.small)
        }
        .task(id: path) { thumbnail = path.isEmpty ? nil : NSImage(contentsOfFile: path) }
    }

    /// Why this rule will not work yet, or nil.
    private var hint: String? {
        if let problem { return problem }
        if case .sendImage(let path) = rule.action, !path.isEmpty, !FileManager.default.fileExists(atPath: path) {
            return "图片找不到了，请重新选一张"
        }
        guard !rule.isComplete else { return nil }
        if TriggerRule.keywords(from: words).isEmpty { return "还没写关键词，这条不会生效" }
        return rule.action.kind == .image ? "还没选图片，这条不会生效" : "还没写要发的话，这条不会生效"
    }

    private var enabled: Binding<Bool> {
        Binding(get: { rule.enabled }, set: { on in change { $0.enabled = on } })
    }

    /// Switching the kind keeps what was written for the old one, and brings back what the new one had.
    private var kind: Binding<TriggerRule.Kind> {
        Binding(get: { rule.action.kind }, set: { new in
            contents[rule.action.kind] = rule.action.content
            let action = TriggerRule.Action(kind: new, content: contents[new] ?? "")
            change { $0.action = action }
        })
    }

    private var content: Binding<String> {
        Binding(get: { rule.action.content }, set: { value in
            let action = TriggerRule.Action(kind: rule.action.kind, content: value)
            change { $0.action = action }
        })
    }

    private func choosePicture() {
        do {
            guard let url = try AutoReplyController.choosePicture() else { return }
            problem = nil
            content.wrappedValue = url.path
            ctl.add(.info, "规则用的图片已存好：\(url.path)")
        } catch {
            problem = "没能用这张图片：\(error.localizedDescription)"
            ctl.add(.error, "选图片失败：\(error.localizedDescription)")
        }
    }
}
