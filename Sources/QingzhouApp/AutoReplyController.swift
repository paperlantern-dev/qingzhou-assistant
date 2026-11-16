import AppKit
import QingzhouCore
import ScreenCaptureKit
import SwiftUI

enum EngineChoice: String, CaseIterable, Identifiable {
    case codex = "Codex CLI（临时，云端）"
    case api = "API 直连"
    case ollama = "Ollama 本机模型"
    var id: String { rawValue }
    var short: String { self == .codex ? "Codex（慢）" : self == .api ? "API 直连（快）" : "Ollama（本机）" }
    var isCloud: Bool { self != .ollama }
}

/// Which incoming messages get an automatic reply.
enum ReplyMode: String, CaseIterable, Identifiable {
    case all = "全部回复"
    case confident = "只回有把握的"
    case exact = "只回指定内容"
    var id: String { rawValue }

    var hint: String {
        switch self {
        case .all: return "知识库答不了的，回“我确认一下再回复你”"
        case .confident: return "知识库答得了的和寒暄才回，其余放到首页交给你"
        case .exact: return "只回内容完全相同的消息（调试用）"
        }
    }
}

/// A message the assistant chose not to answer, waiting for the user.
struct HumanItem: Identifiable {
    let id = UUID()
    let time = Date()
    let chat: String      // ChatID
    let who: String
    let message: String
    let reason: String
}

struct LogEntry: Identifiable {
    enum Kind { case debug, info, incoming, sent, warn, error }
    let id = UUID()
    let time = Date()
    let kind: Kind
    let text: String
}

/// Watches the target chat window and replies automatically with human-like timing.
@MainActor
final class AutoReplyController: ObservableObject {
    static let shared = AutoReplyController()
    /// Test runs change settings without saving them over the user's own.
    static var saveSettings = true

    private static func save(_ value: Any, _ key: String) {
        if saveSettings { UserDefaults.standard.set(value, forKey: key) }
    }

    @Published var target: ChatTarget = .weChat
    /// The exact window the user connected with “选择窗口” (nil = the app's main window).
    @Published var pickedWindow: PickedWindow?
    @Published var isPicking = false
    private let picker = WindowPicker()
    @Published var engine = EngineChoice(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .codex {
        didSet { Self.save(engine.rawValue, "engine") }
    }
    /// The model 本机 (Ollama) uses; kept between launches.
    @Published var ollamaModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? "qwen3:8b" {
        didSet { Self.save(ollamaModel, "ollamaModel") }
    }
    @Published var pacing: PacingConfig = .human
    @Published var isRunning = false
    @Published var status = "未启动"
    @Published var screenshot: NSImage?
    @Published var bubbles: [ChatBubble] = []
    @Published var chatTitle = ""
    /// All text recognized in the connected window (shown for apps that are not calibrated).
    @Published var windowText: [String] = []
    @Published var log: [LogEntry] = []
    @Published var sentCount = 0
    @Published var hasScreenPermission = WindowCapture.hasPermission
    @Published var hasAccessibility = AutoSender.isTrusted
    @Published var kbFolder: URL = AutoReplyController.defaultKBFolder
    @Published var kb: KnowledgeBase?
    @Published var replyMode = ReplyMode(rawValue: UserDefaults.standard.string(forKey: "replyMode") ?? "") ?? .all {
        didSet { Self.save(replyMode.rawValue, "replyMode") }
    }
    /// Messages not answered in “only confident” mode; shown in the panel and on the Dock icon.
    @Published var needsHuman: [HumanItem] = [] { didSet { updateDockBadge() } }
    /// 辅助模式: replies waiting on 首页 for the user to send.
    @Published var drafts: [Draft] = [] { didSet { updateDockBadge() } }
    /// The reply being worked on, step by step (shown live on 首页).
    @Published var steps: [ReplyStep] = []
    /// 不回名单, 辅助模式, 手机提醒 and 主动智能 settings.
    @Published var options = AssistantOptions.load() { didSet { if Self.saveSettings { options.save() } } }
    /// The group robot's webhook for 手机提醒 (kept in the Keychain: it contains a key).
    @Published var alertAddress = Keychain.read("alertWebhook") ?? "" {
        didSet { if Self.saveSettings, !Keychain.save(alertAddress, account: "alertWebhook") { add(.error, "提醒地址没能存进钥匙串") } }
    }
    /// What the owner taught through drafts (kept next to the customer memory).
    lazy var lessons = LessonStore(folder: memory.folder.appendingPathComponent("店主反馈", isDirectory: true))
    /// Questions the knowledge base could not answer, and what the owner replied (从我的回复学知识).
    lazy var answerStore = AnswerSuggestionStore(folder: memory.folder.appendingPathComponent("店主反馈", isDirectory: true))
    /// Answers waiting on 首页 for the owner to put into the knowledge base.
    @Published var answerSuggestions: [AnswerSuggestion] = []
    /// “✨ 跟轻舟说”: what the last confirmed change list replaced, for 撤销.
    @Published var settingsUndo: SettingsUndo?
    /// 读以前的聊天: progress of the current or last run.
    @Published var history: HistoryRun?
    var historyTask: Task<Void, Never>?
    /// 商品照片 already sent, by chat and file: the same photo goes to a customer once a day.
    var photoSent: [String: Date] = [:]
    /// 读屏自检: what is wrong with the reading (auto-reply stopped because of it), and a notice
    /// after the chat app was updated.
    @Published var screenProblem: String?
    @Published var updateNotice: String?
    var screenChecked = false
    /// The talk with 小轻舟, kept on this Mac.
    lazy var dayLog = DayLog(folder: memory.folder.appendingPathComponent("店主反馈", isDirectory: true))
    /// The day whose 小结 the owner closed (yyyy-MM-dd).
    @Published var summaryClosed = UserDefaults.standard.string(forKey: "summaryClosed") ?? "" {
        didSet { Self.save(summaryClosed, "summaryClosed") }
    }
    lazy var chatLog = ChatLog(folder: memory.folder.appendingPathComponent("店主反馈", isDirectory: true))
    @Published var assistantChat: [ChatTurn] = []
    /// For “only exact” mode: messages exactly matching one of these (comma separated) get a reply.
    @Published var onlyReplyTo = UserDefaults.standard.string(forKey: "onlyReplyTo") ?? "你好" {
        didSet { Self.save(onlyReplyTo, "onlyReplyTo") }
    }
    /// Rehearsal: open chats and generate replies, but never paste or send.
    @Published var dryRun = false
    /// Like a person: sometimes a reply is two short messages (never more).
    @Published var allowTwoMessages = UserDefaults.standard.object(forKey: "allowTwoMessages") as? Bool ?? true {
        didSet { Self.save(allowTwoMessages, "allowTwoMessages") }
    }
    /// Contact a customer first only with their permission: a reservation they asked for, or
    /// news after they said “有好东西告诉我”. Never chasing orders or repurchase reminders.
    @Published var outreachEnabled = UserDefaults.standard.object(forKey: "outreachEnabled") as? Bool ?? true {
        didSet { Self.save(outreachEnabled, "outreachEnabled") }
    }
    /// Hours of the day when such messages may be sent.
    var outreachHours = 9..<21
    struct OutreachJob: Identifiable {
        let id = UUID()
        let chat: String
        let who: String
        let reason: PromptBuilder.Outreach
        var due: Date
        var label: String {
            switch reason {
            case .reservationArrived(let r): return "预留到货：\(r.item)"
            case .news(let text, _): return "新品通知：\(text.prefix(20))"
            case .revisit(let days): return "主动问候（\(days) 天没聊）"
            case .broadcast(let text): return "定时群发：\(text.prefix(16))"
            }
        }
    }
    @Published var outreachQueue: [OutreachJob] = []
    /// Plain-language record of what happened today, for the home screen.
    @Published var activity: [Activity] = []
    /// Remembered customers, for the panel (reservations, who welcomes news).
    @Published var customers: [CustomerRecord] = []

    /// Per-customer memory on this Mac: earlier chat and key points go into each reply.
    @Published var useMemory = UserDefaults.standard.object(forKey: "useMemory") as? Bool ?? true {
        didSet { Self.save(useMemory, "useMemory") }
    }
    let memory: CustomerMemoryStore = {
        let args = CommandLine.arguments   // tests keep their memory apart from the user's
        if let i = args.firstIndex(of: "--memory"), i + 1 < args.count {
            return CustomerMemoryStore(folder: URL(fileURLWithPath: args[i + 1]))
        }
        return CustomerMemoryStore()
    }()
    @Published var memoryCount = 0
    var summarizing: Set<String> = []

    /// Voice messages: use WeChat's “转文字” automatically (otherwise they go to “需要你处理”).
    @Published var voiceToText = UserDefaults.standard.object(forKey: "voiceToText") as? Bool ?? true {
        didSet { Self.save(voiceToText, "voiceToText") }
    }
    /// Type and send in the background; only switching chats uses the mouse, and only when idle.
    @Published var backgroundMode = UserDefaults.standard.object(forKey: "backgroundMode") as? Bool ?? true {
        didSet { Self.save(backgroundMode, "backgroundMode") }
    }
    /// Test runs only: answer just the chat whose name contains this (normalized), nothing else.
    var onlyChat: String?
    /// Test runs only: never open another chat; answer just the one already open.
    var stayInOpenChat = false
    /// How long the user must leave mouse and keyboard alone before a click is made.
    var idleSeconds: Double = 10
    /// Group chats are skipped unless this is on.
    @Published var replyToGroups = UserDefaults.standard.bool(forKey: "replyToGroups") {
        didSet { Self.save(replyToGroups, "replyToGroups") }
    }
    @Published var maxPerHour = AutoReplyController.storedInt("maxPerHour", 20) {
        didSet { Self.save(maxPerHour, "maxPerHour") }
    }
    @Published var maxPerChatPerHour = AutoReplyController.storedInt("maxPerChatPerHour", 5) {
        didSet { Self.save(maxPerChatPerHour, "maxPerChatPerHour") }
    }

    private static func storedInt(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
    var limiter = SendLimiter(maxPerHour: 20, maxPerChatPerHour: 5)

    private var loopTask: Task<Void, Never>?
    private var lastFingerprint: [UInt8] = []
    /// Per chat (ChatID: group/person + name): the last pending message set already answered.
    private var handled: [String: String] = [:]
    /// Force a fresh read on the next tick (e.g. after replying, more badges may be waiting).
    var needsLook = false
    private var skippedLogged: Set<String> = []

    /// Chat names come from OCR and can differ by a character (emoji, punctuation), so compare loosely.
    private func handledKey(for chat: String) -> String {
        handled.first { ChatID.same($0.key, chat) }?.value ?? ""
    }

    func markHandled(_ chat: String, _ key: String) {
        if let existing = handled.keys.first(where: { ChatID.same($0, chat) }) { handled[existing] = nil }
        handled[chat] = key
    }

    private var allowList: [String] {
        onlyReplyTo.split(whereSeparator: { ",，".contains($0) })
            .map { TextMatch.normalize(String($0)) }.filter { !$0.isEmpty }
    }

    /// True unless “only exact” mode is on and the text is not in its list.
    private func isAllowed(_ text: String) -> Bool {
        guard replyMode == .exact else { return true }
        let list = allowList
        return list.isEmpty || list.contains(TextMatch.normalize(text))
    }

    /// Puts a message on the “needs a person” list (one entry per chat, newest message).
    func addHuman(chat: String, who: String, message: String, reason: String = "知识库里没有答案") {
        needsHuman.removeAll { ChatID.same($0.chat, chat) }
        needsHuman.append(HumanItem(chat: chat, who: who, message: message, reason: reason))
        add(.warn, "「\(who)」\(reason)，已放到首页“需要你处理”，请你来回复")
        note(.handedOver, who: who, title: "\(reason) · 交给你", detail: "“\(message)”")
        NSSound.beep()
        alertIfWanted(chat: chat, who: who, message: message, reason: reason)
    }

    func resolveHuman(_ id: UUID) { needsHuman.removeAll { $0.id == id } }
    func clearHuman() { needsHuman.removeAll() }
    var lastSendAt = Date.distantPast
    /// After a failed click into a chat, wait a while instead of retrying every round.
    private var openFailedAt = Date.distantPast
    private var failedKey = ""
    private var failedChat = ""
    private var failedAt = Date.distantPast
    private var rng = SystemRandomNumberGenerator()

    func refreshPermissions() {
        hasScreenPermission = WindowCapture.hasPermission
        hasAccessibility = AutoSender.isTrusted
    }

    /// “选择窗口”: the next window the user clicks becomes the one to watch.
    func pickWindow() {
        guard !isRunning, !isPicking else { return }
        isPicking = true
        status = "请点击要连接的聊天窗口（Esc 取消）"
        picker.start { [weak self] picked in
            guard let self else { return }
            self.isPicking = false
            guard let picked else { self.status = "已取消选择窗口"; return }
            self.connect(picked)
        }
    }

    /// Connects a window (from the list or by clicking it) and starts showing it live.
    func connect(_ picked: PickedWindow) {
        pickedWindow = picked
        target = ChatTarget.forApp(bundleID: picked.bundleID, name: picked.appName)
        lastFingerprint = []
        let ready = target.supportsAutoReply ? "可以自动回复" : "还没适配，只能查看，不会自动回复"
        add(.info, "已连接窗口：\(picked.label) · \(ready)")
        status = "已连接：\(picked.appName)"
        startPreview()
    }

    private var previewTask: Task<Void, Never>?

    /// While auto-reply is off, keeps showing the connected window (screenshot + text) every 2 s.
    func startPreview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                if !self.isRunning { _ = await self.read(forceOCR: false) }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        guard target.supportsAutoReply else {
            add(.error, "「\(target.name)」还没适配自动回复：可以查看截图，但不会点击或发送")
            return
        }
        if !WindowCapture.hasPermission { WindowCapture.requestPermission() }
        if !AutoSender.isTrusted { AutoSender.requestTrust() }
        refreshPermissions()
        backupIfDue()   // the app may stay open for days
        isRunning = true
        screenChecked = false
        screenProblem = nil
        updateNotice = nil
        startEscWatcher()
        lastFingerprint = []
        limiter.maxPerHour = maxPerHour
        limiter.maxPerChatPerHour = maxPerChatPerHour
        add(.info, "开始监听：\(target.name) · \(pacing.name)")
        add(.debug, "输入事件自检：" + AutoSender.diagnose())
        reloadKB()
        loopTask = Task { [weak self] in
            while let self, self.isRunning, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        isRunning = false
        stopEscWatcher()
        loopTask?.cancel()
        loopTask = nil
        status = "已停止"
        add(.info, "已停止")
    }

    func makeEngine() -> ReplyEngine {
        switch engine {
        case .codex: return CodexCLIEngine()
        case .api: return apiEngine()
        case .ollama: return OllamaEngine(model: ollamaModel)
        }
    }

    // MARK: - Reading the window

    struct Snapshot {
        let window: SCWindow
        let conversation: Conversation
        let rows: [UnreadRow]       // contact rows with a red badge, top first
        var listDebug = ""          // diagnostics: list text near the top
        var listNames: [UnreadRow] = []   // every contact row's name in the list (for follow-ups)
        let image: CGImage
        let inputText: String       // normalized text typed in the chat input box ("" if empty)
        var chat: String { ChatID.make(title: conversation.title) }
    }

    /// Captures and parses the target window. Returns nil (and sets status) on failure.
    func read(forceOCR: Bool) async -> Snapshot? {
        let window: SCWindow
        do {
            // The picked window first; if it was closed, the app's main window.
            var found: SCWindow?
            if let p = pickedWindow { found = try await WindowCapture.findWindow(id: p.windowID) }
            if found == nil { found = try await WindowCapture.findWindow(bundleID: target.bundleID) }
            guard let w = found else {
                status = "找不到「\(target.name)」的窗口（需要打开且在屏幕上）"
                return nil
            }
            window = w
        } catch {
            refreshPermissions()
            status = error.localizedDescription
            return nil
        }
        let capture: CaptureResult
        do { capture = try await WindowCapture.capture(window: window) } catch {
            status = error.localizedDescription
            return nil
        }
        let fp = WindowCapture.fingerprint(capture.image)
        if !forceOCR, fp == lastFingerprint { return nil }   // nothing changed on screen
        lastFingerprint = fp
        screenshot = NSImage(cgImage: capture.image, size: .zero)

        let image = capture.image
        followDividers(image, windowSize: window.frame.size)
        guard let ocr = try? await Task.detached(operation: { try OCRService.recognize(image) }).value else {
            status = "识字失败"
            return nil
        }
        let conv = ChatParser.parse(ocr.lines, windowSize: window.frame.size, layout: target.layout, image: image)
        let unread = UnreadDetector.badgeRows(in: image, windowSize: window.frame.size, layout: target.layout)
        let size = window.frame.size
        let rows = UnreadRowReader.rows(badges: unread, lines: ocr.lines, windowSize: size, layout: target.layout)
        bubbles = conv.bubbles
        chatTitle = conv.title
        windowText = ocr.lines.map(\.text)
        status = target.supportsAutoReply
            ? "监听中 · 当前会话「\(conv.title)」\(conv.bubbles.count) 条消息 · 左侧未读 \(unread.count) 个"
            : "正在查看「\(pickedWindow?.appName ?? target.name)」 · 识别到 \(ocr.lines.count) 行文字"
        // Text area of the input box: below the messages, above the bottom toolbar row.
        let inputText = ocr.lines.filter { l in
            let x = l.box.minX * size.width, top = (1 - l.box.maxY) * size.height
            let fromBottom = size.height - top
            return x >= target.layout.sidebarWidth && target.layout.inputTextFromBottom.contains(fromBottom)
                && l.text != "发送"
        }
        .map { TextMatch.normalize($0.text) }.joined()
        var snap = Snapshot(window: window, conversation: conv, rows: rows, image: image, inputText: inputText)
        snap.listNames = ocr.lines.compactMap { l in
            let x = l.box.minX * size.width, top = (1 - l.box.maxY) * size.height
            guard x >= target.layout.rowTextMinX, x < target.layout.sidebarWidth - 50, top > target.layout.listTop,
                  !GroupChat.isTimeOrDate(l.text) else { return nil }
            return UnreadRow(y: top, name: l.text, preview: "")
        }
        defer { rememberIfCustomer(snap) }
        snap.listDebug = ocr.lines.filter { $0.box.minX * size.width < target.layout.sidebarWidth }
            .map { "\(Int((1 - $0.box.maxY) * size.height)):\(Int($0.box.minX * size.width)):\($0.text)" }
            .prefix(8).joined(separator: " ")
        return snap
    }

    // MARK: - Main loop

    private func tick() async {
        planRevisitsIfDue()   // 主动智能 and 定时群发: only when the user turned them on (no screen read needed)
        planBroadcastsIfDue()
        let retryDue = !failedKey.isEmpty && Date().timeIntervalSince(failedAt) >= 30
        let outreachDue = outreachQueue.contains { $0.due <= Date() && mayRun($0) }
        let draftDue = drafts.contains { $0.approved != nil }
        guard let snap = await read(forceOCR: retryDue || needsLook || outreachDue || draftDue) else { return }
        needsLook = false
        guard checkScreenOnce(snap) else { return }   // a wrong reading stops auto-reply

        // My newest message counts as an answer only if it went out (no red “!”).
        let answered = snap.conversation.bubbles.last.map { $0.fromMe && !$0.failed } ?? false
        if answered, let done = needsHuman.first(where: { ChatID.same($0.chat, snap.chat) }) {
            resolveHuman(done.id)
            add(.info, "「\(done.who)」已经回复过了，移出“需要你处理”")
        }
        if answered { dropAnsweredDrafts(chat: snap.chat) }
        if await sendApprovedDraft(snap) { needsLook = true; return }   // the user clicked 发送 on a draft

        // 1. The open chat has an unanswered message → reply to it.
        let key = snap.conversation.pendingKey
        let waitingRetry = ChatID.same(snap.chat, failedChat) && TextMatch.similar(key, failedKey)
            && Date().timeIntervalSince(failedAt) < 30
        // The filter looks at their newest message only; older ones are just context.
        let newest = snap.conversation.pendingIncoming.last?.text ?? ""
        let unanswered = !key.isEmpty && !TextMatch.similar(key, handledKey(for: snap.chat))
        if unanswered, !waitingRetry {
            if let why = skipReason(snap, newest: newest) {
                if skippedLogged.insert(snap.chat + key + why).inserted { add(.info, "「\(snap.conversation.title)」\(why)") }
            } else {
                await handle(snap)
                needsLook = true
                return
            }
        }
        // 2. Otherwise open the unread chat that has waited longest. The list puts the newest
        //    chat on top, so that is the bottom-most red badge.
        //    Each skipped row is logged with its own reason.
        if let why = limiter.blockReason(chat: "") {
            if !snap.rows.isEmpty, skippedLogged.insert("limit|\(why)").inserted { add(.warn, why) }
            return
        }
        var pick: UnreadRow?
        for row in snap.rows.reversed() {
            if row.name.isEmpty {   // not read cleanly: look again next round
                needsLook = true
                add(.debug, "没读清楚的行：y=\(Int(row.y)) 全部列表文字=\(snap.listDebug)")
            }
            if let why = rowSkipReason(row) {
                if skippedLogged.insert(TextMatch.normalize(row.name + row.preview) + why).inserted {
                    add(.info, "「\(row.name)」\(why)")
                }
            } else {
                pick = row
                break
            }
        }
        if pick == nil, snap.rows.allSatisfy({ !$0.name.isEmpty }) {
            await runOutreach(snap)   // nothing waiting: send a permitted message (reservation, news)
            return
        }
        if pick != nil, Date().timeIntervalSince(openFailedAt) <= 20 { needsLook = true }   // retry after the pause
        if let row = pick, Date().timeIntervalSince(openFailedAt) > 20 {
            await openChat(row, from: snap)
            needsLook = true
        }
    }

    /// Why an unread row in the list must not be opened, or nil if it may.
    private func rowSkipReason(_ row: UnreadRow) -> String? {
        if stayInOpenChat { return "测试中，只回当前打开的会话，不点开" }
        if row.name.isEmpty { return "（这一行没读清楚，列表可能在变动，先不点开）" }
        if let only = onlyChat, !TextMatch.normalize(row.name).contains(only) { return "不在本次测试的会话里，不点开" }
        if SystemChat.isSystem(row.name) { return "是公众号/系统通知，不点开" }
        if isNeverReply(row.name) { return "在“不自动回复”名单里，不点开" }
        if let why = listSkipReason(row.name, opening: true) { return why }
        if !replyToGroups, GroupChat.looksLikeGroupPreview(row.preview) {
            return "的预览是“昵称: 消息”，像群聊，不点开（预览：\(row.preview)）"
        }
        if !isAllowed(row.preview) {
            return "的最新消息不在“只回指定内容”名单里，不点开（预览：\(row.preview)）"
        }
        return nil
    }

    /// Why the open chat's new message must not be answered, or nil if it may.
    private func skipReason(_ snap: Snapshot, newest: String) -> String? {
        if let only = onlyChat, !snap.chat.contains(only) { return "不在本次测试的会话里，不回复" }
        if SystemChat.isSystem(snap.conversation.title) { return "是公众号/系统通知，不回复" }
        if isNeverReply(snap.conversation.title) { return "在“不自动回复”名单里，不回复" }
        if let why = listSkipReason(snap.conversation.title, opening: false) { return why }
        if let why = groupAtSkipReason(snap, newest: newest) { return why }
        if !replyToGroups, GroupChat.isGroupTitle(snap.conversation.title) { return "是群聊（标题带人数），按设置不回复" }
        if !isAllowed(newest) { return "的新消息不在“只回指定内容”名单里，跳过（\(newest)）" }
        if let why = limiter.blockReason(chat: snap.chat) { return "：" + why }
        return nil
    }

    /// Clicks a contact row in the sidebar and checks that its chat actually opened.
    /// Before each click it re-captures the window and only clicks if that row still looks
    /// exactly the same: a new message can reorder the list between looking and clicking.
    func openChat(_ unread: UnreadRow, from snap: Snapshot) async {
        let row = unread.y
        guard let pid = snap.window.owningApplication?.processID else { return }
        let f = snap.window.frame
        let point = CGPoint(x: f.minX + target.layout.sidebarWidth * 0.6, y: f.minY + row + 15)
        // The opened chat's title should contain the row's name (names may be cut off with “…”).
        let expected = [unread.name].map { TextMatch.normalize($0) }.filter { $0.count >= 2 }
        let before = WindowCapture.rowFingerprint(snap.image, windowWidth: f.width,
                                                  sidebarWidth: target.layout.sidebarWidth, rowCenterY: row)
        guard await waitForIdle(before: "点开「\(unread.name)」") else { return }
        add(.info, "左侧有未读消息，点开「\(unread.name)」")
        do {
            for attempt in 1...2 {
                guard let w = try await WindowCapture.findWindow(bundleID: target.bundleID),
                      w.frame == f else { add(.debug, "窗口移动了，先不点"); return }
                let fresh = try await WindowCapture.capture(window: w)
                let nowRow = WindowCapture.rowFingerprint(fresh.image, windowWidth: f.width,
                                                          sidebarWidth: target.layout.sidebarWidth, rowCenterY: row)
                guard nowRow == before else {
                    add(.info, "会话列表刚刚变动，先不点，重新看一遍")
                    return
                }
                try await AutoSender.click(point, inPID: pid, windowFrame: f)
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard let now = await read(forceOCR: true) else { return }
                if !ChatID.same(now.chat, snap.chat) {
                    let matches = expected.contains { now.chat.contains($0) || TextMatch.similar(now.chat, $0) }
                    if !expected.isEmpty, !matches {
                        add(.warn, "打开的是「\(now.conversation.title)」，和预期的「\(unread.name)」不一致")
                    } else {
                        add(.info, "已打开会话「\(now.conversation.title)」")
                    }
                    return
                }
                if attempt == 1 { try? await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.2) * 1e9)) }
            }
            add(.warn, "点了未读会话，但当前会话没有变化")
        } catch {
            refreshPermissions()
            openFailedAt = Date()
            add(.error, "点开会话失败：\(error.localizedDescription)（20 秒后再试）")
        }
    }

    private func handle(_ snap: Snapshot) async {
        let key = snap.conversation.pendingKey
        let chat = snap.chat
        let who = snap.conversation.title.isEmpty ? "对方" : snap.conversation.title
        let incoming = snap.conversation.pendingIncoming.map(\.text).joined(separator: " / ")
        add(.incoming, "【\(who)】\(incoming)")
        beginSteps(who: who, said: incoming)
        defer { endStepsIfOpen() }   // a reply that stops without sending ends its stream with “没有发送”

        // A voice message without words: get them with “转文字” first, then answer as usual.
        if let voice = snap.conversation.pendingIncoming.last, voice.needsTranscript {
            let label = voice.text
            guard voiceToText else {
                markHandled(chat, key)
                addHuman(chat: chat, who: who, message: label, reason: "发来语音（自动转文字已关闭）")
                return
            }
            add(.info, "【\(who)】发来语音\(voice.voiceSeconds ?? 0)秒，自动转文字")
            if await transcribe(voice, in: snap), let fresh = await read(forceOCR: true),
               ChatID.same(fresh.chat, chat), fresh.conversation.pendingIncoming.last?.needsTranscript == false {
                add(.info, "【\(who)】语音转文字：\(fresh.conversation.pendingIncoming.last?.text ?? "")")
                note(.voice, who: who, title: "发来语音，已转文字", detail: fresh.conversation.pendingIncoming.last?.text ?? "")
                await handle(fresh)
            } else {
                markHandled(chat, key)
                addHuman(chat: chat, who: who, message: label, reason: "发来语音，自动转文字没成功")
            }
            return
        }
        // 关键词触发: a set text or picture, or straight to the owner.
        if await handleTrigger(snap, chat: chat, who: who, key: key, incoming: incoming) { return }
        // 看图: new pictures are read here; only stickers means nothing to answer.
        let pics = await preparePictures(snap)
        defer { removePictureFiles(pics.files) }
        if pics.stickersOnly { markHandled(chat, key); add(.info, "【\(who)】只发了表情，不用回"); return }

        let pacer = HumanPacer(config: pacing)
        let readDelay = pacer.readDelay(using: &rng)
        let started = Date()
        status = "已看到新消息，生成回复中…"

        // The model may only answer after reading the knowledge base.
        ensureKBFresh()
        guard let kb, !kb.isEmpty else {
            failedChat = chat; failedKey = key; failedAt = Date()
            add(.error, "知识库为空（\(kbFolder.path)），不回复。请放入资料后再试。")
            return
        }
        let query = pics.conversation.pendingIncoming.map(\.text).joined(separator: " ")
        let hits = kb.passages(for: query).map { (chunk: $0, score: 0.0) }
        add(.info, hits.isEmpty ? "检索知识库：没有找到相关资料"
            : hits.count == kb.chunks.count ? "知识库不大，整份 \(hits.count) 段都给模型看"
            : "检索知识库：" + hits.map { "[\($0.chunk.id)] \($0.chunk.source)" }.joined(separator: "、"))
        step("检索知识库", hits.isEmpty ? "没有找到相关资料" : Set(hits.map(\.chunk.source)).sorted().joined(separator: "、"))

        let photo = productPhoto(for: snap)
        let raw: ReplyResult
        var memoryGiven = false
        do {
            let record = useMemory ? memory.record(for: chat) : nil
            let earlier = record.map { CustomerMemoryStore.earlier(in: $0, visible: snap.conversation.bubbles) } ?? []
            memoryGiven = record.map { !$0.summary.isEmpty || !earlier.isEmpty } ?? false
            if let record, !record.summary.isEmpty || !earlier.isEmpty {
                add(.info, "带上客户记忆：\(record.summary.isEmpty ? "" : "要点 + ")更早的 \(earlier.count) 条聊天")
            }
            raw = try await makeEngine().reply(
                to: PromptBuilder.build(conversation: pics.conversation, knowledge: hits.map(\.chunk),
                                        memory: record, earlier: earlier, lessons: lessons.promptText(for: incoming),
                                        persona: replyPersona + (photo.map { "\n\n" + ProductPhotos.promptNote($0) } ?? "")),
                    images: pics.files)
        } catch {
            failedChat = chat; failedKey = key; failedAt = Date()
            add(.error, error.localizedDescription)
            return
        }
        guard isRunning else { return }
        guard let parsed = ReplyParser.parse(raw.text, allowed: Set(hits.map(\.chunk.id)), memoryGiven: memoryGiven) else {
            failedChat = chat; failedKey = key; failedAt = Date()
            add(.error, "模型没有按“类型/引用/回复”格式回答，未发送：\(raw.text.prefix(80))")
            return
        }
        recordPermissions(parsed, chat: chat, who: who,
                          quote: snap.conversation.pendingIncoming.map(\.text).joined(separator: " "))
        // “发张图看看”: nothing to look up, the photo is the answer.
        let photoAnswers = photo != nil && !parsed.isConfident
        if !parsed.isConfident, !photoAnswers { watchForOwnerAnswer(chat: chat, who: who, question: incoming) }
        // The model only saw ［地址］/［电话］ placeholders: a reply that needs them goes to the owner.
        if Privacy.containsPlaceholder(parsed.text) || parsed.second.map(Privacy.containsPlaceholder) == true {
            markHandled(chat, key)
            addHuman(chat: chat, who: who, message: incoming, reason: "回复要用到地址或电话（这些不发给云端）")
            return
        }
        // “Only confident”: no knowledge-base answer and not small talk → leave it to the user.
        if !parsed.isConfident, !photoAnswers, replyMode == .confident {
            markHandled(chat, key)
            addHuman(chat: chat, who: who, message: incoming)
            return
        }
        let reply = ReplyResult(text: photoAnswers ? "发你看下" : parsed.text, engineLabel: raw.engineLabel, durationMs: raw.durationMs)
        let basis = parsed.hasBasis
            ? "依据 " + parsed.citations.map { id in "[\(id)] \(kb.chunks.first { $0.id == id }?.source ?? "")" }.joined(separator: "、")
            : photoAnswers ? "有照片，直接发"
            : parsed.usedMemory ? "依据客户记忆"
            : (parsed.isSmallTalk ? "寒暄，无需资料" : "知识库里没有答案，暂缓答复")
        step("写好回复", reply.text)
        if options.assistMode, !dryRun {   // 辅助模式: it waits on 首页 until the user clicks 发送
            step("放到首页，等你确认")
            markHandled(chat, key)
            let text = photoAnswers ? reply.text : DraftText.join(allowTwoMessages ? parsed.messages : [parsed.text])
            addDraft(chat: chat, who: who, question: incoming, text: text, basis: basis)
            if let photo { add(.info, "【\(who)】有「\(photo.product)」的照片可以发（确认后发的模式下不自动发图）") }
            return
        }

        // Act like a person: finish "reading", then "type" for a while.
        let typing = pacer.typingDelay(for: reply.text, using: &rng)
        let gapLeft = pacing.minGapBetweenSends - Date().timeIntervalSince(lastSendAt)
        let total = HumanPacer.waitBeforeSending(read: readDelay, typing: typing,
                                                 elapsed: Date().timeIntervalSince(started), gapLeft: gapLeft)
        status = String(format: "回复已生成（%.1f 秒），%.0f 秒后发送", Double(reply.durationMs) / 1000, total)
        try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
        guard isRunning else { return }

        // Re-check: if they sent more, or someone already answered, don't send a stale reply.
        guard let now = await read(forceOCR: true) else { return }
        guard ChatID.same(now.chat, chat) else {
            add(.warn, "当前会话已不是「\(who)」，这条先不发，稍后重新处理")
            return
        }
        guard TextMatch.similar(now.conversation.pendingKey, key) else {
            add(.warn, now.conversation.pendingKey.isEmpty ? "已有人回复，放弃这条" : "对方又发了新消息，重新生成")
            return
        }

        if dryRun {
            markHandled(chat, key)
            add(.warn, "【\(who)】演练模式，不发送。拟回复：\(reply.text)（\(basis)）")
            return
        }
        do {
            step("正在输入", reply.text)
            guard let method = try await deliver(reply.text, in: now, chat: chat) else {
                guard isRunning else { return }   // paused while typing; nothing was sent
                failedChat = chat; failedKey = key; failedAt = Date()
                add(.error, "这条没有发出，或者没能在窗口里确认发出，30 秒后重试")
                return
            }
            step("已发送", method)
            markHandled(chat, key)
            failedKey = ""
            limiter.record(chat: chat)
            sentCount += 1
            add(.sent, "【\(who)】我：\(reply.text)\n\(basis) · \(method) · 已在窗口中确认 · 生成用时 \(reply.durationMs / 1000) 秒")
            note(.replied, who: who, title: "已回复", detail: "“\(reply.text)” · \(basis)", question: incoming, reply: reply.text)

            // Sometimes a second short message, a few seconds later, like a person typing on.
            if allowTwoMessages, !photoAnswers, let second = parsed.second, limiter.blockReason(chat: chat) == nil {
                let pause = pacer.typingDelay(for: second, using: &rng) + Double.random(in: 1...3)
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                if isRunning, let fresh = await read(forceOCR: true), ChatID.same(fresh.chat, chat),
                   fresh.conversation.pendingIncoming.isEmpty {   // they have not written in between
                    if let m2 = try await deliver(second, in: fresh, chat: chat) {
                        limiter.record(chat: chat)
                        sentCount += 1
                        add(.sent, "【\(who)】我（第二条）：\(second)\n\(m2) · 已在窗口中确认")
                        note(.replied, who: who, title: "补了一句", detail: "“\(second)”")
                    } else {
                        add(.warn, "第二条没有确认发出，不再重试：\(second)")
                    }
                }
            }
            if let photo { await sendProductPhoto(photo, chat: chat, who: who) }
            summarizeIfDue(chat)
        } catch is WeChatRefused {
            markHandled(chat, key)
            addHuman(chat: chat, who: who, message: incoming, reason: "回复没发出去（微信里是红色感叹号）")
        } catch {
            refreshPermissions()
            failedChat = chat; failedKey = key; failedAt = Date()
            add(.error, error.localizedDescription)
        }
    }

    /// Sends one message into the open chat (background typing, or paste as a fallback) and checks
    /// it shows up as my newest message. Returns how it was sent, or nil if it was not sent or not confirmed.
    /// Whichever way it goes, the screen is read again right before Return: another chat showing, a newer
    /// message, other words in the input box, an unreadable window or a pause all call the send off.
    func deliver(_ text: String, in snap: Snapshot, chat: String) async throws -> String? {
        guard var pid = snap.window.owningApplication?.processID else { throw SendError.appNotRunning }
        let snap = await clearStranded(in: snap, pid: pid)
        let key = snap.conversation.pendingKey
        var method = "后台发送"
        switch backgroundMode ? await sendInBackground(text, pid: pid, snapshot: snap, chat: chat) : .useForeground {
        case .sent: break
        case .calledOff: return nil
        case .useForeground:
            guard isRunning else { return nil }   // paused (暂停 / 双击 Esc) while typing: don't fall back to pasting
            if backgroundMode { guard await waitForIdle(before: "前台发送") else { return nil } }
            // Look again right before pasting: the chat may have changed while waiting.
            guard let screen = await read(forceOCR: true), let freshPID = screen.window.owningApplication?.processID else {
                add(.warn, "前台发送前没能看清聊天窗口，这条先不发")
                return nil
            }
            pid = freshPID
            guard isRunning else { return nil }
            if let why = SendCheck.problem(chat: chat, pendingKey: key, nowChat: screen.chat,
                                           nowPendingKey: screen.conversation.pendingKey, nowInput: screen.inputText) {
                add(.warn, "前台发送前又看了一眼：\(why)，这条先不发")
                return nil
            }
            let f = screen.window.frame
            let paneMidX = f.minX + target.layout.sidebarWidth + (f.width - target.layout.sidebarWidth) / 2
            let point = CGPoint(x: paneMidX, y: f.maxY - target.layout.inputClickFromBottom)
            add(.debug, "发送：窗口 \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height))，点击输入框 \(Int(point.x)),\(Int(point.y))")
            // Pasted, not yet sent: one more look, then Return.
            let pressed = try await AutoSender.send(text, toPID: pid, windowFrame: f, clickPoint: point) { [self] in
                await holdForTest()
                let pasted = await read(forceOCR: true)
                let why = pasted == nil ? "没能看清聊天窗口"
                    : !isRunning ? "已暂停"
                    : SendCheck.problem(chat: chat, pendingKey: key, nowChat: pasted!.chat,
                                        nowPendingKey: pasted!.conversation.pendingKey, nowInput: "")
                    ?? (Self.inputShows(pasted!.inputText, text) || TextMatch.normalize(text).count < 2 ? nil : "输入框里不是这条回复")
                guard let why else { return true }
                // Still this chat and only my text in the box: empty it. Otherwise leave the box alone.
                if let pasted, ChatID.same(pasted.chat, chat), SendCheck.isAssistantText(input: pasted.inputText, reply: text) {
                    await AutoSender.deletePastedText(characters: text.count + 2)
                } else if pasted.map({ !PictureCheck.inputLooksEmpty($0.inputText) || !ChatID.same($0.chat, chat) }) ?? true {
                    Self.stranded.append((chat, text))
                }
                add(.warn, "按发送前又看了一眼：\(why)，这条没有发出")
                return false
            }
            guard pressed else { return nil }
            method = "前台粘贴发送"
        }
        lastSendAt = Date()
        add(.debug, "发送时：" + AutoSender.lastTrace)
        // Confirm on screen: my newest message must be this text; never assume success.
        // Looks up to three times: a long message can take a moment to show.
        for wait: UInt64 in [700_000_000, 1_000_000_000, 1_500_000_000] {
            try? await Task.sleep(nanoseconds: wait)
            guard let after = await read(forceOCR: true), ChatID.same(after.chat, chat),
                  let last = after.conversation.bubbles.last, last.fromMe else { continue }
            // A long reply may be read as several bubbles: take all of mine at the end together.
            let mine = after.conversation.bubbles.reversed().prefix { $0.fromMe }.reversed().map(\.text).joined()
            guard Self.inputShows(mine, text) else { continue }
            if last.failed { throw WeChatRefused() }   // red “!”: WeChat did not send it; don't try again
            noteAssistantSent(text)
            return method
        }
        // Don't leave the text sitting in the input box (it would be typed twice on retry).
        await takeBack(text, chat: chat, pid: pid, seen: await read(forceOCR: true))
        return nil
    }

    /// Waits until the user has left mouse and keyboard alone for `idleSeconds` (background mode).
    func waitForIdle(before action: String) async -> Bool {
        guard backgroundMode else { return true }
        let deadline = Date().addingTimeInterval(120)
        var told = false
        while AutoSender.userIdleSeconds < idleSeconds {
            guard isRunning, Date() < deadline else { return false }
            if !told { status = "等你停下鼠标键盘 \(Int(idleSeconds)) 秒后再\(action)"; told = true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return true
    }

    func add(_ kind: LogEntry.Kind, _ text: String) {
        log.append(LogEntry(kind: kind, text: text))
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}

