import QingzhouCore
import SwiftUI

/// 读以前的聊天: start, watch, stop. Shown on the 说话风格 page.
struct HistoryCard: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var chats = 30
    @State private var pages = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "读以前的聊天")
            CardBox {
                Text("挨个点开客户聊天往上翻，把以前的记录读下来，学你回客人的说法。只读，不回复。地址、电话、单号的那句整句不学，记录只存在这台电脑。")
                    .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
                if let h = ctl.history, !h.finished { progress(h) } else { setup }
                if let h = ctl.history, h.finished { result(h) }
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("读多少位客户", selection: $chats) {
                    ForEach([10, 30, 50, 100], id: \.self) { Text("\($0) 位").tag($0) }
                }
                .fixedSize()
                Picker("每位往上翻", selection: $pages) {
                    ForEach([5, 10, 20, 40], id: \.self) { Text("\($0) 屏").tag($0) }
                }
                .fixedSize()
            }
            .font(.system(size: 13))
            Button("开始读") { ctl.startHistory(maxChats: chats, pagesPerChat: pages) }
                .buttonStyle(PrimaryButtonStyle(height: 30)).fixedSize()
                .disabled(ctl.isRunning)
            Text(ctl.isRunning ? "先暂停自动回复再读" : "读的时候会点微信、翻页，电脑先别动；双击 Esc 或点“停下”随时停")
                .font(.system(size: 12)).foregroundStyle(ctl.isRunning ? Theme.amber : Theme.sub)
        }
    }

    private func progress(_ h: HistoryRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView(value: Double(h.chatsDone), total: Double(max(h.maxChats, 1))).frame(maxWidth: 180)
                Text("\(h.chatsDone)/\(h.maxChats) 位").font(.system(size: 13).monospacedDigit())
                Spacer()
                Button("停下") { ctl.stopHistory() }.buttonStyle(SoftButtonStyle())
            }
            Text(h.note.isEmpty ? (h.current.isEmpty ? "准备中…" : "正在读「\(h.current)」") : h.note)
                .font(.system(size: 12)).foregroundStyle(Theme.sub)
        }
    }

    private func result(_ h: HistoryRun) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("读了 \(h.chatsDone) 位客户，新记下 \(h.messagesAdded) 条，学到 \(h.lessonsAdded) 条你的说法" + (h.note.isEmpty ? "" : "（\(h.note)）"))
                .font(.system(size: 13, weight: .semibold))
            Text("想让整体口气也像你：点上面的“从我的聊天学”，它会用这些记录写一版说话风格给你确认。")
                .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
        }
    }
}
