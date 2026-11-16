import AppKit
import QingzhouCore
import SwiftUI

@main
struct QingzhouApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // The main window is created by AppDelegate, so it opens even when the app is launched
    // with arguments (macOS treats path arguments as “open this file” and skips SwiftUI windows).
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }   // screenshots
        MainActor.assumeIsolated {
            showMainWindow()
            NSApp.activate(ignoringOtherApps: true)
            // Test and screenshot modes start here, so they never wait for the window to appear.
            AutoTest.startIfRequested(AutoReplyController.shared)
            AutoReplyController.shared.backupIfDue()   // after the line above: test runs turn it off
            Snapshot.runIfRequested()
            ApiCheck.runIfRequested(AutoReplyController.shared)
            AXProbe.runIfRequested()
            KeyTest.runIfRequested()
            ClickTest.runIfRequested()
            SearchTest.runIfRequested()
            HoverTest.runIfRequested(AutoReplyController.shared)
            ConnectTest.runIfRequested(AutoReplyController.shared)
            TranscribeTest.runIfRequested()
            FrontTest.runIfRequested()
        }
    }

    /// Clicking the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { showMainWindow() }
        return true
    }

    @MainActor
    private func showMainWindow() {
        if mainWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "轻舟助手"
            w.titleVisibility = .hidden            // the panel shows its own name
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 340, height: 520)
            w.contentView = NSHostingView(rootView: ContentView().environmentObject(AutoReplyController.shared))
            if !w.setFrameUsingName("main") { w.center() }
            w.setFrameAutosaveName("main")
            mainWindow = w
        }
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// `--autotest <report.json> --duration <seconds>`: watch the mock WeChat with fast
/// pacing, then write the run log and quit. The mock app's own log is the ground truth.
@MainActor
enum AutoTest {
    private static var started = false
    /// `--settings-say "售后加上发霉"`: the change list the model made (nothing is applied).
    @MainActor static var settingsPlans: [[String: Any]] = []

    /// Uses “选择窗口” like a person: start picking, then one real click on a blank spot of the
    /// mock WeChat's title bar.
    static func pickMockByClicking(_ ctl: AutoReplyController) async {
        guard let f = WindowDocker.mainWindowFrame(bundleID: ChatTarget.mockWeChat.bundleID),
              let h = NSScreen.screens.first?.frame.height else { return }
        let point = CGPoint(x: f.minX + f.width - 60, y: h - f.maxY + 14)   // title bar, right side
        ctl.pickWindow()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 300_000_000)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }

    /// Saves a picture of this process's own panel (another copy of the app may be open too).
    static func saveUI(to url: URL) async {
        guard let n = NSApp.windows.first(where: { $0.isVisible && $0.title == "轻舟助手" })?.windowNumber,
              let me = try? await WindowCapture.findWindow(id: CGWindowID(n)),
              let cap = try? await WindowCapture.capture(window: me) else { return }
        try? WindowCapture.pngData(cap.image)?.write(to: url)
    }

    static func startIfRequested(_ ctl: AutoReplyController) {
        let args = CommandLine.arguments
        guard !started, let i = args.firstIndex(of: "--autotest"), i + 1 < args.count else { return }
        started = true
        AutoReplyController.saveSettings = false
        let reportURL = URL(fileURLWithPath: args[i + 1])
        var duration = 120.0
        if let d = args.firstIndex(of: "--duration"), d + 1 < args.count { duration = Double(args[d + 1]) ?? duration }
        ctl.target = args.contains("wechat") ? .weChat : .mockWeChat
        ctl.pacing = args.contains("--human") ? .human : .fastTest
        ctl.dryRun = args.contains("--dryrun")
        if let o = args.firstIndex(of: "--only"), o + 1 < args.count {
            ctl.onlyReplyTo = args[o + 1]
            ctl.replyMode = args[o + 1].isEmpty ? .all : .exact
        }
        if args.contains("--confident") { ctl.replyMode = .confident }
        if let c = args.firstIndex(of: "--onlychat"), c + 1 < args.count { ctl.onlyChat = TextMatch.normalize(args[c + 1]) }
        if args.contains("--stay") { ctl.stayInOpenChat = true }
        if args.contains("--foreground") { ctl.backgroundMode = false }
        if args.contains("--anytime") { ctl.outreachHours = 0..<24 }
        ctl.idleSeconds = 2   // nobody uses the computer during a test run
        if let m = args.firstIndex(of: "--maxhour"), m + 1 < args.count, let n = Int(args[m + 1]) { ctl.maxPerHour = n }
        if let k = args.firstIndex(of: "--kb"), k + 1 < args.count { ctl.kbFolder = URL(fileURLWithPath: args[k + 1]) }
        // Tests never use the user's own 不回名单, alerts or 主动智能; flags turn things on.
        let saved = ctl.options
        ctl.options = AssistantOptions()
        ctl.options.triggers = []   // tests add rules with flags
        if args.contains("--saved-api") {   // the owner's own API and model (key from the Keychain)
            ctl.options.apiConfigs = saved.apiConfigs
            ctl.options.apiActive = saved.apiActive
            ctl.engine = .api
        }
        if args.contains("--saved-persona") { ctl.options.persona = saved.persona }   // the owner's 店铺人设
        ctl.alertAddress = ""
        if args.contains("--assist") { ctl.options.assistMode = true }
        if args.contains("--pictures-to-model") { ctl.options.picturesToModel = true }
        // Sending-safety tests: wait this long right before the last look and Return, optionally pausing meanwhile.
        if let h = args.firstIndex(of: "--hold-before-send"), h + 1 < args.count {
            AutoReplyController.holdBeforeSend = Double(args[h + 1]) ?? 0
        }
        AutoReplyController.pauseInHold = args.contains("--pause-in-hold")
        // One after another, each seeing the ones before (as in the panel).
        let says = args.enumerated().compactMap { i, a in a == "--settings-say" && i + 1 < args.count ? args[i + 1] : nil }
        if !says.isEmpty {
            Task { @MainActor in
                for request in says {
                    let plan = await ctl.talkToAssistant(request)
                    settingsPlans.append(["said": request, "reply": ctl.assistantChat.last?.text ?? "", "changes": plan.changes.map(\.summary),
                                          "problems": plan.problems])
                }
            }
        }
        // `--click x,y` (points from the window's top-left, after 2 s): a real mouse click through
        // the window's own hit testing, to see which control takes it.
        if let c = args.firstIndex(of: "--click"), c + 1 < args.count {
            let xy = args[c + 1].split(separator: ",").compactMap { Double($0) }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard xy.count == 2, let w = NSApp.windows.first(where: { $0.isVisible && $0.title == "轻舟助手" }),
                      let content = w.contentView else { return }
                let point = NSPoint(x: xy[0], y: content.frame.height - xy[1])
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        w.sendEvent(e)
                    }
                }
            }
        }
        // `--read-history N`: 读以前的聊天, N customers, 4 screens each (after 2 s).
        if let h = args.firstIndex(of: "--read-history"), h + 1 < args.count, let n = Int(args[h + 1]) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                ctl.stop()   // as the owner would: pause auto-reply first
                ctl.startHistory(maxChats: n, pagesPerChat: 4)
            }
        }
        // `--add-file path`: adds a file to the knowledge folder the way a drop does (use with --kb).
        for (i, arg) in args.enumerated() where arg == "--add-file" && i + 1 < args.count {
            ctl.addKnowledgeFiles([URL(fileURLWithPath: args[i + 1])])
        }
        // API 直连 for tests: `--api-base http://127.0.0.1:8765/v1 --api-model m [--api-vision v] --api-key k`.
        if let b = args.firstIndex(of: "--api-base"), b + 1 < args.count {
            let value = { (flag: String) in args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            let config = ApiConfig(name: "测试接口", baseURL: args[b + 1], model: value("--api-model") ?? "test",
                                   visionModel: value("--api-vision"))
            ctl.options.apiConfigs = [config]
            ctl.options.apiActive = config.id
            AutoReplyController.testApiKey = value("--api-key") ?? "test"
            ctl.engine = .api
        }
        // 关键词触发 for tests (keywords may be several, “a、b”): `--trigger-image 多少钱 /abs/price.png`,
        // `--trigger-text 地址 "店在…"`, `--trigger-handover 退货`, `--common-rules`.
        if let t = args.firstIndex(of: "--trigger-image"), t + 2 < args.count {
            ctl.options.triggers.append(TriggerRule(keywords: TriggerRule.keywords(from: args[t + 1]),
                                                    action: .sendImage(path: args[t + 2])))
        }
        if let t = args.firstIndex(of: "--trigger-text"), t + 2 < args.count {
            ctl.options.triggers.append(TriggerRule(keywords: TriggerRule.keywords(from: args[t + 1]),
                                                    action: .sendText(args[t + 2])))
        }
        if let t = args.firstIndex(of: "--trigger-handover"), t + 1 < args.count {
            ctl.options.triggers.append(TriggerRule(keywords: TriggerRule.keywords(from: args[t + 1]),
                                                    action: .handOver(reason: "")))
        }
        if args.contains("--common-rules") { ctl.options.triggers += TriggerRule.presets }
        if args.contains("--tall"), let w = NSApp.windows.first(where: { $0.title == "轻舟助手" }) {   // whole pages in one picture
            w.setContentSize(NSSize(width: w.frame.width, height: 1900))
        }
        if let n = args.firstIndex(of: "--never"), n + 1 < args.count { ctl.options.neverReply = [args[n + 1]] }
        if let n = args.firstIndex(of: "--sold-out"), n + 1 < args.count { ctl.options.soldOut = args[n + 1].components(separatedBy: ",") }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if args.contains("--pickmock") { await pickMockByClicking(ctl) }
            ctl.start()
            // Act like the shop owner during a test: “已到货” on the first reservation, or publish news.
            if let a = args.firstIndex(of: "--arrive-after"), a + 1 < args.count, let secs = Double(args[a + 1]) {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                    if let r = ctl.memory.all.first(where: { $0.reservations.contains { $0.status == .waiting } }),
                       let res = r.reservations.first(where: { $0.status == .waiting }) {
                        ctl.reservationArrived(chat: r.chatID, id: res.id)
                    }
                }
            }
            // Like the owner in 辅助模式: click 发送 on the first draft (optionally after changing it).
            if let a = args.firstIndex(of: "--approve-after"), a + 1 < args.count, let secs = Double(args[a + 1]) {
                let edited = args.firstIndex(of: "--approve-text").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                    for _ in 0..<600 where ctl.drafts.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000_000) }
                    if let d = ctl.drafts.first { ctl.approveDraft(d.id, text: edited ?? d.text) }
                }
            }
            // 定时群发 switched on later, with one message to everyone, due now.
            if let n = args.firstIndex(of: "--broadcast-after"), n + 2 < args.count, let secs = Double(args[n + 1]) {
                let text = args[n + 2]
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                    ctl.options.broadcastOn = true
                    ctl.options.broadcasts = [Broadcast(text: text, schedule: .once(at: Date()))]
                }
            }
            // 双击 Esc: two presses 0.2 s apart, as the key monitors report them (synthetic events from
            // this app are ignored on purpose, so the handler is called directly).
            if let e = args.firstIndex(of: "--esc-after"), e + 1 < args.count, let secs = Double(args[e + 1]) {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                    ctl.escPressed(at: ProcessInfo.processInfo.systemUptime)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    ctl.escPressed(at: ProcessInfo.processInfo.systemUptime)
                }
            }
            // 主动智能 switched on later, with any quiet time up to 30 days counting, one greeting.
            if let r = args.firstIndex(of: "--revisit-after"), r + 1 < args.count, let secs = Double(args[r + 1]) {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                    ctl.options.revisitOn = true
                    ctl.options.revisitMinDays = 0
                    ctl.options.revisitMaxDays = 30
                    ctl.options.revisitPerDay = 1
                    AutoReplyController.revisitPlannedAt = nil
                }
            }
            if let n = args.firstIndex(of: "--announce-after"), n + 2 < args.count, let secs = Double(args[n + 1]) {
                let text = args[n + 2]
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
                    ctl.publish(text)
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await saveUI(to: reportURL.deletingPathExtension().appendingPathExtension("running.png"))
            ctl.stop()
            let fmt = ISO8601DateFormatter()
            let report: [String: Any] = [
                "screenRecordingPermission": WindowCapture.hasPermission,
                "accessibilityPermission": AutoSender.isTrusted,
                "sentCount": ctl.sentCount,
                "screenProblem": ctl.screenProblem ?? "",
                "photos": ctl.productPhotos.map { "\($0.product)：\($0.file.lastPathComponent)" },
                "knowledgeFolder": ctl.kbFolder.path,
                "knowledgeChunks": ctl.kb?.chunks.count ?? 0,
                "lastStatus": ctl.status,
                "replyMode": ctl.replyMode.rawValue,
                "customers": ctl.memory.all.map { r -> [String: Any] in
                    ["name": r.name, "reservations": r.reservations.map { "\($0.item) [\($0.status.rawValue)]" },
                     "consent": r.consent.map { "\($0.interests) “\($0.quote)”" } ?? "", "optedOut": r.optedOutAt != nil]
                },
                "pickedWindow": ctl.pickedWindow.map { ["app": $0.appName, "bundle": $0.bundleID, "id": Int($0.windowID)] } ?? [:],
                "target": ctl.target.name,
                "needsHuman": ctl.needsHuman.map { ["who": $0.who, "message": $0.message] },
                "drafts": ctl.drafts.map { ["who": $0.who, "text": $0.text, "picture": $0.picture ?? "", "problem": $0.problem ?? ""] },
                "triggers": ctl.options.triggers.map { "\($0.keywordText) → \($0.action.summary)" },
                "lessons": ctl.lessons.lessons.map { "\($0.kind.rawValue)：\($0.question) → \($0.final ?? $0.draft)" },
                "settingsPlans": settingsPlans,
                "learnedAnswers": ctl.answerStore.items.map { ["who": $0.who, "question": $0.question, "answer": $0.answer] },
                "greeted": ctl.memory.all.filter { $0.lastRevisitAt != nil }.map(\.name),
                "log": ctl.log.map { ["time": fmt.string(from: $0.time), "kind": "\($0.kind)", "text": $0.text] },
                "lastParsedBubbles": ctl.bubbles.map { ["fromMe": $0.fromMe, "text": $0.text] },
            ]
            // Also save how the assistant's own panel looked at the end (after animations settle).
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await saveUI(to: reportURL.deletingPathExtension().appendingPathExtension("ui.png"))
            if let img = ctl.screenshot, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: reportURL.deletingPathExtension().appendingPathExtension("png"))
            }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: reportURL)
            }
            NSApp.terminate(nil)
        }
    }
}

/// `--snapshot <out.png> [--target wechat|mock]`: capture the target window once, save the image
/// plus OCR lines (with positions), detected badges and the parsed chat, then quit.
/// Read-only: never clicks or types. Used to calibrate a target's layout.
@MainActor
enum Snapshot {
    private static var started = false

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard !started, let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        started = true
        let out = URL(fileURLWithPath: args[i + 1])
        let target = args.contains("wechat") ? ChatTarget.weChat : ChatTarget.mockWeChat
        // "self" captures this app's own panel (to check the UI); others capture a chat app.
        let bundleID = args.contains("self") ? (Bundle.main.bundleIdentifier ?? "") : target.bundleID
        Task { @MainActor in
            var report: [String: Any] = ["target": target.name]
            do {
                // "self" means the assistant panel that is already open (another process).
                let exclude: pid_t? = args.contains("self") ? ProcessInfo.processInfo.processIdentifier : nil
                guard let w = try await WindowCapture.findWindow(bundleID: bundleID, excludingPID: exclude) else {
                    throw CaptureError.failed("找不到窗口")
                }
                let cap = try await WindowCapture.capture(window: w)
                try WindowCapture.pngData(cap.image)?.write(to: out)
                let ocr = try OCRService.recognize(cap.image)
                let size = w.frame.size
                report["windowFrame"] = [w.frame.minX, w.frame.minY, size.width, size.height]
                report["imagePixels"] = [cap.image.width, cap.image.height]
                report["lines"] = ocr.lines.map { l -> [String: Any] in
                    ["text": l.text,
                     "x": Int(l.box.minX * size.width), "y": Int((1 - l.box.maxY) * size.height),
                     "w": Int(l.box.width * size.width), "h": Int(l.box.height * size.height)]
                }
                let found = LayoutFinder.find(in: cap.image, windowSize: size, base: target.layout)
                report["dividers"] = ["sidebarWidth": found.sidebarWidth.map { Int($0) } ?? -1,
                                      "inputHeight": found.inputHeight.map { Int($0) } ?? -1,
                                      "measuredSidebar": Int(target.layout.sidebarWidth), "measuredInput": Int(target.layout.inputHeight)]
                let badges = UnreadDetector.badgeRows(in: cap.image, windowSize: size, layout: target.layout)
                report["badgeRows"] = badges
                report["unreadRows"] = UnreadRowReader.rows(badges: badges, lines: ocr.lines, windowSize: size,
                                                            layout: target.layout).map { r -> [String: Any] in
                    ["name": r.name, "preview": r.preview, "system": SystemChat.isSystem(r.name),
                     "looksLikeGroup": GroupChat.looksLikeGroupPreview(r.preview)]
                }
                let conv = ChatParser.parse(ocr.lines, windowSize: size, layout: target.layout)
                report["title"] = conv.title
                report["titleIsGroup"] = GroupChat.isGroupTitle(conv.title)
                report["chatID"] = ChatID.make(title: conv.title)
                report["bubbles"] = conv.bubbles.map { ["fromMe": $0.fromMe, "text": $0.text] }
            } catch {
                report["error"] = error.localizedDescription
            }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: out.deletingPathExtension().appendingPathExtension("json"))
            }
            NSApp.terminate(nil)
        }
    }
}

/// `--api-check <out.json>`: tests the API in use with its saved key (read by this app from the
/// Keychain, never written out) and records only whether it works.
@MainActor
enum ApiCheck {
    static func runIfRequested(_ ctl: AutoReplyController) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--api-check"), i + 1 < args.count else { return }
        AutoReplyController.saveSettings = false
        let out = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            var report: [String: Any] = ["result": "没有 API"]
            if var c = ctl.activeApi {
                if let m = args.firstIndex(of: "--model"), m + 1 < args.count { c.model = args[m + 1] }   // try another model
                report = ["name": c.name, "baseURL": c.baseURL, "model": c.model,
                          "hasKey": !ctl.apiKey(for: c).isEmpty, "result": await ctl.testApi(c)]
            }
            if args.contains("--list-models"), let c = ctl.activeApi, var url = URL(string: c.baseURL) {
                // Which models this key may use (GET /models): only their names are kept.
                url.appendPathComponent("models")
                var request = URLRequest(url: url, timeoutInterval: 20)
                request.setValue("Bearer \(ctl.apiKey(for: c))", forHTTPHeaderField: "Authorization")
                if let (data, response) = try? await URLSession.shared.data(for: request) {
                    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    report["modelsStatus"] = (response as? HTTPURLResponse)?.statusCode ?? 0
                    report["models"] = ((json?["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.sorted()
                    report["modelsError"] = (json?["error"] as? [String: Any])?["message"] ?? ""
                }
            }
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]).write(to: out)
            NSApp.terminate(nil)
        }
    }
}
