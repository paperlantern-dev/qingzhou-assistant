import QingzhouCore
import SwiftUI

/// 客户: everyone the assistant has talked with, like the chat app's own list, and one customer's page.
struct CustomersView: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var query = ""
    @State private var shown: String?          // ChatID of the open customer page
    @State private var publishing = false

    var body: some View {
        if let id = shown, let record = ctl.customers.first(where: { $0.chatID == id }) {
            CustomerDetailView(record: record, back: { shown = nil })
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            PageHeader(title: ctl.customers.isEmpty ? "客户" : "客户 \(ctl.customers.count)") {
                Button("＋ 上新") { publishing = true }.buttonStyle(PillButtonStyle()).help("发布新品，通知想要的客户")
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Theme.sub)
                TextField("搜索", text: $query).textFieldStyle(.plain).font(.system(size: 14))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.sub)
                }
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(Theme.neutralSoft.opacity(0.8)))
            .padding(.horizontal, 20).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        if ctl.customers.isEmpty {
                            EmptyState(icon: "person.2", title: "还没有客户", detail: "开始后，聊过的客户会出现在这里")
                        } else {
                            EmptyState(icon: "magnifyingglass", title: "没找到“\(query)”")
                        }
                    }
                    ForEach(filtered, id: \.chatID) { r in
                        Button { shown = r.chatID } label: { row(r) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $publishing) { PublishSheet(isPresented: $publishing).environmentObject(ctl) }
        .onAppear {   // tests can open a customer's page directly (`--show-customer 王女士`)
            let args = CommandLine.arguments
            guard shown == nil, let i = args.firstIndex(of: "--show-customer"), i + 1 < args.count else { return }
            ctl.refreshCustomers()
            shown = ctl.customers.first { $0.name.contains(args[i + 1]) }?.chatID
        }
    }

    private var filtered: [CustomerRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ctl.customers }
        return ctl.customers.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.summary.contains(q) }
    }

    private func row(_ r: CustomerRecord) -> some View {
        HStack(alignment: .center, spacing: 11) {
            AvatarView(name: r.name, image: ctl.avatar(of: r), size: 36).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(r.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(r.lastSeen.shortLabel).font(.system(size: 12)).foregroundStyle(Theme.sub)
                }
                if let last = r.messages.last {
                    Text((last.fromMe ? "我：" : "对方：") + last.text)
                        .font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                }
                let tags = tags(of: r)
                if !tags.isEmpty {
                    HStack(spacing: 4) { ForEach(tags, id: \.0) { TagView(text: $0.0, kind: $0.1) } }
                }
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 0.5) }
        .contentShape(Rectangle())
    }

    private func tags(of r: CustomerRecord) -> [(String, TagView.Kind)] {
        var tags: [(String, TagView.Kind)] = []
        if ctl.isNeverReply(r.name) { tags.append(("不自动回复", .neutral)) }
        if ctl.needsHuman.contains(where: { ChatID.same($0.chat, r.chatID) })
            || ctl.drafts.contains(where: { ChatID.same($0.chat, r.chatID) }) { tags.append(("等你处理", .amber)) }
        if r.reservations.contains(where: { $0.status == .waiting }) {
            tags.append(("预留中", .neutral))
        } else if r.reservations.contains(where: { $0.status == .notified }) {
            tags.append(("预留已通知", .green))
        }
        if r.optedOutAt != nil {
            tags.append(("别打扰", .neutral))
        } else if let c = r.consent {
            tags.append(("想要\(c.interests)", .neutral))
        }
        return tags
    }
}

/// One customer: key points, reservations and news permission, and the latest messages.
struct CustomerDetailView: View {
    @EnvironmentObject var ctl: AutoReplyController
    let record: CustomerRecord
    let back: () -> Void
    @State private var editing = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: back) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                            Text("客户")
                        }
                        .font(.system(size: 14)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    identity
                    Button("在\(ctl.target.name)里打开") { ctl.showInChatApp(record.chatID) }
                        .buttonStyle(PrimaryButtonStyle(height: 32))
                    keyPoints
                    permissions
                    recent
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $editing) {
            SummaryEditor(text: record.summary) { ctl.updateSummary($0, chat: record.chatID) }
        }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            AvatarView(name: record.name, image: ctl.avatar(of: record), size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.name).font(.system(size: 20, weight: .bold)).textSelection(.enabled)
                Text("\(ctl.target.name) · 最近 \(record.lastSeen.shortLabel) · 记住 \(record.messages.count) 条聊天")
                    .font(.system(size: 13)).foregroundStyle(Theme.sub)
            }
        }
    }

    private var keyPoints: some View {
        CardBox {
            HStack {
                Text("要点").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("编辑") { editing = true }.buttonStyle(.link).font(.system(size: 13))
            }
            Text(record.summary.isEmpty ? "还没有要点。聊得多了会自动整理，也可以自己写。" : record.summary)
                .font(.system(size: 14)).foregroundStyle(record.summary.isEmpty ? Theme.sub : .primary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private var permissions: some View {
        CardBox(padding: 0) {
            VStack(spacing: 0) {
                autoReplyRow
                Divider()
                ForEach(record.reservations.filter { $0.status != .cancelled }.reversed()) { res in
                    reservationRow(res)
                    Divider()
                }
                newsRow
                if let greeted = record.lastRevisitAt {
                    Divider()
                    Text("主动智能上次问候：\(greeted.shortLabel)").font(.system(size: 12)).foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 8)
                }
            }
        }
    }

    private func reservationRow(_ res: Reservation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("预留 · \(res.item)").font(.system(size: 14))
                Text("“\(res.quote)”").font(.system(size: 12)).foregroundStyle(Theme.sub).lineLimit(2)
            }
            Spacer(minLength: 8)
            if res.status == .notified {
                TagView(text: "已通知" + (res.notifiedAt.map { " \($0.shortLabel)" } ?? ""), kind: .green)
            } else if ctl.isQueued(res) {
                TagView(text: "已安排通知", kind: .blue)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Button("已到货") { ctl.reservationArrived(chat: record.chatID, id: res.id) }
                        .controlSize(.small).disabled(!ctl.outreachEnabled)
                    Button("取消预留") { ctl.deleteReservation(chat: record.chatID, id: res.id) }
                        .buttonStyle(.link).font(.system(size: 12))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Off = put on the 不自动回复 list (family, friends, suppliers).
    private var autoReplyRow: some View {
        SettingLine(title: "自动回复 TA", hint: ctl.isNeverReply(record.name) ? "关着：不点开、不回复、不记录" : "家人、朋友、供应商可以关掉") {
            Toggle("", isOn: Binding(get: { !ctl.isNeverReply(record.name) },
                                     set: { ctl.setNeverReply(record.name, !$0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    private var newsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("新品通知").font(.system(size: 14))
                Text(newsHint).font(.system(size: 12)).foregroundStyle(Theme.sub).lineLimit(2)
            }
            Spacer(minLength: 8)
            if record.optedOutAt != nil {
                TagView(text: "别打扰", kind: .neutral)
            } else if record.consent != nil {
                VStack(alignment: .trailing, spacing: 4) {
                    TagView(text: "已同意", kind: .green)
                    Button("不再通知") { ctl.removeConsent(chat: record.chatID) }.buttonStyle(.link).font(.system(size: 12))
                }
            } else {
                TagView(text: "未同意", kind: .neutral)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var newsHint: String {
        if record.optedOutAt != nil { return "说过别再发 · 只回复不主动" }
        if let c = record.consent { return "想要：\(c.interests) · “\(c.quote)”" }
        return "没说过想收到 · 只回复不主动"
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "最近聊天")
            ForEach(Array(record.messages.suffix(4).enumerated()), id: \.offset) { _, m in
                HStack {
                    if m.fromMe { Spacer(minLength: 40) }
                    Text(m.text).font(.system(size: 14)).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(m.fromMe ? Theme.bubbleMine : Theme.bubbleTheirs))
                    if !m.fromMe { Spacer(minLength: 40) }
                }
            }
        }
    }
}

/// Edits a customer's key points (the assistant reads them before replying).
private struct SummaryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    let save: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("编辑要点").font(.headline)
            TextEditor(text: $text).font(.system(size: 14)).frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
            Text("回复这位客户时会参考这些要点。").font(.system(size: 12)).foregroundStyle(Theme.sub)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 340)
    }
}

/// “发布新品”: only customers who asked to hear about new arrivals, and whose interests fit.
private struct PublishSheet: View {
    @EnvironmentObject var ctl: AutoReplyController
    @Binding var isPresented: Bool
    @State private var text = ""
    @State private var confirming = false

    var body: some View {
        let people = ctl.newsRecipients(for: text)
        VStack(alignment: .leading, spacing: 10) {
            Text("发布新品").font(.headline)
            Text("只发给说过“有好东西告诉我”、而且想要的东西对得上的客户。AI 按你写的内容给每人写一句，隔几分钟发一位。")
                .font(.system(size: 13)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text).font(.system(size: 14)).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
            Text(recipientsLine(people)).font(.system(size: 13))
                .foregroundStyle(people.isEmpty ? Theme.sub : Theme.green).fixedSize(horizontal: false, vertical: true)
            if !ctl.outreachEnabled {
                Text("设置里“按许可主动联系”已关闭，不会发送。").font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
            HStack {
                Spacer()
                Button("取消") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("发布") { confirming = true }
                    .keyboardShortcut(.defaultAction).disabled(people.isEmpty || !ctl.outreachEnabled)
            }
        }
        .padding(16).frame(width: 360)
        .alert("发给 \(people.count) 位客户？", isPresented: $confirming) {
            Button("发布") {
                ctl.publish(text)
                isPresented = false
            }
            Button("再想想", role: .cancel) {}
        } message: {
            Text(ctl.isRunning ? "白天（9–21 点）空闲时逐个发送。" : "开始自动回复后，白天（9–21 点）逐个发送。")
        }
    }

    private func recipientsLine(_ people: [CustomerRecord]) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "写好内容后，这里会显示会发给谁。" }
        if people.isEmpty { return "没有对得上的客户，不会发给任何人。" }
        let names = people.prefix(5).map(\.name).joined(separator: "、")
        return "会发给 \(people.count) 位：\(names)\(people.count > 5 ? " 等" : "")"
    }
}
