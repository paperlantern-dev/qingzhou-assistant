import AppKit
import QingzhouCore
import SwiftUI
import UniformTypeIdentifiers

/// 定时群发 (off by default): the owner's own words, sent at set times to chosen customers.
struct BroadcastCard: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "定时群发（默认关闭）")
            CardBox {
                ToggleLine(title: "按时间群发消息",
                           hint: "按时间给选中的客户发同一段话。群发太多容易被微信限制，也和“不打扰客户”的做法相反，需要时再开。",
                           isOn: Binding(get: { ctl.options.broadcastOn }, set: { ctl.setBroadcastOn($0) }))
                if ctl.options.broadcastOn {
                    Divider()
                    if ctl.options.broadcasts.isEmpty, !editing {
                        Text("还没有群发").font(.system(size: 13)).foregroundStyle(Theme.sub)
                    }
                    let everyone = ctl.options.broadcasts.contains { $0.recipients.isEmpty } ? reachable : 0
                    ForEach(ctl.options.broadcasts) { BroadcastRow(broadcast: $0, everyone: everyone) }
                    if editing {
                        BroadcastEditor { editing = false }
                    } else {
                        Button { editing = true } label: { Label("新建群发", systemImage: "plus") }
                    }
                    Text(rules).font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// How many customers a broadcast to everyone reaches now (worked out once per drawing).
    private var reachable: Int { ctl.broadcastRecipients(Broadcast(text: ""), in: ctl.customers).count }

    private var rules: String {
        "只在 9–21 点发，每人间隔 1–3 分钟；说过“别发了”的和不自动回复的人不会收到。"
            + "开着自动回复时才会发；每次最多 \(Broadcast.maxPerRun) 位，左侧聊天列表里找不到的客户这次跳过。"
            + (ctl.options.assistMode ? "辅助模式下也直接发，因为是你自己写的。" : "")
    }
}

/// One saved broadcast: its words, when, to whom; a switch and delete.
private struct BroadcastRow: View {
    @EnvironmentObject var ctl: AutoReplyController
    let broadcast: Broadcast
    let everyone: Int   // customers a broadcast to everyone reaches now

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(broadcast.text).font(.system(size: 14)).lineLimit(2)
                    .foregroundStyle(broadcast.enabled ? Color.primary : Theme.sub)
                HStack(spacing: 6) {
                    TagView(text: broadcast.schedule.label(), kind: broadcast.enabled ? .blue : .neutral)
                    TagView(text: whom)
                    if broadcast.picture != nil { TagView(text: "带图片") }
                    if let last = broadcast.lastRun {
                        Text("上次 \(last.shortLabel)").font(.system(size: 12)).foregroundStyle(Theme.sub)
                    }
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { broadcast.enabled }, set: { ctl.setBroadcast(broadcast.id, enabled: $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .help(broadcast.enabled ? "暂停这条群发" : "打开这条群发")
            Button { ctl.deleteBroadcast(broadcast.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.sub).help("删除这条群发")
        }
        .padding(.vertical, 2)
    }

    private var whom: String {
        broadcast.recipients.isEmpty ? "所有客户 · \(everyone) 位" : "选了 \(broadcast.recipients.count) 位"
    }
}

/// 新建群发, right in the card: the words, an optional picture, when, and to whom.
private struct BroadcastEditor: View {
    enum Repeat: String, CaseIterable, Identifiable {
        case once = "一次", daily = "每天", weekly = "每周"
        var id: String { rawValue }
    }

    @EnvironmentObject var ctl: AutoReplyController
    let close: () -> Void
    @State private var text = ""
    @State private var picture: URL?   // copied into the app's own folder on 保存
    @State private var repeats = Repeat.daily
    @State private var day = BroadcastEditor.today(hour: 10, plusDays: 1)    // 一次
    @State private var time = BroadcastEditor.today(hour: 10, plusDays: 0)   // 每天 / 每周
    @State private var weekday = Calendar.current.component(.weekday, from: Date())
    @State private var everyone = true
    @State private var chosen: Set<String> = []
    @State private var people: [CustomerRecord] = []   // who can get it; worked out when the editor opens
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("新建群发").font(.system(size: 14, weight: .semibold))
            words
            pictureLine
            whenLine
            whomLine
            if let why = problem ?? (text.isEmpty ? nil : check) {
                Text(why).font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
            HStack {
                Spacer()
                Button("取消", action: close)
                Button("保存", action: save).disabled(check != nil)
            }
        }
        .onAppear { people = candidates }
        .onChange(of: ctl.customers.count) { people = candidates }
    }

    // MARK: Parts

    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(height: 70)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.page))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("要发的话，比如：今天到了新鲜脐橙，要的私聊我")
                            .font(.system(size: 14)).foregroundStyle(Theme.sub)
                            .padding(.horizontal, 9).padding(.vertical, 4).allowsHitTesting(false)
                    }
                }
            Text("原样发出，不经过 AI。发出去是一条消息，换行会变成空格。\(Broadcast.oneLine(text).count)/\(Broadcast.maxLength)")
                .font(.system(size: 12)).foregroundStyle(Theme.sub)
        }
    }

    private var pictureLine: some View {
        SettingLine(title: "图片（可不加）", hint: picture?.lastPathComponent ?? "文字发完后再发这张图") {
            if picture != nil { Button("去掉") { picture = nil }.controlSize(.small) }
            Button(picture == nil ? "选图片…" : "换一张…", action: choosePicture).controlSize(.small)
        }
    }

    private var whenLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingLine(title: "什么时候发") {
                Picker("", selection: $repeats) { ForEach(Repeat.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            HStack(spacing: 8) {
                Spacer()
                switch repeats {
                case .once:
                    DatePicker("", selection: $day, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                case .daily:
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                case .weekly:
                    Picker("", selection: $weekday) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(Broadcast.Schedule.weekdayName($0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                }
            }
            if let later = laterNote {
                Text(later).font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
        }
    }

    private var whomLine: some View {
        let list = people
        return VStack(alignment: .leading, spacing: 6) {
            SettingLine(title: "发给谁") {
                Picker("", selection: $everyone) {
                    Text("所有客户").tag(true)
                    Text("选择客户").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if everyone {
                Text("记住的客户里，现在能收到的有 \(list.count) 位").font(.system(size: 12)).foregroundStyle(Theme.sub)
            } else if list.isEmpty {
                Text("还没有记住的客户。开始自动回复后，聊过的客户会出现在这里。")
                    .font(.system(size: 12)).foregroundStyle(Theme.sub)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(list, id: \.chatID) { r in
                            Toggle(r.name, isOn: pick(r.name)).toggleStyle(.checkbox).font(.system(size: 14))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(CGFloat(list.count) * 22 + 8, 160))
                Text("已选 \(chosen.count) 位").font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
        }
    }

    // MARK: Logic

    /// Customers who can get a broadcast (not 别发了, not 不自动回复, no groups or system chats).
    private var candidates: [CustomerRecord] { ctl.broadcastRecipients(Broadcast(text: ""), in: ctl.customers) }

    private var schedule: Broadcast.Schedule {
        let c = Calendar.current
        let hour = c.component(.hour, from: time), minute = c.component(.minute, from: time)
        switch repeats {
        case .once: return .once(at: Self.startOfMinute(day))
        case .daily: return .daily(hour: hour, minute: minute)
        case .weekly: return .weekly(weekday: weekday, hour: hour, minute: minute)
        }
    }

    /// What still needs fixing before 保存, or nil.
    private var check: String? {
        let words = Broadcast.oneLine(text)
        if words.isEmpty { return "先写要发的话" }
        if words.count > Broadcast.maxLength { return "最多 \(Broadcast.maxLength) 个字" }
        let hour = Calendar.current.component(.hour, from: repeats == .once ? day : time)
        if !ctl.outreachHours.contains(hour) { return "只能选 9–21 点之间的时间" }
        if repeats == .once, Self.startOfMinute(day) < Self.startOfMinute(Date()) { return "这个时间已经过了" }
        if !everyone, chosen.isEmpty { return "至少选一位客户" }
        return nil
    }

    /// Today's time already passed: it starts with the next one (nothing goes out right after 保存).
    private var laterNote: String? {
        guard repeats != .once, let today = schedule.time(on: Date()), today < Self.startOfMinute(Date()) else { return nil }
        return repeats == .daily ? "今天这个时间已经过了，明天开始发" : "今天这个时间已经过了，下周开始发"
    }

    private func pick(_ name: String) -> Binding<Bool> {
        Binding(get: { chosen.contains(name) },
                set: { chosen = $0 ? chosen.union([name]) : chosen.subtracting([name]) })
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "用这张图片"
        if panel.runModal() == .OK, let url = panel.url {
            picture = url
            problem = nil
        }
    }

    private func save() {
        problem = nil
        guard check == nil else { return }
        // Chosen people who can no longer get it are left out; none left must never mean everyone.
        let names = everyone ? [] : candidates.map(\.name).filter { chosen.contains($0) }
        guard everyone || !names.isEmpty else {
            problem = "选的客户现在都收不到了，请重新选"
            return
        }
        var path: String?
        if let picture {
            do {
                path = try AutoReplyController.copyBroadcastPicture(from: picture).path
            } catch {
                problem = "图片没存好：\(error.localizedDescription)"
                return
            }
        }
        ctl.addBroadcast(Broadcast(text: Broadcast.oneLine(text), picture: path, recipients: names, schedule: schedule))
        close()
    }

    private static func today(hour: Int, plusDays: Int) -> Date {
        let c = Calendar.current
        let day = c.date(byAdding: .day, value: plusDays, to: Date()) ?? Date()
        return c.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private static func startOfMinute(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
    }
}
