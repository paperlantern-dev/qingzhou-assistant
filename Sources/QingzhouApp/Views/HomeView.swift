import QingzhouCore
import SwiftUI

/// 动态: the big sea-blue card (today's count, start / pause, how replies go), what waits for the
/// owner, and what just happened.
struct HomeView: View {
    @EnvironmentObject var ctl: AutoReplyController
    @Binding var showChooser: Bool
    let goSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if ctl.homeBadge > 0 || !ctl.answerSuggestions.isEmpty { waiting }
                if let s = ctl.summaryToShow { summaryCard(s.title, s.summary, day: s.day) }
                feed
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 20)
        }
        .onAppear { ctl.refreshAnswerSuggestions() }
    }

    // MARK: 大卡片

    private var hero: some View {
        let running = ctl.isRunning
        return ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusLine).font(.system(size: 13)).opacity(0.85)
                        if running {
                            Text("\(ctl.repliesToday)").font(.system(size: 44, weight: .bold).monospacedDigit())
                                .contentTransition(.numericText())
                        } else {
                            Text(problem?.title ?? "准备好了").font(.system(size: 24, weight: .bold))
                        }
                        Text(subLine).font(.system(size: 13)).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    runButton
                }
                HStack(spacing: 6) {
                    ChoiceChip(title: ctl.replyMode == .all ? "全回" : "稳妥", onDark: running,
                               options: [ChoiceOption(id: "confident", title: "稳妥", detail: "只回有把握的，其余交给你"),
                                         ChoiceOption(id: "all", title: "全回", detail: "都回，答不了的说“我确认一下”")],
                               selected: ctl.replyMode == .all ? "all" : "confident") { ctl.replyMode = $0 == "all" ? .all : .confident }
                    ChoiceChip(title: ctl.options.assistMode ? "确认后发" : "自动发", onDark: running,
                               options: [ChoiceOption(id: "auto", title: "自动发", detail: "写好就发"),
                                         ChoiceOption(id: "assist", title: "确认后发", detail: "放在这里，你点了才发")],
                               selected: ctl.options.assistMode ? "assist" : "auto") { ctl.options.assistMode = $0 == "assist" }
                    ChoiceChip(title: modelTitle, icon: "cpu", onDark: running, options: modelOptions,
                               selected: modelSelected, pick: pickModel)
                    if !running, let problem, let action = problem.action {
                        Button(action.0, action: action.1).buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.amber)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.amberSoft))
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            WaveBand(color: running ? .white : Theme.accent, strength: running ? 1 : 0.55)
                .frame(height: 24).allowsHitTesting(false)
        }
        .foregroundStyle(running ? Color.white : Theme.heroInk)
        .background {
            if running {
                LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Theme.heroIdle
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: running)
    }

    private var statusLine: String {
        let app = ctl.pickedWindow?.appName ?? ctl.target.name
        if ctl.isRunning { return "● \(ctl.dryRun ? "演练中" : "运行中") · \(app)" }
        return "● 未运行"
    }

    private var subLine: String {
        if ctl.isRunning, let notice = ctl.updateNotice { return notice }
        if ctl.isRunning { return "今天已回复 · 学到 \(ctl.answerSuggestions.count) 条" }
        if let problem { return problem.hint }
        let app = ctl.pickedWindow?.appName ?? ctl.target.name
        return "\(app)已连接 · 知识库 \(ctl.kb?.files.count ?? 0) 个文件"
    }

    /// The round start / pause button on the card.
    private var runButton: some View {
        let running = ctl.isRunning
        return Button { running ? ctl.stop() : ctl.start() } label: {
            Image(systemName: running ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(running ? Theme.heroBottom : .white)
                .offset(x: running ? 0 : 1.5)
                .frame(width: 54, height: 54)
                .background(Circle().fill(running ? Color.white : Theme.accent))
                .shadow(color: (running ? Color.black : Theme.accent).opacity(0.25), radius: 8, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .disabled(!running && !ctl.target.supportsAutoReply)
        .help(running ? "暂停自动回复" : "开始自动回复")
    }

    // MARK: 模型

    /// “极速” / “省钱” / “聪明” from the model's note, else the model's own name.
    private var modelTitle: String {
        guard ctl.engine == .api, let api = ctl.activeApi else { return ctl.engine == .ollama ? "本机" : "Codex" }
        return Self.shortName(api.modelChoices.first { $0.id == api.model }?.note, model: api.model)
    }

    private static func shortName(_ note: String?, model: String) -> String {
        guard let note else { return model.replacingOccurrences(of: "gpt-", with: "") }
        if note.contains("快") { return "极速" }
        if note.contains("便宜") { return "省钱" }
        if note.contains("聪明") { return "聪明" }
        return model.replacingOccurrences(of: "gpt-", with: "")
    }

    /// Every model of every API that has a key, and the model on this Mac.
    private var modelOptions: [ChoiceOption] {
        apiOptions + [ChoiceOption(id: "ollama|\(ctl.ollamaModel)", title: "本机 · \(ctl.ollamaModel)",
                                   detail: "在这台电脑上运行，不联网、不花钱；要先装好 Ollama")]
    }

    private var apiOptions: [ChoiceOption] {
        ctl.options.apiConfigs.filter { !ctl.apiKey(for: $0).isEmpty }.flatMap { c -> [ChoiceOption] in
            let choices = c.modelChoices.isEmpty ? [(id: c.model, note: "")] : c.modelChoices.map { (id: $0.id, note: $0.note) }
            return choices.map { m in
                ChoiceOption(id: "\(c.id.uuidString)|\(m.id)",
                             title: "\(c.name) · \(Self.shortName(m.note.isEmpty ? nil : m.note, model: m.id))",
                             detail: m.note.isEmpty ? m.id : "\(m.id) · \(m.note)")
            }
        }
    }

    private var modelSelected: String {
        if ctl.engine == .ollama { return "ollama|\(ctl.ollamaModel)" }
        guard ctl.engine == .api, let api = ctl.activeApi else { return "" }
        return "\(api.id.uuidString)|\(api.model)"
    }

    private func pickModel(_ id: String) {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.first == "ollama" {
            ctl.engine = .ollama
            ctl.add(.info, "换成本机模型 \(ctl.ollamaModel)")
            return
        }
        guard parts.count == 2, let i = ctl.options.apiConfigs.firstIndex(where: { $0.id.uuidString == parts[0] }) else { return }
        ctl.options.apiConfigs[i].model = parts[1]
        ctl.options.apiActive = ctl.options.apiConfigs[i].id
        ctl.engine = .api
        ctl.add(.info, "换成 \(ctl.options.apiConfigs[i].name) \(parts[1])")
    }

    /// What stops a start, the first one only: (title, hint, button).
    private var problem: (title: String, hint: String, action: (String, () -> Void)?)? {
        let app = ctl.pickedWindow?.appName ?? ctl.target.name
        if !ctl.target.supportsAutoReply { return ("还没适配", "\(app)只能查看，不能自动回复", ("换窗口", { showChooser = true })) }
        if let wrong = ctl.screenProblem { return ("读\(app)读得不对", wrong, ("再检查一次", { ctl.start() })) }
        if ctl.chatWindowMissing { return ("没找到\(app)", "打开它，放在屏幕上（可以被挡住）", ("换窗口", { showChooser = true })) }
        if !ctl.hasScreenPermission || !ctl.hasAccessibility { return ("还缺系统权限", "在上面的提示里点“去授权”", nil) }
        if ctl.kb?.isEmpty ?? true { return ("知识库是空的", "放进价格表等文件才会回复", ("去设置", goSettings)) }
        if !engineReady { return ("还没填密钥", "在设置里填好 AI 的密钥", ("去设置", goSettings)) }
        return nil
    }

    private var engineReady: Bool {
        switch ctl.engine {
        case .codex: return true
        case .api: return ctl.activeApi.map { !ctl.apiKey(for: $0).isEmpty } ?? false
        case .ollama: return true
        }
    }

    // MARK: 每日小结

    private func summaryCard(_ title: String, _ s: DailySummary, day: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
                Spacer()
                Button { ctl.closeSummary(day) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.sub)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("知道了，收起")
            }
            Text(s.headline).font(.system(size: 15, weight: .semibold))
            if !s.unanswered.isEmpty {
                ForEach(Array(s.unanswered.prefix(3).enumerated()), id: \.offset) { _, q in
                    Text("没答上：\(q.replacingOccurrences(of: " / ", with: "；"))").font(.system(size: 13))
                        .foregroundStyle(Theme.sub).lineLimit(2)
                }
                Text(s.unanswered.count > 3 ? "还有 \(s.unanswered.count - 3) 个 · 跟小轻舟说答案，就能补进知识库"
                                            : "跟小轻舟说答案，就能补进知识库")
                    .font(.system(size: 12)).foregroundStyle(Theme.sub.opacity(0.8))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
    }

    // MARK: 待处理

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ctl.homeBadge > 0 {
                Text("待处理 \(ctl.homeBadge)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.amber)
                ForEach(ctl.drafts) { DraftCard(draft: $0) }
                ForEach(ctl.needsHuman.reversed()) { item in
                    personRow(name: item.who, title: "\(item.who) · \(item.reason)", detail: item.message) {
                        pill("去回复") { ctl.showInChatApp(item.chat) }
                        Button { ctl.resolveHuman(item.id) } label: { Image(systemName: "checkmark") }
                            .buttonStyle(.plain).foregroundStyle(Theme.sub).help("已处理")
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                ForEach(ctl.waitingReservations, id: \.reservation.id) { pair in
                    personRow(name: pair.record.name, title: "\(pair.record.name) · 留货", detail: pair.reservation.item) {
                        pill("到货了") { ctl.reservationArrived(chat: pair.record.chatID, id: pair.reservation.id) }
                            .disabled(!ctl.outreachEnabled)
                        Button { ctl.deleteReservation(chat: pair.record.chatID, id: pair.reservation.id) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.sub).help("取消留货")
                    }
                }
            }
            if !ctl.answerSuggestions.isEmpty {
                Text("学到的问答 \(ctl.answerSuggestions.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
                    .padding(.top, ctl.homeBadge > 0 ? 6 : 0)
                ForEach(ctl.answerSuggestions.reversed()) { LearnedAnswerCard(suggestion: $0).id("\($0.id)\($0.answer)") }
            }
        }
        .animation(.easeOut(duration: 0.25), value: ctl.needsHuman.map(\.id))
    }

    private func personRow<Actions: View>(name: String, title: String, detail: String,
                                          @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: name, image: nil, size: 34).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(2).textSelection(.enabled)
            }
            Spacer(minLength: 6)
            HStack(spacing: 10) { actions() }
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.blueText)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(Theme.accentSoft))
    }

    // MARK: 刚刚

    private var feed: some View {
        let items = ctl.activity.filter { Calendar.current.isDateInToday($0.time) }.reversed()
        return VStack(alignment: .leading, spacing: 0) {
            Text(ctl.isRunning ? "刚刚" : "今天").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
                .padding(.bottom, 4)
            if ctl.isRunning {
                row(time: "现在", color: Theme.green, title: ctl.status, detail: nil) { stepStream }
            }
            if items.isEmpty, !ctl.isRunning {
                VStack(spacing: 8) {
                    WaveLine().stroke(Theme.accent.opacity(0.18), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 96, height: 16)
                    Text("还没开始，风平浪静").font(.system(size: 13)).foregroundStyle(Theme.sub)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 36)
            }
            ForEach(Array(items.prefix(40))) { a in
                row(time: a.time.shortLabel,
                    color: a.kind == .handedOver ? Theme.amber : Theme.sub,
                    title: a.who.isEmpty ? a.title : "\(a.who) · \(a.title)", detail: a.detail) {
                    if let q = a.question, let r = a.reply { TeachLine(question: q, reply: r) }
                }
            }
        }
    }

    /// The reply being worked on, step by step. Re-checked every few seconds so old steps go away.
    private var stepStream: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let live = ctl.liveSteps(at: context.date)
            if !live.steps.isEmpty { StepStream(steps: live.steps, ended: live.ended).padding(.top, 4) }
        }
    }

    private func row(time: String, color: Color, title: String, detail: String?) -> some View {
        row(time: time, color: color, title: title, detail: detail) { EmptyView() }
    }

    private func row<Extra: View>(time: String, color: Color, title: String, detail: String?,
                                  @ViewBuilder extra: () -> Extra) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time).font(.system(size: 13).monospacedDigit()).foregroundStyle(color).frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1).textSelection(.enabled)
                }
                extra()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 0.5) }
    }
}

/// Under a reply the assistant sent: “回得不好？” opens one line to write what it should have said.
private struct TeachLine: View {
    @EnvironmentObject var ctl: AutoReplyController
    let question: String
    let reply: String
    @State private var open = false
    @State private var better = ""
    @State private var saved = false

    var body: some View {
        if saved {
            Text("记住了，下次照这样回").font(.system(size: 12)).foregroundStyle(Theme.green)
        } else if open {
            HStack(spacing: 6) {
                TextField("应该怎么回？", text: $better).textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(Theme.neutralSoft.opacity(0.8)))
                    .onSubmit(save)
                Button("记住", action: save).buttonStyle(PillButtonStyle())
                    .disabled(better.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 2)
        } else {
            Button("回得不好？教它") { open = true }.buttonStyle(.plain)
                .font(.system(size: 12)).foregroundStyle(Theme.blueText)
        }
    }

    private func save() {
        guard !better.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        ctl.teach(question: question, reply: reply, better: better)
        saved = true
    }
}

/// Two soft waves along the bottom of the big card.
private struct WaveBand: View {
    let color: Color
    var strength: Double = 1
    var body: some View {
        ZStack {
            Wave(phase: 0, amplitude: 6).fill(color.opacity(0.14 * strength))
            Wave(phase: .pi / 2, amplitude: 4).fill(color.opacity(0.18 * strength)).offset(y: 4)
        }
    }
}

/// A filled wave: a sine line across the top, flat below.
private struct Wave: Shape {
    var phase: Double
    var amplitude: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.height * 0.55
        p.move(to: CGPoint(x: 0, y: mid))
        for x in stride(from: 0, through: rect.width, by: 4) {
            let y = mid + sin(Double(x) / rect.width * 4 * .pi + phase) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// A single wave line (for empty states).
private struct WaveLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        for x in stride(from: 0, through: rect.width, by: 2) {
            p.addLine(to: CGPoint(x: x, y: rect.midY + sin(Double(x) / rect.width * 4 * .pi) * rect.height * 0.4))
        }
        return p
    }
}

/// Pressed in a little while held down.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A compact stream of the current reply's steps: a thin rail with a dot per step, small times,
/// the newest step highlighted (blue while working, green once sent).
private struct StepStream: View {
    let steps: [ReplyStep]
    let ended: Bool
    private static let rowHeight: CGFloat = 18
    private static let dotColumn: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { s in row(s, newest: s.id == steps.last?.id) }
        }
        .background(alignment: .leading) {   // the rail: from the first dot to the newest
            Rectangle().fill(Theme.line).frame(width: 1)
                .padding(.vertical, Self.rowHeight / 2).padding(.leading, (Self.dotColumn - 1) / 2)
        }
    }

    private func row(_ s: ReplyStep, newest: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(newest ? highlight : Theme.sub).frame(width: newest ? 7 : 5, height: newest ? 7 : 5)
                .frame(width: Self.dotColumn)
            Text(s.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.sub)
            Text(s.detail.isEmpty ? s.title : "\(s.title) · \(s.detail)")
                .font(.system(size: 12, weight: newest ? .medium : .regular))
                .foregroundStyle(newest ? highlight : Theme.sub)
                .lineLimit(1).truncationMode(.tail)
                .help(s.detail)
        }
        .frame(height: Self.rowHeight)
    }

    private var highlight: Color {
        guard ended else { return Theme.accent }
        return steps.last?.title == "已发送" ? Theme.green : Theme.neutralText
    }
}
