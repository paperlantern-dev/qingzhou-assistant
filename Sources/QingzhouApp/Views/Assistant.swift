import QingzhouCore
import SwiftUI

/// 小轻舟's button: a small white circle with ✨ on the window's edge. Drag it up or down;
/// let go and it settles on the nearer side. It stays where it was put, also after a restart.
struct AssistantButton: View {
    let open: () -> Void
    @AppStorage("assistantButtonY") private var heightShare = 0.62
    @AppStorage("assistantButtonLeft") private var onLeft = false
    @State private var drag: CGSize = .zero
    @State private var hover = false
    private static let size: CGFloat = 38

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height, w = geo.size.width
            let x = onLeft ? 8 + Self.size / 2 : w - 8 - Self.size / 2
            let y = min(max(heightShare * h, Self.size), h - Self.size)
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .shadow(color: Theme.accent.opacity(hover ? 0.3 : 0.18), radius: hover ? 12 : 8, y: 2)
                .scaleEffect(hover ? 1.06 : 1)
                .contentShape(Circle())
                .onHover { hover = $0 }
                .onTapGesture(perform: open)
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { drag = $0.translation }
                    .onEnded { v in
                        let endX = x + v.translation.width, endY = y + v.translation.height
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            onLeft = endX < w / 2
                            heightShare = Double(min(max(endY / max(h, 1), 0.08), 0.92))
                            drag = .zero
                        }
                    })
                .help("问轻舟：说话或打字，问问题、改设置都行")
                .animation(.easeOut(duration: 0.15), value: hover)
                .position(x: x + drag.width, y: y + drag.height)   // last, so only the circle takes clicks
        }
    }
}

/// 小轻舟's panel: what was said and answered, the change list to confirm, quick questions,
/// and the box to type or speak into.
struct AssistantPanel: View {
    @EnvironmentObject var ctl: AutoReplyController
    let page: String
    let close: () -> Void
    @StateObject private var speech = SpeechInput()
    @State private var plan: SettingsPlan?
    @State private var applied: [String]?
    @State private var text = ""
    @State private var thinking = false
    @State private var waiting: String?   // what was just said, shown until the answer comes

    private let quick = ["今天怎么样", "谁在等我回", "试试客人问", "帮我补全关键词"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if ctl.assistantChat.isEmpty { hello }
                        ForEach(ctl.assistantChat) { bubble($0) }
                        if let plan, !plan.changes.isEmpty || !plan.problems.isEmpty { planCard(plan) }
                        if let applied { appliedLine(applied) }
                        if let waiting { bubble(ChatTurn(mine: true, text: waiting)) }
                        if thinking { ProgressView().controlSize(.small).padding(.leading, 6) }
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .onChange(of: ctl.assistantChat) { withAnimation { proxy.scrollTo("end") } }
                .onAppear { proxy.scrollTo("end") }
                .onChange(of: plan) { withAnimation { proxy.scrollTo("end") } }
            }
            if ctl.assistantChat.isEmpty && !speech.listening { chips }
            if speech.listening || speech.problem != nil { listeningLine }
            inputRow
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous).fill(Theme.card)
            .shadow(color: .black.opacity(0.1), radius: 20, y: -4))
        .onAppear { ctl.loadChat() }
        .onDisappear { speech.stop() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule().fill(Theme.line).frame(width: 36, height: 5)
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                Text("小轻舟").font(.system(size: 15, weight: .bold))
                Spacer()
                Text("在“\(page)”页").font(.system(size: 12)).foregroundStyle(Theme.sub)
                if !ctl.assistantChat.isEmpty {
                    Button { ctl.clearChat(); plan = nil; applied = nil } label: {
                        Label("新对话", systemImage: "square.and.pencil").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).help("清空记录，重新开始")
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.sub)
                        .frame(width: 28, height: 28).background(Circle().fill(Theme.neutralSoft))
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
        }
    }

    private var hello: some View {
        Text("想改什么、想问什么，直接说。比如“售后加上发霉”“水蜜桃改成 88 一斤”“今天回了多少”。")
            .font(.system(size: 14)).foregroundStyle(Theme.sub).padding(.vertical, 6)
    }

    private func bubble(_ line: ChatTurn) -> some View {
        HStack {
            if line.mine { Spacer(minLength: 40) }
            Text(line.text).font(.system(size: 14)).textSelection(.enabled)
                .foregroundStyle(line.mine ? Color.white : Color.primary)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: line.mine ? 16 : 4,
                                                   bottomTrailingRadius: line.mine ? 4 : 16, topTrailingRadius: 16,
                                                   style: .continuous)
                    .fill(line.mine ? Theme.accent : Theme.neutralSoft.opacity(0.8)))
            if !line.mine { Spacer(minLength: 40) }
        }
    }

    private func planCard(_ plan: SettingsPlan) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(plan.changes.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.accent).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.summary).font(.system(size: 14))
                        if case .setPersona(let p) = c {
                            Text(p).font(.system(size: 12)).foregroundStyle(Theme.sub).lineLimit(6)
                        }
                    }
                }
            }
            ForEach(plan.problems, id: \.self) { p in
                Label(p, systemImage: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(Theme.amber)
            }
            if ctl.engine == .ollama, !plan.changes.isEmpty {
                Text("本机模型理解力弱一些，确认前请看仔细").font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
            if !plan.changes.isEmpty {
                HStack(spacing: 8) {
                    Button("确认修改") {
                        ctl.applySettings(plan.changes)
                        applied = plan.changes.map(\.summary)
                        ctl.addChat("已确认修改：" + plan.changes.map(\.summary).joined(separator: "；"), mine: false)
                        self.plan = nil
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 32)).fixedSize()
                    Button("取消") { self.plan = nil }.buttonStyle(SoftButtonStyle(height: 32))
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func appliedLine(_ done: [String]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            Text("改好了").font(.system(size: 14, weight: .semibold))
            Spacer()
            if ctl.settingsUndo != nil {
                Button("撤销") { ctl.undoSettings(); applied = nil; ctl.addChat("已经撤销，恢复成原来的样子。", mine: false) }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(quick, id: \.self) { q in
                // 试试客人问 only starts the sentence; the owner says what the customer asks.
                Button(q) { if q == "试试客人问" { text = "客人问：" } else { send(q) } }.buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(Theme.neutralText)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            }
        }
    }

    /// As drawn: bars in the middle, the words (or "正在听") under them, stops by itself.
    private var listeningLine: some View {
        VStack(spacing: 8) {
            if let problem = speech.problem {
                Label(problem, systemImage: "mic.slash").font(.system(size: 13)).foregroundStyle(Theme.amber)
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<9, id: \.self) { i in
                        Capsule().fill(Theme.accent.opacity(i % 2 == 0 ? 1 : 0.6))
                            .frame(width: 4, height: 6 + CGFloat(max(speech.level, 0.25)) * CGFloat([0, 6, 12, 4, 16, 8, 2, 10, 0][i]))
                    }
                }
                .frame(height: 22)
                .animation(.easeOut(duration: 0.1), value: speech.level)
                if speech.text.isEmpty {
                    Text("正在听… 说完会自动停").font(.system(size: 13)).foregroundStyle(Theme.sub)
                } else {
                    Text(speech.text).font(.system(size: 14)).multilineTextAlignment(.center).lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField(speech.listening ? "也可以打字" : "说话或打字，问什么、改什么都行", text: $text).textFieldStyle(.plain).font(.system(size: 14))
                .padding(.horizontal, 14).frame(height: 40)
                .background(Capsule().fill(Theme.neutralSoft.opacity(0.8)))
                .onSubmit { send(text) }
            Button {
                if speech.listening { speech.stop() } else { speech.start { send($0) } }
            } label: {
                Image(systemName: "mic.fill").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.accent))
                    .background(Circle().fill(Theme.accentSoft).padding(speech.listening ? -6 : 0))
                    .animation(.easeOut(duration: 0.2), value: speech.listening)
            }
            .buttonStyle(.plain)
            .help(speech.listening ? "再点一下就停" : "点一下说话")
        }
    }

    private func send(_ raw: String) {
        let request = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !thinking else { return }
        text = ""
        applied = nil
        plan = nil
        thinking = true
        waiting = request
        Task {
            let result = await ctl.talkToAssistant(request, page: page)
            waiting = nil
            thinking = false
            plan = result
        }
    }
}
