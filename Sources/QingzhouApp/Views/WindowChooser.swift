import QingzhouCore
import SwiftUI

/// “选择聊天窗口”: fills the panel with every open window as a big row (covered windows
/// included). Apps that can auto-reply come first. `choose(nil)` = pick with the mouse instead.
struct WindowChooser: View {
    let currentID: CGWindowID?
    let currentBundleID: String
    let choose: (PickedWindow?) -> Void
    let cancel: () -> Void
    @State private var windows: [PickedWindow] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择聊天窗口").font(.system(size: 15, weight: .semibold))
                    Text("点一下就连接。被别的窗口挡住的也能选。").font(.system(size: 13)).foregroundStyle(Theme.sub)
                }
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.card)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if windows.isEmpty {
                        Text("没有找到窗口。最小化或在别的桌面上的窗口不会列出。")
                            .font(.system(size: 13)).foregroundStyle(Theme.sub).padding(.vertical, 20)
                    }
                    group("可以自动回复", windows.filter(canReply))
                    group("其他窗口（只能查看，不会自动回复）", windows.filter { !canReply($0) })
                }
                .padding(16)
            }

            HStack(spacing: 18) {
                Button { windows = PickedWindow.onScreen() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                Button { choose(nil) } label: { Label("用鼠标点选", systemImage: "cursorarrow.click") }
                Spacer()
            }
            .buttonStyle(.link).font(.system(size: 13))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.card)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        }
        .onAppear { windows = PickedWindow.onScreen() }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [PickedWindow]) -> some View {
        if !items.isEmpty {
            SectionHeader(title: title).padding(.top, 4)
            ForEach(items) { w in
                WindowRow(window: w, isCurrent: isCurrent(w)) { choose(w) }
            }
        }
    }

    private func canReply(_ w: PickedWindow) -> Bool {
        ChatTarget.forApp(bundleID: w.bundleID, name: w.appName).supportsAutoReply
    }

    private func isCurrent(_ w: PickedWindow) -> Bool {
        currentID.map { $0 == w.windowID } ?? (w.bundleID == currentBundleID)
    }
}

/// One window: the app's icon, its name and the window's title.
private struct WindowRow: View {
    let window: PickedWindow
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = window.icon {
                    Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                } else {
                    Image(systemName: "macwindow").font(.system(size: 22)).foregroundStyle(Theme.sub).frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.appName).font(.system(size: 14, weight: .semibold))
                    Text(window.title.isEmpty || window.title == window.appName ? "主窗口" : window.title)
                        .font(.system(size: 13)).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer(minLength: 8)
                if isCurrent { TagView(text: "当前", kind: .blue) }
            }
            .padding(.horizontal, 14).frame(minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Theme.accentSoft : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isCurrent ? Theme.accent : Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
