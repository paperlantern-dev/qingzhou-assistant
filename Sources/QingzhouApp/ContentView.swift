import QingzhouCore
import SwiftUI

enum PacingChoice: String, CaseIterable, Identifiable {
    case human = "像真人"
    case fast = "快速测试"
    var id: String { rawValue }
    var config: PacingConfig { self == .human ? .human : .fastTest }
}

enum MainTab: String, CaseIterable, Identifiable {
    case home = "动态"
    case customers = "客户"
    case knowledge = "知识库"
    case settings = "设置"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "waveform.path.ecg"
        case .customers: return "person.2"
        case .knowledge: return "book.closed"
        case .settings: return "slider.horizontal.3"
        }
    }

    /// Tests can open a tab directly (`--show-tab customers`).
    static var initial: MainTab {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--show-tab"), i + 1 < args.count else { return .home }
        return MainTab.allCases.first { "\($0)" == args[i + 1] } ?? .home
    }
}

/// The side panel next to the chat app: a slim top bar, the tab's content, and the tab bar at the bottom.
struct ContentView: View {
    @EnvironmentObject var ctl: AutoReplyController
    @StateObject private var docker = WindowDocker()
    @State private var tab: MainTab = .initial
    @State private var showChooser = CommandLine.arguments.contains("--show-chooser")   // tests can open it directly
    @State private var showAssistant = CommandLine.arguments.contains("--show-assistant")

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            if showChooser {
                WindowChooser(currentID: ctl.pickedWindow?.windowID, currentBundleID: ctl.target.bundleID,
                              choose: { picked in
                                  showChooser = false
                                  if let picked { ctl.connect(picked) } else { ctl.pickWindow() }
                              },
                              cancel: { showChooser = false })
            } else {
                if !ctl.hasScreenPermission || !ctl.hasAccessibility { permissionBanner }
                Group {
                    switch tab {
                    case .home: HomeView(showChooser: $showChooser, goSettings: { tab = .settings })
                    case .customers: CustomersView()
                    case .knowledge: KnowledgeView()
                    case .settings: SettingsView(docker: docker, showChooser: $showChooser)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { if !showAssistant { AssistantButton { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { showAssistant = true } } } }
                tabBar
            }
        }
        .overlay {
            if showAssistant {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.12).ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showAssistant = false } }
                    AssistantPanel(page: tab.rawValue) { withAnimation(.easeOut(duration: 0.2)) { showAssistant = false } }
                        .frame(maxHeight: 560)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)   // the title bar is see-through; the name sits in it
        .frame(minWidth: 340, minHeight: 520)
        .background(Theme.page)
        .tint(Theme.accent)   // switches, pickers and links in sea blue
        .onAppear {
            ctl.refreshPermissions()
            ctl.refreshCustomers()
            docker.start(bundleID: ctl.target.bundleID)
            ctl.startPreview()
        }
        .onChange(of: ctl.target) { docker.retarget(bundleID: ctl.target.bundleID, windowID: ctl.pickedWindow?.windowID) }
        .onChange(of: ctl.pickedWindow) { docker.retarget(bundleID: ctl.target.bundleID, windowID: ctl.pickedWindow?.windowID) }
    }

    // MARK: Header

    /// The window's title bar row: the traffic lights, then the sail and the name.
    private var titleBar: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 72)
            if tab == .home {   // the name only on 动态; other pages give the room to their content
                Image(systemName: "sailboat.fill").font(.system(size: 14)).foregroundStyle(Theme.accent)
                Text("轻舟").font(.system(size: 14, weight: .bold)).kerning(0.5)
            }
            Spacer()
            if ctl.isRunning, ctl.options.escToStop {
                Text("双击 Esc 暂停").font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
        }
        .padding(.trailing, 16)
        .frame(height: 40)
    }

    // MARK: Tab bar

    /// 动态 · 客户 · 关键词 · 设置 along the bottom: an icon and two words each.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { t in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: tab == t ? .semibold : .regular))
                            .frame(height: 20)
                            .overlay(alignment: .topTrailing) {
                                if t == .home, ctl.homeBadge > 0 {
                                    Text("\(ctl.homeBadge)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14)
                                        .background(Capsule().fill(Theme.badge)).offset(x: 10, y: -4)
                                }
                            }
                        Text(t.rawValue).font(.system(size: 12, weight: tab == t ? .semibold : .regular))
                    }
                    .foregroundStyle(tab == t ? Theme.accent : Theme.sub)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 4)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield").foregroundStyle(Theme.amber)
            Text(!ctl.hasScreenPermission ? "需要“屏幕录制”权限才能读取聊天窗口" : "需要“辅助功能”权限才能点击和发送")
                .font(.system(size: 13)).foregroundStyle(Theme.amber)
            Spacer()
            Button("去授权") {
                let pane = !ctl.hasScreenPermission ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
            }
            .controlSize(.small)
            Button("重新检测") { ctl.refreshPermissions() }.controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.amberSoft)
    }
}
