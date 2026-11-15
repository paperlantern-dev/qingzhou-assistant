import AppKit

/// A window the user picked by clicking on it.
struct PickedWindow: Equatable {
    let windowID: CGWindowID
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
}

extension PickedWindow: Identifiable {
    var id: CGWindowID { windowID }
    var label: String { title.isEmpty || title == appName ? appName : "\(appName) — \(title)" }
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }

    /// All normal windows currently on screen, including ones covered by other windows
    /// (front to back). This app's own windows and tiny helper windows are left out.
    static func onScreen() -> [PickedWindow] {
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { w -> PickedWindow? in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = (w[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }), pid != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) > 200, (b["Height"] ?? 0) > 200,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier   // another copy of this app
            else { return nil }
            return PickedWindow(windowID: CGWindowID(id), pid: pid, bundleID: app.bundleIdentifier ?? "",
                                appName: app.localizedName ?? (w[kCGWindowOwnerName as String] as? String ?? ""),
                                title: w[kCGWindowName as String] as? String ?? "")
        }
    }
}

/// “Click a window to connect it”: while active, the window under the mouse gets a green
/// outline; the next click outside this app picks it. Esc or 30 seconds cancels.
@MainActor
final class WindowPicker {
    private var monitors: [Any] = []
    private var overlay: NSPanel?
    private var timeout: Task<Void, Never>?
    private var finish: ((PickedWindow?) -> Void)?

    func start(_ completion: @escaping (PickedWindow?) -> Void) {
        stop(nil)
        finish = completion
        overlay = Self.makeOverlay()
        let move = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.highlight() }
        }
        let click = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop(Self.windowUnderMouse()) }
        }
        let escGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.stop(nil) } }
        }
        let escLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.stop(nil) }; return nil }
            return e
        }
        monitors = [move, click, escGlobal, escLocal].compactMap { $0 }
        highlight()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if !Task.isCancelled { self?.stop(nil) }
        }
    }

    private func stop(_ result: PickedWindow?) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        timeout?.cancel()
        overlay?.orderOut(nil)
        overlay = nil
        let done = finish
        finish = nil
        done?(result)
    }

    private func highlight() {
        guard let overlay, let info = Self.windowInfoUnderMouse() else { overlay?.orderOut(nil); return }
        overlay.setFrame(Self.cocoaRect(info.bounds).insetBy(dx: -3, dy: -3), display: true)
        overlay.orderFrontRegardless()
    }

    // MARK: Finding the window under the mouse

    private static func windowInfoUnderMouse() -> (id: CGWindowID, pid: pid_t, owner: String, title: String, bounds: CGRect)? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let m = NSEvent.mouseLocation
        let point = CGPoint(x: m.x, y: primaryHeight - m.y)      // to top-left screen coordinates
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for w in list {                                           // front to back
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = (w[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }), pid != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let id = w[kCGWindowNumber as String] as? Int else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard r.contains(point), r.width > 100, r.height > 100 else { continue }
            return (CGWindowID(id), pid, w[kCGWindowOwnerName as String] as? String ?? "",
                    w[kCGWindowName as String] as? String ?? "", r)
        }
        return nil
    }

    static func windowUnderMouse() -> PickedWindow? {
        guard let i = windowInfoUnderMouse() else { return nil }
        let app = NSRunningApplication(processIdentifier: i.pid)
        return PickedWindow(windowID: i.id, pid: i.pid, bundleID: app?.bundleIdentifier ?? "",
                            appName: app?.localizedName ?? i.owner, title: i.title)
    }

    private static func cocoaRect(_ r: CGRect) -> NSRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    private static func makeOverlay() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.borderColor = NSColor.systemGreen.cgColor
        v.layer?.borderWidth = 4
        v.layer?.cornerRadius = 10
        v.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.08).cgColor
        p.contentView = v
        return p
    }
}
