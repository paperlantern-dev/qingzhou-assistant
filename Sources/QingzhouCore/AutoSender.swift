import AppKit
import ApplicationServices
import ImageIO

public enum SendError: LocalizedError {
    case notTrusted
    case appNotRunning
    case couldNotActivate
    case windowCovered(String)

    public var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "没有“辅助功能”权限，无法模拟点击和粘贴。请在 系统设置 › 隐私与安全性 › 辅助功能 中允许“轻舟助手”。"
        case .appNotRunning:
            return "目标应用没有在运行。"
        case .couldNotActivate:
            return "无法把目标窗口切到前台，没有发送。"
        case .windowCovered(let who):
            return "输入框被其他窗口挡住（\(who)），为安全起见没有点击和发送。"
        }
    }
}

/// Sends a reply the way a person would: copy, click the input box, ⌘V, Return.
@MainActor
public enum AutoSender {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the normal system prompt for Accessibility access.
    public static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// `clickPoint` is in global screen coordinates (origin top-left), like CGWindow frames.
    /// `windowFrame` is the target chat window's frame, used to raise exactly that window.
    /// `confirm` runs after the text is in the input box and before Return: false calls the send off
    /// (Return is not pressed). Returns whether Return was pressed.
    @discardableResult
    public static func send(_ text: String, toPID pid: pid_t, windowFrame: CGRect, clickPoint: CGPoint,
                            confirm: (() async -> Bool)? = nil) async throws -> Bool {
        try await paste(toPID: pid, windowFrame: windowFrame, clickPoint: clickPoint, settle: 350_000_000, confirm: confirm) {
            $0.setString(text, forType: .string)
        }
    }

    /// Backspaces in the front app: takes back the reply just pasted (the caret is at its end). Only
    /// called right after a paste, when the box was seen to hold nothing but that reply.
    public static func deletePastedText(characters: Int) async {
        for _ in 0..<characters {
            key(51)                   // Delete
            await wait(15_000_000)
        }
        await wait(150_000_000)
    }

    /// Waits even when the calling task was cancelled (a pause cancels it): the keys that follow must
    /// still reach the chat app before the front window is handed back.
    private static func wait(_ nanoseconds: UInt64) async {
        await Task.detached { try? await Task.sleep(nanoseconds: nanoseconds) }.value
    }

    /// Sends a picture file the same way: the chat app shows it in the input box, Return sends it.
    /// The clipboard gets the picture itself (PNG and TIFF) and the file, so it pastes as a picture.
    @discardableResult
    public static func sendImage(_ file: URL, toPID pid: pid_t, windowFrame: CGRect, clickPoint: CGPoint,
                                 confirm: (() async -> Bool)? = nil) async throws -> Bool {
        guard isTrusted else { throw SendError.notTrusted }
        guard let data = await Task.detached(operation: { pictureData(file) }).value else {
            throw PictureError.unreadable(file.lastPathComponent)
        }
        // A picture takes longer than text to show up in the input box.
        return try await paste(toPID: pid, windowFrame: windowFrame, clickPoint: clickPoint, settle: 1_200_000_000, confirm: confirm) { board in
            let item = NSPasteboardItem()
            item.setData(data.png, forType: .png)
            item.setData(data.tiff, forType: .tiff)
            item.setString(file.absoluteString, forType: .fileURL)
            board.writeObjects([item])
        }
    }

    /// The picture as PNG and TIFF data, upright and at most 4096 px on its long side.
    nonisolated static func pictureData(_ file: URL) -> (png: Data, tiff: Data)? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 4096]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]),
              let tiff = rep.tiffRepresentation(using: .lzw, factor: 0) else { return nil }
        return (png, tiff)
    }

    /// Copy (`fill` writes the clipboard), bring the window forward, click the input box, ⌘V, wait
    /// `settle` nanoseconds, ask `confirm`, Return; then put the clipboard, mouse and front app back.
    /// false = `confirm` said no and Return was not pressed.
    private static func paste(toPID pid: pid_t, windowFrame: CGRect, clickPoint: CGPoint, settle: UInt64,
                              confirm: (() async -> Bool)?, fill: (NSPasteboard) -> Void) async throws -> Bool {
        guard isTrusted else { throw SendError.notTrusted }
        guard let app = NSRunningApplication(processIdentifier: pid) else { throw SendError.appNotRunning }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { (t, $0) } })
        } ?? []
        let previousApp = NSWorkspace.shared.frontmostApplication
        let mouseBefore = CGEvent(source: nil)?.location

        pasteboard.clearContents()
        fill(pasteboard)

        do {
            try await bringToFront(app, windowFrame: windowFrame, point: clickPoint)
        } catch {
            restore(saved, to: pasteboard)
            throw error
        }
        lastTrace = "frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-") topWindowAtPoint=\(topWindowOwner(at: clickPoint))"
        // Click the input box twice, spaced so it is not a double-click: the first click may
        // only make the window key, the second puts the caret in the box.
        let gap = UInt64((NSEvent.doubleClickInterval + 0.15) * 1_000_000_000)
        click(at: clickPoint)
        try await Task.sleep(nanoseconds: gap)
        click(at: clickPoint)
        try await Task.sleep(nanoseconds: 300_000_000)
        key(9, flags: .maskCommand)   // V
        try await Task.sleep(nanoseconds: settle)
        var pressed = true
        if let confirm, !(await confirm()) { pressed = false }
        if pressed { key(36) }        // Return
        // From here on nothing may stop half-way (a pause cancels the task): the clipboard, mouse and
        // front app are always put back.
        await wait(400_000_000)

        // Put things back the way they were.
        restore(saved, to: pasteboard)
        if let p = mouseBefore { CGWarpMouseCursorPosition(p) }
        if let prev = previousApp, prev.processIdentifier != pid { giveBackFront(to: prev) }
        return pressed
    }

    /// Clicks once at a point inside the target window (e.g. a contact row), like a person would.
    /// `then`: a second spot to click in the same visit (e.g. the input box, so typing goes there).
    public static func click(_ point: CGPoint, inPID pid: pid_t, windowFrame: CGRect,
                             then followUp: CGPoint? = nil) async throws {
        guard isTrusted else { throw SendError.notTrusted }
        guard let app = NSRunningApplication(processIdentifier: pid) else { throw SendError.appNotRunning }
        let previousApp = NSWorkspace.shared.frontmostApplication
        let mouseBefore = CGEvent(source: nil)?.location
        try await bringToFront(app, windowFrame: windowFrame, point: point)
        click(at: point)
        try await Task.sleep(nanoseconds: 300_000_000)
        if let followUp {
            try await Task.sleep(nanoseconds: 300_000_000)
            click(at: followUp)
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        if let p = mouseBefore { CGWarpMouseCursorPosition(p) }
        if let prev = previousApp, prev.processIdentifier != pid { giveBackFront(to: prev) }
    }

    /// Scrolls the part of the window under `point` (positive `lines`: up, toward older messages),
    /// like turning the mouse wheel there, then puts the mouse and the front app back.
    public static func scroll(at point: CGPoint, lines: Int32, times: Int = 1, inPID pid: pid_t, windowFrame: CGRect) async throws {
        guard isTrusted else { throw SendError.notTrusted }
        guard let app = NSRunningApplication(processIdentifier: pid) else { throw SendError.appNotRunning }
        let previousApp = NSWorkspace.shared.frontmostApplication
        let mouseBefore = CGEvent(source: nil)?.location
        defer {
            if let p = mouseBefore { CGWarpMouseCursorPosition(p) }
            if let prev = previousApp, prev.processIdentifier != pid { giveBackFront(to: prev) }
        }
        try await bringToFront(app, windowFrame: windowFrame, point: point)
        CGWarpMouseCursorPosition(point)   // the wheel goes to what is under the pointer
        try await Task.sleep(nanoseconds: 100_000_000)
        for _ in 0..<times {
            let e = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .line,
                            wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
            e?.location = point
            e?.post(tap: .cghidEventTap)
            try await Task.sleep(nanoseconds: 60_000_000)
        }
        try await Task.sleep(nanoseconds: 400_000_000)   // let the list settle
    }

    /// Right-clicks `point` in the target window, reads the menu that pops up, and clicks the item
    /// whose text contains `item` (e.g. “转文字”). Presses Esc and returns false if it is not there.
    public static func chooseFromContextMenu(_ item: String, at point: CGPoint, inPID pid: pid_t,
                                             windowFrame: CGRect, then followUp: CGPoint? = nil) async throws -> Bool {
        guard isTrusted else { throw SendError.notTrusted }
        guard let app = NSRunningApplication(processIdentifier: pid) else { throw SendError.appNotRunning }
        let previousApp = NSWorkspace.shared.frontmostApplication
        let mouseBefore = CGEvent(source: nil)?.location
        defer {
            if let p = mouseBefore { CGWarpMouseCursorPosition(p) }
            if let prev = previousApp, prev.processIdentifier != pid { giveBackFront(to: prev) }
        }
        try await bringToFront(app, windowFrame: windowFrame, point: point)
        let before = Set(windowIDs(of: pid))

        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)?
            .post(tap: .cghidEventTap)

        // The menu is a new window of the same app. Read it and find the item.
        let wanted = TextMatch.normalize(item)
        var trace: [String] = []
        defer { lastTrace = trace.joined(separator: " | ") }
        for attempt in 0..<8 {
            try await Task.sleep(nanoseconds: 250_000_000)
            let fresh = windowIDs(of: pid).filter { !before.contains($0) }
            if attempt == 0 || attempt == 7 { trace.append("try\(attempt): new windows \(fresh)") }
            for (id, rect) in windowBounds(of: pid) where fresh.contains(id) {
                guard let image = try? await WindowCapture.captureScreenRect(rect, ofPID: pid),
                      let ocr = try? OCRService.recognize(image) else { trace.append("#\(id) capture failed"); continue }
                guard let line = ocr.lines.first(where: { TextMatch.normalize($0.text).contains(wanted) }) else {
                    trace.append("#\(id) \(Int(rect.width))x\(Int(rect.height)) text: \(ocr.lines.map(\.text))")
                    continue
                }
                let target = CGPoint(x: rect.minX + line.box.midX * rect.width,
                                     y: rect.minY + (1 - line.box.midY) * rect.height)
                trace.append("#\(id) clicked “\(line.text)”")
                click(at: target)
                try await Task.sleep(nanoseconds: 300_000_000)
                if let followUp {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    click(at: followUp)
                    try await Task.sleep(nanoseconds: 300_000_000)
                }
                return true
            }
        }
        key(53)   // Esc: close the menu, nothing chosen
        return false
    }

    /// On-screen windows of the app with their bounds (top-left screen coordinates).
    private static func windowBounds(of pid: pid_t) -> [(CGWindowID, CGRect)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == pid,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return (CGWindowID(id), CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0))
        }
    }

    private static func windowIDs(of pid: pid_t) -> [CGWindowID] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == pid,
                  let id = w[kCGWindowNumber as String] as? Int else { return nil }
            return CGWindowID(id)
        }
    }

    /// For the user: brings the chat app forward (and clicks `point`, e.g. a contact row) and
    /// leaves it in front, because the user wants to work there now.
    public static func showForUser(pid: pid_t, windowFrame: CGRect, click point: CGPoint?) async throws {
        guard let app = NSRunningApplication(processIdentifier: pid) else { throw SendError.appNotRunning }
        guard let point else {
            NSApp.yieldActivation(to: app)
            app.activate()
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            return
        }
        guard isTrusted else { throw SendError.notTrusted }
        try await bringToFront(app, windowFrame: windowFrame, point: point)
        click(at: point)
    }

    /// Puts the app you were using back in front (the Accessibility way works from the background).
    private static func giveBackFront(to app: NSRunningApplication) {
        app.activate()
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                     kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    /// Activates the app, raises the exact window, and makes sure nothing covers `point`.
    private static func bringToFront(_ app: NSRunningApplication, windowFrame: CGRect, point: CGPoint) async throws {
        let pid = app.processIdentifier
        // macOS 14+ cooperative activation: we must yield before the target can come forward.
        NSApp.yieldActivation(to: app)
        app.activate()
        func waitFront(_ tries: Int) async throws -> Bool {
            for _ in 0..<tries where NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        }
        // A yield only works while this app is in front. When another app is (you are working in
        // it), ask through the Accessibility API instead, as assistive tools do.
        if try await !waitFront(8) {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString,
                                         kCFBooleanTrue)
            guard try await waitFront(15) else { throw SendError.couldNotActivate }
        }
        raiseWindow(pid: pid, frame: windowFrame)
        for _ in 0..<15 where topWindow(at: point)?.pid != pid {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if let top = topWindow(at: point), top.pid != pid { throw SendError.windowCovered(top.desc) }
    }

    // MARK: Background input (WeChat 4.1 accepts keystrokes sent to its process while inactive)

    /// Seconds since the user last touched the mouse, keyboard or trackpad.
    public static var userIdleSeconds: Double {
        let kinds: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel,
                                    .leftMouseDragged, .flagsChanged]
        return kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    /// Types text straight into the app's focused field without bringing it to the front,
    /// moving the mouse or using the clipboard. Sent in short pieces, like fast typing.
    public static func typeInBackground(_ text: String, toPID pid: pid_t) async {
        let src = CGEventSource(stateID: .privateState)
        for (i, piece) in pieces(text).enumerated() {
            if i > 0 { try? await Task.sleep(nanoseconds: UInt64.random(in: 40_000_000...90_000_000)) }
            let chars = Array(piece.utf16)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            up?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            down?.postToPid(pid)
            up?.postToPid(pid)
        }
    }

    /// The text cut into pieces of at most ~16 UTF-16 units (the system takes ~20 per event).
    /// A piece starting with a line break reads as Return (the chat would send it), so line
    /// breaks always end the piece they follow, never start one.
    nonisolated static func pieces(_ text: String) -> [String] {
        var out: [String] = []
        var piece = ""
        for ch in text {
            if ch.isNewline, !piece.isEmpty { piece.append(ch); continue }
            if !piece.isEmpty, piece.utf16.count + ch.utf16.count > 16 {
                out.append(piece)
                piece = ""
            }
            piece.append(ch)
        }
        if !piece.isEmpty { out.append(piece) }
        return out
    }

    /// Presses one key in the app without bringing it to the front (e.g. 36 = Return, 51 = Delete).
    public static func keyInBackground(_ code: CGKeyCode, toPID pid: pid_t, times: Int = 1) async {
        let src = CGEventSource(stateID: .privateState)
        for _ in 0..<times {
            CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.postToPid(pid)
            CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.postToPid(pid)
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// What was on top at the click point during the last send (diagnostics).
    public private(set) static var lastTrace = ""

    private static func topWindowOwner(at p: CGPoint) -> String { topWindow(at: p)?.desc ?? "none" }

    /// Front-most normal window containing the point (screen coordinates, top-left origin).
    private static func topWindow(at p: CGPoint) -> (pid: pid_t, desc: String)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard r.contains(p) else { continue }
            let pid = (w[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) } ?? 0
            return (pid, "\(w[kCGWindowOwnerName as String] ?? "?") \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))")
        }
        return nil
    }

    /// Uses the Accessibility API to bring one specific window of the app to the front.
    private static func raiseWindow(pid: pid_t, frame: CGRect) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        let match = windows.first { w in
            var posRef: CFTypeRef?, sizeRef: CFTypeRef?
            var pos = CGPoint.zero, size = CGSize.zero
            guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let pv = posRef, let sv = sizeRef else { return false }
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sv as! AXValue, .cgSize, &size)
            return abs(pos.x - frame.minX) < 4 && abs(pos.y - frame.minY) < 4
                && abs(size.width - frame.width) < 4 && abs(size.height - frame.height) < 4
        } ?? windows.first
        guard let win = match else { return }
        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
    }

    /// Checks whether posted input events actually take effect (moves the cursor and reads it back).
    public static func diagnose() -> String {
        let before = CGEvent(source: nil)?.location ?? .zero
        let probe = CGPoint(x: before.x + 37, y: before.y + 23)
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: probe, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(150_000)
        let after = CGEvent(source: nil)?.location ?? .zero
        CGWarpMouseCursorPosition(before)
        let moved = abs(after.x - probe.x) < 2 && abs(after.y - probe.y) < 2
        return "AXTrusted=\(AXIsProcessTrusted()) PostEventAccess=\(CGPreflightPostEventAccess()) "
            + "posted-mouse-move-took-effect=\(moved)"
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            dict.forEach { item.setData($0.value, forType: $0.key) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private static func click(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
