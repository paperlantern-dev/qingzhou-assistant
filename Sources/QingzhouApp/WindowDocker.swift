import AppKit
import SwiftUI

/// Keeps the assistant window snapped beside the chat app's main window:
/// same height, half its width, on the right (or the left if there is no room).
@MainActor
final class WindowDocker: ObservableObject {
    @Published var enabled = true
    @Published private(set) var attached = false

    private var timer: Timer?
    private var bundleID = ""
    private var windowID: CGWindowID?

    func start(bundleID: String) {
        self.bundleID = bundleID
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        update()
    }

    func retarget(bundleID: String, windowID: CGWindowID? = nil) {
        self.bundleID = bundleID
        self.windowID = windowID
        update()
    }

    private func update() {
        guard enabled, let ours = NSApp.windows.first(where: { $0.title == "轻舟助手" && $0.isVisible }),
              let target = Self.mainWindowFrame(bundleID: bundleID, windowID: windowID),
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(target) }) ?? NSScreen.main
        else {
            attached = false
            return
        }
        let minWidth: CGFloat = 340
        let half = max(minWidth, (target.width / 2).rounded())
        let visible = screen.visibleFrame
        let rightRoom = visible.maxX - target.maxX, leftRoom = target.minX - visible.minX
        // Prefer the right side; shrink a little to fit rather than cover the chat window.
        let (x, width): (CGFloat, CGFloat)
        if rightRoom >= minWidth {
            (x, width) = (target.maxX, min(half, rightRoom))
        } else if leftRoom >= minWidth {
            let w = min(half, leftRoom)
            (x, width) = (target.minX - w, w)
        } else {
            (x, width) = (visible.maxX - half, half)   // no room: overlap the screen edge
        }
        let frame = NSRect(x: x, y: target.minY, width: width, height: target.height)
        if !ours.frame.equalTo(frame) { ours.setFrame(frame, display: true, animate: false) }
        attached = true
    }

    /// Largest normal on-screen window of the app, converted to Cocoa (bottom-left) coordinates.
    /// With `windowID`, that exact window (if still on screen); otherwise the app's largest one.
    static func mainWindowFrame(bundleID: String, windowID: CGWindowID? = nil) -> NSRect? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let rects: [CGRect] = list.compactMap { w in
            if let windowID, (w[kCGWindowNumber as String] as? Int).map(CGWindowID.init) != windowID { return nil }
            guard let pid = w[kCGWindowOwnerPID as String] as? Int, pids.contains(pid_t(pid)),
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return r.width > 300 && r.height > 300 ? r : nil
        }
        guard let r = rects.max(by: { $0.width * $0.height < $1.width * $1.height }),
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
