import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Result of a real ScreenCaptureKit capture of one window.
public struct CaptureResult {
    public let image: CGImage
    public let windowID: CGWindowID
    public let windowTitle: String
    public let capturedAt: Date
    public let durationMs: Int
}

public enum CaptureError: LocalizedError {
    case permissionDenied
    case windowNotFound(CGWindowID)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有“屏幕录制”权限。请在 系统设置 › 隐私与安全性 › 屏幕与系统音频录制 中允许“轻舟助手”，然后重启应用。"
        case .windowNotFound(let id):
            return "在可共享窗口列表中找不到窗口 #\(id)（窗口需要在屏幕上可见）。"
        case .failed(let msg):
            return "截图失败：\(msg)"
        }
    }
}

public enum WindowCapture {
    /// True when the app already has Screen Recording permission (no prompt).
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the normal system permission prompt if not yet decided.
    @discardableResult
    public static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Finds the largest visible window of an app (e.g. the main chat window).
    public static func findWindow(bundleID: String, excludingPID: pid_t? = nil) async throws -> SCWindow? {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if !hasPermission { throw CaptureError.permissionDenied }
            throw CaptureError.failed(error.localizedDescription)
        }
        return content.windows
            .filter { $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0 && $0.isOnScreen }
            .filter { excludingPID == nil || $0.owningApplication?.processID != excludingPID }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// Finds a specific window (e.g. one the user picked) if it is still open and on screen.
    public static func findWindow(id: CGWindowID) async throws -> SCWindow? {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if !hasPermission { throw CaptureError.permissionDenied }
            throw CaptureError.failed(error.localizedDescription)
        }
        return content.windows.first { $0.windowID == id }
    }

    /// Captures exactly one window using ScreenCaptureKit (works even if partly covered).
    public static func capture(window: SCWindow) async throws -> CaptureResult {
        let start = Date()
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return CaptureResult(
                image: image,
                windowID: window.windowID,
                windowTitle: window.title ?? "",
                capturedAt: Date(),
                durationMs: Int(Date().timeIntervalSince(start) * 1000)
            )
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
    }

    /// Captures a screen area (top-left coordinates) as it looks on screen, but with only this
    /// app's windows in it. Used for pop-up menus, which do not capture well on their own.
    public static func captureScreenRect(_ rect: CGRect, ofPID pid: pid_t) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first
        else { throw CaptureError.failed("没有找到屏幕") }
        let windows = content.windows.filter { $0.owningApplication?.processID == pid }
        let filter = SCContentFilter(display: display, including: windows)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: rect.minX - display.frame.minX, y: rect.minY - display.frame.minY,
                                   width: rect.width, height: rect.height)
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Tiny grayscale fingerprint, used to skip OCR when nothing on screen changed.
    public static func fingerprint(_ image: CGImage) -> [UInt8] {
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels
    }

    /// Fingerprint of one contact row (around `rowCenterY`, window points) in the sidebar,
    /// used to make sure the list did not move between looking and clicking.
    public static func rowFingerprint(_ image: CGImage, windowWidth: CGFloat, sidebarWidth: CGFloat,
                                      rowCenterY: CGFloat) -> [UInt8] {
        let scale = CGFloat(image.width) / max(1, windowWidth)
        let rect = CGRect(x: 0, y: (rowCenterY - 20) * scale, width: sidebarWidth * scale, height: 65 * scale)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty, let crop = image.cropping(to: rect) else { return [] }
        return fingerprint(crop)
    }

    public static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
