import AppKit
import QingzhouCore
import SwiftUI

/// One page of 设置; the first screen is a short menu of these, each showing how it is set now.
enum SettingsPage: String, CaseIterable, Identifiable {
    case knowledge = "知识库"
    case trigger = "关键词"
    case persona = "说话风格"
    case reply = "回复方式"
    case people = "回复谁"
    case connection = "微信和模型"
    case alert = "手机提醒"
    case proactive = "主动联系"
    case advanced = "高级"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .knowledge: return "book.closed"
        case .trigger: return "bolt"
        case .persona: return "person"
        case .reply: return "bubble.left"
        case .people: return "person.2"
        case .connection: return "cpu"
        case .alert: return "bell"
        case .proactive: return "paperplane"
        case .advanced: return "slider.horizontal.3"
        }
    }

    /// The menu, in groups: what is changed often first, rarely used things last.
    static let groups: [(title: String, pages: [SettingsPage])] = [
        ("常用", [.trigger, .persona]),
        ("回复", [.reply, .people]),
        ("其他", [.alert, .proactive]),
    ]

    /// Tests open a page directly (`--settings-at trigger`; older card names still work).
    static var initial: SettingsPage? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--settings-at"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "filter": return .people
        case "revisit", "broadcast": return .proactive
        default: return allCases.first { "\($0)" == args[i + 1] }
        }
    }
}

/// 设置: a short menu; each item opens its own page.
struct SettingsView: View {
    @EnvironmentObject var ctl: AutoReplyController
    @ObservedObject var docker: WindowDocker
    @Binding var showChooser: Bool
    @State private var page: SettingsPage? = SettingsPage.initial
    @State private var question = ""
    @State private var asking = false
    @State private var answer: (text: String, basis: String)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let page {
                    if page != .trigger { pageHeader(page) }   // 关键词 draws its own header
                    content(of: page)
                        .environment(\.sectionHeadersHidden, page != .people && page != .proactive && page != .advanced)
                } else {
                    menu
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .onAppear { ctl.ensureKBFresh() }
    }

    // MARK: Menu

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "设置")
            menuRow(.connection, title: "模型", value: modelValue).padding(.top, 6)
            ForEach(SettingsPage.groups, id: \.title) { group in
                Text(group.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub)
                    .padding(.top, 16).padding(.bottom, 2)
                ForEach(group.pages) { menuRow($0) }
            }
            Button { withAnimation(.easeOut(duration: 0.2)) { page = .advanced } } label: {
                Text("高级设置（节奏、上限、运行记录）›").font(.system(size: 13)).foregroundStyle(Theme.sub)
            }
            .buttonStyle(.plain).padding(.top, 16)
        }
    }

    /// The model in use, in two words (“OpenAI 极速”).
    private var modelValue: String {
        guard ctl.engine == .api, let api = ctl.activeApi else { return ctl.engine == .ollama ? "本机 \(ctl.ollamaModel)" : "Codex" }
        let note = api.modelChoices.first { $0.id == api.model }?.note ?? ""
        let short = note.contains("快") ? "极速" : note.contains("便宜") ? "省钱" : note.contains("聪明") ? "聪明" : api.model
        return "\(api.name) \(short)"
    }

    /// One menu row: icon in a pale circle, name, and either a summary under it or a value on the right.
    private func menuRow(_ p: SettingsPage, title: String? = nil, value: String? = nil) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { page = p } } label: {
            HStack(spacing: 12) {
                Image(systemName: p.icon).font(.system(size: 14)).foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32).background(Circle().fill(Theme.accentSoft))
                if let value {
                    Text(title ?? p.rawValue).font(.system(size: 14)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(value).font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title ?? p.rawValue).font(.system(size: 14)).foregroundStyle(.primary)
                        Text(summary(of: p)).font(.system(size: 13)).lineLimit(1)
                            .foregroundStyle(p == .alert && !alertOn ? Theme.amber : Theme.sub)
                    }
                    Spacer(minLength: 8)
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.sub.opacity(0.5))
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// How a page is set now, in a few words, so most of the time it need not be opened.
    private func summary(of p: SettingsPage) -> String {
        let o = ctl.options
        switch p {
        case .knowledge: return kbTitle
        case .trigger:
            let on = o.triggers.filter(\.enabled).count
            return on == 0 ? "没有开着的规则" : "\(on) 条开着"
        case .persona:
            let first = o.persona.split(separator: "\n").first.map(String.init) ?? ""
            return first.isEmpty ? "还没写，回复用默认说法" : first
        case .reply:
            return ctl.replyMode.rawValue + " · " + (o.assistMode ? "我确认后发" : "自动发")
                + (ctl.replyToGroups ? " · 回群聊" : "")
        case .people:
            return (ctl.replyToGroups ? "也回群聊" : "只回私聊") + " · 不回 \(o.neverReply.count) 人"
                + (o.onlyListOn ? " · 只回名单里的 \(o.onlyList.count) 人" : "")
        case .connection:
            if ctl.engine == .api, let api = ctl.activeApi { return "\(api.name) · \(api.model)" }
            return ctl.engine.short
        case .alert:
            return alertOn ? "开着" : "没开 · 不在电脑前时建议打开"
        case .proactive:
            let on = [(ctl.outreachEnabled, "到货和新品通知"), (o.revisitOn, "问候老客户"), (o.broadcastOn, "定时群发")]
                .filter(\.0).map(\.1)
            return on.isEmpty ? "都关着，只回复不主动发" : "只有" + on.joined(separator: "、") + "开着"
        case .advanced:
            return (ctl.dryRun ? "演练中 · " : "") + "节奏、上限、运行记录"
        }
    }

    private var alertOn: Bool { ctl.options.alertsOn && !ctl.alertAddress.isEmpty }

    // MARK: A page

    private func pageHeader(_ p: SettingsPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BackHeader(back: "设置", title: p.rawValue) { withAnimation(.easeOut(duration: 0.2)) { page = nil } }
            if ctl.isRunning, p == .reply || p == .connection {
                Label("运行中，先暂停才能改", systemImage: "pause.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.amber)
            }
        }
    }

    @ViewBuilder
    private func content(of p: SettingsPage) -> some View {
        switch p {
        case .knowledge: knowledge
        case .trigger: TriggerCard(back: { withAnimation(.easeOut(duration: 0.2)) { page = nil } })
        case .persona:
            PersonaCard()
            HistoryCard()
        case .reply: reply.disabled(ctl.isRunning)
        case .people:
            NeverReplyCard()
            FilterCard()
        case .connection: connection.disabled(ctl.isRunning)
        case .alert: AlertCard()
        case .proactive:
            CardBox {
                ToggleLine(title: "按许可主动联系", hint: "只限预留到货、和说过想知道新品的客户", isOn: $ctl.outreachEnabled)
            }
            RevisitCard()
            BroadcastCard()
        case .advanced:
            advancedCard.disabled(ctl.isRunning)
            logView
        }
    }

    // MARK: Window and model

    private var connection: some View {
        CardBox {
            SettingLine(title: "聊天窗口") {
                Text(ctl.pickedWindow?.appName ?? ctl.target.name).font(.system(size: 14)).foregroundStyle(Theme.sub)
                Button("更换") { showChooser = true }.controlSize(.small)
            }
            Divider()
            SettingLine(title: "回复模型", hint: engineHint) {
                Picker("", selection: $ctl.engine) {
                    ForEach(EngineChoice.allCases) { Text($0.short).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            if ctl.engine == .api { ApiList() }
            if ctl.engine == .ollama {
                SettingLine(title: "本机模型名") {
                    TextField("", text: $ctl.ollamaModel).textFieldStyle(.roundedBorder).frame(width: 130)
                }
            }
        }
    }

    private var engineHint: String {
        switch ctl.engine {
        case .codex: return "测试用，每条 20–30 秒；内容发到云端（地址电话已屏蔽）"
        case .api: return "直连云端模型，几秒一条；地址电话已屏蔽"
        case .ollama: return "在这台 Mac 上运行，聊天内容不出电脑（需要先装好 Ollama）"
        }
    }

    // MARK: 回复

    private var reply: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("回复哪些消息") {
                choice(ReplyMode.confident, title: "只回有把握的", hint: "知识库答得了的和寒暄才回，其余交给你")
                Divider().padding(.leading, 14)
                choice(ReplyMode.all, title: "全部回复", hint: "答不了的回“我确认一下再回复你”")
            }
            group("怎么发") {
                row { ToggleLine(title: "发之前让我确认", hint: "AI 写好放在首页，你点了才发", isOn: $ctl.options.assistMode) }
                Divider().padding(.leading, 14)
                row { ToggleLine(title: "有时分两条发", hint: "像真人一样，偶尔把话分成两条", isOn: $ctl.allowTwoMessages) }
            }
            VStack(alignment: .leading, spacing: 8) {
                group("客人发来的") {
                    row { ToggleLine(title: "回复群聊", isOn: $ctl.replyToGroups) }
                    Divider().padding(.leading, 14)
                    row { ToggleLine(title: "语音自动转文字", isOn: $ctl.voiceToText) }
                    Divider().padding(.leading, 14)
                    row { ToggleLine(title: "看懂客人发的图片", isOn: $ctl.options.picturesToModel) }
                }
                Text("图里有地址或电话的，只发屏蔽后的文字，不发图片本身。")
                    .font(.system(size: 13)).foregroundStyle(Theme.sub).padding(.horizontal, 14)
            }
        }
    }

    /// A titled group of rows, like a group in System Settings.
    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title).environment(\.sectionHeadersHidden, false)
            CardBox(padding: 0) {
                VStack(spacing: 0) { rows() }.clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44)
    }

    /// One of the reply modes: a row with a check mark when chosen.
    private func choice(_ mode: ReplyMode, title: String, hint: String) -> some View {
        Button { ctl.replyMode = mode } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14)).foregroundStyle(.primary)
                    Text(hint).font(.system(size: 13)).foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 8)
                if ctl.replyMode == mode {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 52)
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .buttonStyle(.plain)
    }

    // MARK: 知识库

    private var knowledge: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "知识库")
            CardBox {
                SettingLine(title: kbTitle, hint: kbFiles) {
                    Button("打开文件夹") { NSWorkspace.shared.open(ctl.kbFolder) }.controlSize(.small)
                }
                .help(ctl.kbFolder.path)
                if let skipped = ctl.kb?.skipped, !skipped.isEmpty {
                    Text("无法读取：\(skipped.joined(separator: "、"))").font(.system(size: 12)).foregroundStyle(Theme.amber)
                }
                HStack(spacing: 14) {
                    Button("换一个文件夹…", action: chooseFolder)
                    Button("重新读取") { ctl.reloadKB() }
                }
                .buttonStyle(.link).font(.system(size: 12)).disabled(ctl.isRunning)
                Divider()
                Text("试问一句（不会发给任何人）").font(.system(size: 13)).foregroundStyle(Theme.sub)
                HStack {
                    TextField("例如：水蜜桃怎么保存？", text: $question).textFieldStyle(.roundedBorder).onSubmit(ask)
                    Button(asking ? "想一下…" : "试一下", action: ask)
                        .disabled(asking || question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let answer {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(answer.text).font(.system(size: 14)).textSelection(.enabled)
                        Text(answer.basis).font(.system(size: 12)).foregroundStyle(Theme.sub)
                    }
                }
            }
        }
    }

    private var kbTitle: String {
        guard let kb = ctl.kb, !kb.isEmpty else { return "知识库是空的" }
        return "\(kb.files.count) 个文件 · \(kb.chunks.count) 段资料"
    }

    private var kbFiles: String {
        guard let kb = ctl.kb, !kb.isEmpty else { return "放进价格、发货、做法等文件（txt / md / csv），才会自动回复" }
        return kb.files.map { ($0 as NSString).deletingPathExtension }.joined(separator: "、")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = ctl.kbFolder
        panel.prompt = "用这个文件夹"
        if panel.runModal() == .OK, let url = panel.url { ctl.setKBFolder(url) }
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }
        asking = true
        answer = nil
        Task {
            let result = await ctl.askTest(q)
            asking = false
            if let error = result.error {
                answer = (error, "")
                return
            }
            guard let reply = result.reply else { return }
            var sources: [String] = []
            for id in reply.citations {
                if let s = result.hits.first(where: { $0.chunk.id == id })?.chunk.source, !sources.contains(s) { sources.append(s) }
            }
            let basis = !sources.isEmpty
                ? "· 依据：" + sources.map { ($0 as NSString).deletingPathExtension }.joined(separator: "、")
                : (reply.isSmallTalk ? "· 寒暄" : "· 知识库里没有依据：“只回有把握的”会交给你")
            answer = (reply.messages.joined(separator: "\n"), basis)
        }
    }

    // MARK: 高级

    private var advancedCard: some View {
        CardBox {
            SettingLine(title: "回复节奏") {
                Picker("", selection: pacingChoice) {
                    ForEach(PacingChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            ToggleLine(title: "后台运行", hint: "尽量不抢鼠标键盘；要切换聊天时，等你停手 10 秒", isOn: $ctl.backgroundMode)
            SettingLine(title: "每小时最多发 \(ctl.maxPerHour) 条") {
                Stepper("", value: $ctl.maxPerHour, in: 5...60, step: 5).labelsHidden()
            }
            SettingLine(title: "每位客户每小时最多 \(ctl.maxPerChatPerHour) 条") {
                Stepper("", value: $ctl.maxPerChatPerHour, in: 1...20).labelsHidden()
            }
            ToggleLine(title: "结合客户记忆", hint: "记住 \(ctl.memoryCount) 位客户 · 只存在这台 Mac", isOn: $ctl.useMemory)
            ToggleLine(title: "演练模式", hint: "写好回复但不发送", isOn: $ctl.dryRun)
            ToggleLine(title: "贴在聊天窗口旁边", hint: "跟着聊天窗口移动，宽度是它的一半", isOn: $docker.enabled)
            ToggleLine(title: "只回指定内容（调试用）", isOn: exactMode)
            if ctl.replyMode == .exact {
                TextField("只回这句话", text: $ctl.onlyReplyTo).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 14) {
                Button("打开客户记忆文件夹") { NSWorkspace.shared.open(ctl.memory.folder) }
                Button("打开备份文件夹") { NSWorkspace.shared.open(AutoReplyController.backupFolder) }
                    .help("每天自动备份一次客户记忆、知识库和设置，留最近 14 天")
            }
            .buttonStyle(.link).font(.system(size: 12))
        }
    }

    private var pacingChoice: Binding<PacingChoice> {
        Binding(get: { ctl.pacing.name == PacingConfig.fastTest.name ? .fast : .human },
                set: { ctl.pacing = $0.config })
    }

    private var exactMode: Binding<Bool> {
        Binding(get: { ctl.replyMode == .exact }, set: { ctl.replyMode = $0 ? .exact : .confident })
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "运行记录")
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(ctl.log.suffix(80).reversed()) { e in
                        Text("\(e.time.formatted(.dateTime.hour().minute().second()))  \(e.text)")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(color(of: e.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textSelection(.enabled).padding(10)
            }
            .frame(height: 200)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
        }
    }

    private func color(of kind: LogEntry.Kind) -> Color {
        switch kind {
        case .error: return Theme.badge
        case .warn: return Theme.amber
        case .sent: return Theme.green
        case .incoming: return Theme.blueText
        case .debug, .info: return Theme.sub
        }
    }
}
