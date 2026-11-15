import AppKit
import ApplicationServices
import QingzhouCore
import ScreenCaptureKit

/// `--axprobe <out.json> [--assistive]`: read-only look at which controls a chat app exposes
/// to the Accessibility API (to judge whether replies could be sent without mouse/keyboard).
/// Records roles, labels and whether values are settable — never the text of values.
/// With `--assistive`, temporarily sets the standard screen-reader flags and restores them.
@MainActor
enum AXProbe {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--axprobe"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let bundleID = "com.tencent.xinWeChat"
        var report: [String: Any] = ["trusted": AXIsProcessTrusted()]
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            report["error"] = "WeChat not running"
            write(report, to: out)
            NSApp.terminate(nil)
            return
        }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        let assistive = args.contains("--assistive")
        let flags = ["AXManualAccessibility", "AXEnhancedUserInterface"]
        var previous: [String: CFTypeRef] = [:]
        if assistive {
            for f in flags {
                var v: CFTypeRef?
                if AXUIElementCopyAttributeValue(appEl, f as CFString, &v) == .success, let v { previous[f] = v }
                report["set_\(f)"] = AXUIElementSetAttributeValue(appEl, f as CFString, kCFBooleanTrue).rawValue
            }
        }
        Task { @MainActor in
            if assistive { try? await Task.sleep(nanoseconds: 1_500_000_000) } // let it build its tree
            var nodes: [[String: Any]] = []
            var roleCounts: [String: Int] = [:]
            walk(appEl, depth: 0, path: "app", into: &nodes, counts: &roleCounts)
            report["nodeCount"] = nodes.count
            report["roleCounts"] = roleCounts
            report["nodes"] = nodes
            if assistive {
                for f in flags {
                    let restore: CFTypeRef = previous[f] ?? kCFBooleanFalse!
                    AXUIElementSetAttributeValue(appEl, f as CFString, restore)
                }
                report["restored"] = true
            }
            write(report, to: out)
            NSApp.terminate(nil)
        }
    }

    private static func walk(_ el: AXUIElement, depth: Int, path: String,
                             into nodes: inout [[String: Any]], counts: inout [String: Int]) {
        guard depth <= 14, nodes.count < 4000 else { return }
        func str(_ attr: String) -> String? {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
            return v as? String
        }
        let role = str(kAXRoleAttribute) ?? "?"
        counts[role, default: 0] += 1
        var node: [String: Any] = ["path": path, "role": role, "depth": depth]
        if let s = str(kAXSubroleAttribute) { node["subrole"] = s }
        // Labels of controls (button titles, descriptions); value text is never recorded.
        if let t = str(kAXTitleAttribute), !t.isEmpty { node["title"] = String(t.prefix(20)) }
        if let d = str(kAXDescriptionAttribute), !d.isEmpty { node["desc"] = String(d.prefix(20)) }
        if let id = str(kAXIdentifierAttribute), !id.isEmpty { node["id"] = id }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
            node["valueSettable"] = true
        }
        var actions: CFArray?
        if AXUIElementCopyActionNames(el, &actions) == .success, let a = actions as? [String], !a.isEmpty {
            node["actions"] = a
        }
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &v) == .success, let s = v as? String {
            node["valueLength"] = s.count
        }
        nodes.append(node)
        var children: CFTypeRef?
        let attr = depth == 0 ? kAXWindowsAttribute : kAXChildrenAttribute
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return }
        for (n, child) in list.enumerated() {
            walk(child, depth: depth + 1, path: "\(path)/\(n)", into: &nodes, counts: &counts)
        }
    }

    private static func write(_ report: [String: Any], to url: URL) {
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}

/// `--keytest <out.json>`: checks whether WeChat accepts keystrokes while it stays in the
/// background. Types "QZ" straight to the WeChat process (no clipboard, no mouse), checks the
/// input box, then deletes it with two Backspaces. Never presses Return, so nothing is sent.
@MainActor
enum KeyTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--keytest"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            var report: [String: Any] = [:]
            defer {
                if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? d.write(to: out)
                }
                NSApp.terminate(nil)
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let wx = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.xinWeChat").first
            else { report["error"] = "WeChat not running"; return }
            let pid = wx.processIdentifier
            let mouseBefore = CGEvent(source: nil)?.location ?? .zero
            report["frontmostBefore"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
                report["error"] = "WeChat is in front; the test needs it in the background"; return
            }

            func inputText() async -> [String] {
                guard let w = try? await WindowCapture.findWindow(bundleID: "com.tencent.xinWeChat"),
                      let cap = try? await WindowCapture.capture(window: w),
                      let ocr = try? OCRService.recognize(cap.image) else { return ["<capture failed>"] }
                let width = w.frame.size.width, height = w.frame.size.height
                var texts: [String] = []
                for l in ocr.lines {
                    let x = l.box.minX * width
                    let top = (1 - l.box.maxY) * height
                    if x >= 300, top > height - 145 { texts.append(l.text) }
                }
                return texts
            }
            func post(_ make: (CGEventSource?) -> (CGEvent?, CGEvent?)) {
                let src = CGEventSource(stateID: .privateState)
                let (down, up) = make(src)
                down?.postToPid(pid)
                up?.postToPid(pid)
            }

            report["inputBefore"] = await inputText()
            // Type "QZ" as text (bypasses the input method and the clipboard).
            post { src in
                let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
                let u = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
                let chars = Array("QZ".utf16)
                d?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
                u?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
                return (d, u)
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            report["inputAfterTyping"] = await inputText()
            report["frontmostAfterTyping"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            // Two Backspaces to remove what was typed. Return is never sent.
            for _ in 0..<2 {
                post { src in (CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true),
                               CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)) }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            report["inputAfterDelete"] = await inputText()
            report["frontmostAfter"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            let mouseAfter = CGEvent(source: nil)?.location ?? .zero
            report["mouseMoved"] = abs(mouseAfter.x - mouseBefore.x) > 1 || abs(mouseAfter.y - mouseBefore.y) > 1
        }
    }
}

/// `--clicktest <out.json> <name part>`: checks whether WeChat accepts a click while it stays in
/// the background. Finds the contact row whose name contains <name part>, sends one click
/// straight to the WeChat process, and checks whether that chat opened. No typing, no sending.
@MainActor
enum ClickTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--clicktest"), i + 2 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let wanted = TextMatch.normalize(args[i + 2])
        let layout = ChatTarget.weChat.layout
        Task { @MainActor in
            var report: [String: Any] = ["wanted": wanted]
            defer {
                if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? d.write(to: out)
                }
                NSApp.terminate(nil)
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let wx = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.xinWeChat").first
            else { report["error"] = "WeChat not running"; return }
            let pid = wx.processIdentifier
            report["frontmostBefore"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
                report["error"] = "WeChat is in front; the test needs it in the background"; return
            }

            func look() async -> (title: String, rowPoint: CGPoint?, windowID: CGWindowID)? {
                guard let w = try? await WindowCapture.findWindow(bundleID: "com.tencent.xinWeChat"),
                      let cap = try? await WindowCapture.capture(window: w),
                      let ocr = try? OCRService.recognize(cap.image) else { return nil }
                let f = w.frame
                let conv = ChatParser.parse(ocr.lines, windowSize: f.size, layout: layout)
                var point: CGPoint?
                for l in ocr.lines {
                    let x = l.box.minX * f.width
                    let midY = (1 - l.box.midY) * f.height
                    if x >= layout.rowTextMinX, x < layout.sidebarWidth, midY > layout.listTop,
                       TextMatch.normalize(l.text).contains(wanted) {
                        point = CGPoint(x: f.minX + x + 30, y: f.minY + midY)
                        break
                    }
                }
                return (conv.title, point, w.windowID)
            }

            guard let before = await look() else { report["error"] = "capture failed"; return }
            report["titleBefore"] = before.title
            guard let p = before.rowPoint else { report["error"] = "row not found in the visible list"; return }
            if TextMatch.normalize(before.title).contains(wanted) {
                report["error"] = "that chat is already open, so a switch cannot be seen"; return
            }
            let mouseBefore = CGEvent(source: nil)?.location ?? .zero
            let src = CGEventSource(stateID: .privateState)
            // Tell the event which window it is for, so a background window can take it.
            let wid = Int64(before.windowID)
            report["variant"] = "move+down+up with window number"
            for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
                e?.setIntegerValueField(.mouseEventClickState, value: type == .mouseMoved ? 0 : 1)
                e?.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: wid)
                e?.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: wid)
                e?.postToPid(pid)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            report["titleAfter"] = (await look())?.title ?? "<capture failed>"
            report["frontmostAfter"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            let mouseAfter = CGEvent(source: nil)?.location ?? .zero
            report["mouseMoved"] = abs(mouseAfter.x - mouseBefore.x) > 1 || abs(mouseAfter.y - mouseBefore.y) > 1
            report["clickPoint"] = [p.x, p.y]
        }
    }
}

/// `--searchtest <out.json> <query>`: checks whether WeChat can switch chats by keyboard while
/// it stays in the background: ⌘F, type <query>, then press Return ONLY if the query is in the
/// search box, not in the chat input box, and appears in the results. Otherwise Escape (and
/// delete anything that landed in the input box). Afterwards checks that the title changed.
@MainActor
enum SearchTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--searchtest"), i + 2 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let query = args[i + 2]
        let q = TextMatch.normalize(query)
        let layout = ChatTarget.weChat.layout
        Task { @MainActor in
            var report: [String: Any] = ["query": query]
            var steps: [String] = []
            defer {
                report["steps"] = steps
                if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? d.write(to: out)
                }
                NSApp.terminate(nil)
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let wx = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.xinWeChat").first
            else { report["error"] = "WeChat not running"; return }
            let pid = wx.processIdentifier
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
                report["error"] = "WeChat is in front; the test needs it in the background"; return
            }
            report["frontmostBefore"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            let mouseBefore = CGEvent(source: nil)?.location ?? .zero

            struct Look { let title: String; let search: [String]; let input: [String]; let list: [String] }
            func look() async -> Look? {
                guard let w = try? await WindowCapture.findWindow(bundleID: "com.tencent.xinWeChat"),
                      let cap = try? await WindowCapture.capture(window: w),
                      let ocr = try? OCRService.recognize(cap.image) else { return nil }
                let width = w.frame.size.width, height = w.frame.size.height
                var search: [String] = [], input: [String] = [], list: [String] = []
                for l in ocr.lines {
                    let x = l.box.minX * width
                    let top = (1 - l.box.maxY) * height
                    if x >= 60, x < layout.sidebarWidth, top < layout.listTop { search.append(l.text) }
                    else if x >= 60, x < layout.sidebarWidth { list.append(l.text) }
                    else if x >= layout.sidebarWidth, top > height - layout.inputHeight { input.append(l.text) }
                }
                let title = ChatParser.parse(ocr.lines, windowSize: w.frame.size, layout: layout).title
                return Look(title: title, search: search, input: input, list: list)
            }
            func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
                let src = CGEventSource(stateID: .privateState)
                let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
                let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
                d?.flags = flags; u?.flags = flags
                d?.postToPid(pid); u?.postToPid(pid)
            }
            func type(_ text: String) {
                let src = CGEventSource(stateID: .privateState)
                let chars = Array(text.utf16)
                let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
                let u = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
                d?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
                u?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
                d?.postToPid(pid); u?.postToPid(pid)
            }
            func has(_ lines: [String]) -> Bool { lines.contains { TextMatch.normalize($0).contains(q) } }

            guard let before = await look() else { report["error"] = "capture failed"; return }
            report["titleBefore"] = before.title
            guard !has(before.input) else { report["error"] = "input box already contains the query; stop"; return }

            key(3, .maskCommand)                       // ⌘F
            steps.append("⌘F")
            try? await Task.sleep(nanoseconds: 700_000_000)
            type(query)
            steps.append("typed query")
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let typed = await look() else { key(53); report["error"] = "capture failed after typing"; return }
            report["searchBox"] = typed.search
            report["inputBox"] = typed.input
            report["resultsHaveQuery"] = has(typed.list)

            let inSearch = has(typed.search), inInput = has(typed.input)
            guard inSearch, !inInput, has(typed.list) else {
                key(53)                                 // Escape: cancel the search
                steps.append("Escape (checks failed: inSearch=\(inSearch) inInput=\(inInput))")
                if inInput {                             // remove what landed in the chat input box
                    for _ in 0..<query.count { key(51); try? await Task.sleep(nanoseconds: 60_000_000) }
                    steps.append("deleted \(query.count) chars from input box")
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                report["inputAfterCleanup"] = (await look())?.input ?? []
                report["result"] = "aborted safely, Return not pressed"
                return
            }
            key(36)                                     // Return: open the top search result
            steps.append("Return (checks passed)")
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let after = await look()
            report["titleAfter"] = after?.title ?? "<capture failed>"
            report["inputAfter"] = after?.input ?? []
            report["switched"] = TextMatch.normalize(after?.title ?? "").contains(q)
            report["frontmostAfter"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            let mouseAfter = CGEvent(source: nil)?.location ?? .zero
            report["mouseMoved"] = abs(mouseAfter.x - mouseBefore.x) > 1 || abs(mouseAfter.y - mouseBefore.y) > 1
        }
    }
}

/// `--hovertest <out.json>`: starts “选择窗口”, moves the mouse over the WeChat and Codex windows
/// (no clicks), and records where the green outline went. Then cancels with Esc.
@MainActor
enum HoverTest {
    static func runIfRequested(_ ctl: AutoReplyController) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--hovertest"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            var report: [String: Any] = [:]
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let me = ProcessInfo.processInfo.processIdentifier
            func overlayFrame() -> [Int]? {
                let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
                for w in list where (w[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == me
                    && (w[kCGWindowLayer as String] as? Int ?? 0) > 0 {
                    if let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) > 200 {
                        return [Int(b["X"] ?? 0), Int(b["Y"] ?? 0), Int(b["Width"] ?? 0), Int(b["Height"] ?? 0)]
                    }
                }
                return nil
            }
            ctl.pickWindow()
            try? await Task.sleep(nanoseconds: 500_000_000)
            let mouseStart = CGEvent(source: nil)?.location ?? .zero
            var results: [[String: Any]] = []
            for bundle in ["com.tencent.xinWeChat", "com.openai.codex"] {
                guard let f = WindowDocker.mainWindowFrame(bundleID: bundle), let h = NSScreen.screens.first?.frame.height
                else { results.append(["app": bundle, "error": "window not found"]); continue }
                let p = CGPoint(x: f.midX, y: h - f.midY)
                let src = CGEventSource(stateID: .hidSystemState)
                CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 700_000_000)
                results.append(["app": bundle, "windowTopLeft": [Int(f.minX), Int(h - f.maxY), Int(f.width), Int(f.height)],
                                "outline": overlayFrame() ?? "none",
                                "underMouse": WindowPicker.windowUnderMouse()?.appName ?? "none"])
            }
            CGWarpMouseCursorPosition(mouseStart)
            let src = CGEventSource(stateID: .hidSystemState)
            CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 500_000_000)
            report["results"] = results
            report["stillPicking"] = ctl.isPicking
            if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? d.write(to: out)
            }
            NSApp.terminate(nil)
        }
    }
}

/// `--connecttest <out.json> <bundleID>`: lists the windows the chooser would show, connects the
/// first window of <bundleID> (read-only), waits, and saves a picture of this panel.
@MainActor
enum ConnectTest {
    static func runIfRequested(_ ctl: AutoReplyController) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--connecttest"), i + 2 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let bundle = args[i + 2]
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let list = PickedWindow.onScreen()
            var report: [String: Any] = ["windows": list.map { $0.label }]
            if let w = list.first(where: { $0.bundleID == bundle }) {
                ctl.connect(w)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                report["connected"] = ctl.pickedWindow?.label ?? "-"
                report["target"] = ctl.target.name
                report["supportsAutoReply"] = ctl.target.supportsAutoReply
                report["textLines"] = ctl.windowText.count
                report["hasScreenshot"] = ctl.screenshot != nil
                if let me = try? await WindowCapture.findWindow(bundleID: Bundle.main.bundleIdentifier ?? ""),
                   let cap = try? await WindowCapture.capture(window: me) {
                    try? WindowCapture.pngData(cap.image)?.write(to: out.deletingPathExtension().appendingPathExtension("png"))
                }
            } else {
                report["error"] = "no window of \(bundle)"
            }
            if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? d.write(to: out)
            }
            try? await Task.sleep(nanoseconds: 12_000_000_000)   // stay open so the panel can be photographed
            NSApp.terminate(nil)
        }
    }
}

/// `--transcribetest <out.json>`: in the open WeChat chat, clicks “转文字” next to the newest voice
/// message that has no words yet, and checks the words appear. Never types or sends anything.
@MainActor
enum TranscribeTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--transcribetest"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let layout = ChatTarget.weChat.layout
        Task { @MainActor in
            var report: [String: Any] = [:]
            defer {
                if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? d.write(to: out)
                }
                NSApp.terminate(nil)
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            func look() async -> (SCWindowFrame: CGRect, pid: pid_t, conv: Conversation)? {
                guard let w = try? await WindowCapture.findWindow(bundleID: "com.tencent.xinWeChat"),
                      let pid = w.owningApplication?.processID,
                      let cap = try? await WindowCapture.capture(window: w),
                      let ocr = try? OCRService.recognize(cap.image) else { return nil }
                return (w.frame, pid, ChatParser.parse(ocr.lines, windowSize: w.frame.size, layout: layout))
            }
            guard let before = await look() else { report["error"] = "capture failed"; return }
            report["title"] = before.conv.title
            guard let voice = before.conv.bubbles.last(where: { !$0.fromMe && $0.needsTranscript }) else {
                report["error"] = "no voice message without words in the open chat"; return
            }
            report["voice"] = voice.text
            guard let b = voice.transcribeButton else { report["error"] = "no 转文字 button found next to it"; return }
            let f = before.SCWindowFrame
            do {
                try await AutoSender.click(CGPoint(x: f.minX + b.x, y: f.minY + b.y), inPID: before.pid, windowFrame: f)
            } catch { report["error"] = error.localizedDescription; return }
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let now = await look(),
                   let v = now.conv.bubbles.last(where: { !$0.fromMe && $0.voiceSeconds != nil }), !v.needsTranscript {
                    report["after"] = v.text
                    report["ok"] = true
                    return
                }
            }
            report["ok"] = false
            report["after"] = (await look())?.conv.bubbles.suffix(3).map(\.text) ?? []
        }
    }
}

/// `--fronttest <out.json>`: with another app (Finder) in front, checks that the assistant can
/// still bring the mock WeChat forward and click a blank spot in its title bar.
@MainActor
enum FrontTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--fronttest"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            var report: [String: Any] = [:]
            defer {
                if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? d.write(to: out)
                }
                NSApp.terminate(nil)
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
                  let mock = NSRunningApplication.runningApplications(withBundleIdentifier: ChatTarget.mockWeChat.bundleID).first,
                  let w = try? await WindowCapture.findWindow(bundleID: ChatTarget.mockWeChat.bundleID)
            else { report["error"] = "Finder or mock WeChat not found"; return }
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(finder.processIdentifier),
                                         kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            try? await Task.sleep(nanoseconds: 800_000_000)
            report["frontBefore"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            let f = w.frame
            do {
                try await AutoSender.click(CGPoint(x: f.maxX - 60, y: f.minY + 14), inPID: mock.processIdentifier, windowFrame: f)
                report["result"] = "clicked"
            } catch {
                report["result"] = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            report["frontAfter"] = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
        }
    }
}
