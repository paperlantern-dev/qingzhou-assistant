import QingzhouCore
import SwiftUI

/// The top of every page: its name, and maybe one small action on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            Text(title).font(.system(size: 20, weight: .bold))
            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 2)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// “‹ 设置” and the page's title, for pages opened from a list.
struct BackHeader: View {
    let back: String
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text(back)
                }
                .font(.system(size: 14)).foregroundStyle(Theme.accent).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(title).font(.system(size: 20, weight: .bold))
        }
        .padding(.bottom, 2)
    }
}

/// 运行中 / 未运行. Pointing at it shows what a click does (暂停 or 开始), so the switch is easy to find.
struct StatusPill: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var hover = false

    var body: some View {
        Button { ctl.isRunning ? ctl.stop() : ctl.start() } label: {
            HStack(spacing: 6) {
                if hover {
                    Image(systemName: ctl.isRunning ? "pause.fill" : "play.fill").font(.system(size: 9, weight: .bold))
                    Text(ctl.isRunning ? (ctl.dryRun ? "停止" : "暂停") : "开始")
                } else {
                    if ctl.isRunning { PulsingDot() } else { Circle().fill(Theme.sub.opacity(0.55)).frame(width: 7, height: 7) }
                    Text(ctl.isRunning ? (ctl.dryRun ? "演练中" : "运行中") : "未运行")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 11).frame(height: 26)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 && (ctl.isRunning || ctl.target.supportsAutoReply) }
        .disabled(!ctl.isRunning && !ctl.target.supportsAutoReply)
        .help(ctl.isRunning ? "暂停自动回复" : "开始自动回复")
    }

    private var color: Color {
        if ctl.isRunning { return Theme.green }
        return hover ? Theme.accent : Theme.neutralText
    }

    private var background: Color {
        if ctl.isRunning { return hover ? Theme.greenSoft.opacity(0.7) : Theme.greenSoft }
        return hover ? Theme.accentSoft : Theme.neutralSoft
    }
}

/// The green “running” dot, gently breathing so it reads as live.
struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Theme.greenDot).frame(width: 7, height: 7)
            .background(Circle().fill(Theme.greenDot.opacity(0.35)).scaleEffect(on ? 2.2 : 1).opacity(on ? 0 : 1))
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

/// An empty list: a faint icon, a short line, and maybe one more line under it.
struct EmptyState: View {
    let icon: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.sub.opacity(0.5))
                .padding(.bottom, 2)
            Text(title).font(.system(size: 14, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 16)
    }
}
