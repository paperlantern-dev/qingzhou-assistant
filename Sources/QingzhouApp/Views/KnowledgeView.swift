import AppKit
import QingzhouCore
import SwiftUI
import UniformTypeIdentifiers

/// 知识库: the price table first (changed most often), the other files, the learned answers,
/// and the folder. Files dragged onto the page are added. (To try a customer's question, ask 小轻舟.)
struct KnowledgeView: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var dropping = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "知识库 \(ctl.kb?.files.count ?? 0)") {
                    Button("＋ 添加文件", action: pickFiles).buttonStyle(PillButtonStyle())
                }
                if let price = priceFile { priceCard(price) }
                files
                folderLine
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 20)
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accentSoft.opacity(0.5)))
                    .overlay(Text("松手就加进知识库").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.blueText))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping, perform: drop)
        .onAppear { ctl.ensureKBFresh() }
    }

    // MARK: 价格表

    /// The first price table among the files (a csv with a name and a price column).
    private var priceFile: (name: String, items: Int)? {
        for f in ctl.kb?.files ?? [] {
            let n = ctl.priceItems(in: f)
            if n > 0 { return (f, n) }
        }
        return nil
    }

    private func priceCard(_ price: (name: String, items: Int)) -> some View {
        let days = ctl.modified(price.name).map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0 } ?? 0
        return HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 16)).foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38).background(Circle().fill(Theme.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text("价格表").font(.system(size: 14, weight: .semibold))
                (Text("\(price.items) 样 · ")
                    + Text(days == 0 ? "今天更新过" : "\(days) 天没改了").foregroundColor(days >= 3 ? Theme.amber : Theme.sub))
                    .font(.system(size: 13)).foregroundStyle(Theme.sub)
                if !ctl.options.soldOut.isEmpty {
                    Text("卖完：" + ctl.options.soldOut.joined(separator: "、")).font(.system(size: 12))
                        .foregroundStyle(Theme.amber).lineLimit(2)
                        .help("跟小轻舟说“××有货了”就恢复")
                }
            }
            Spacer(minLength: 8)
            Button("打开改价") { open(price.name) }.buttonStyle(PrimaryButtonStyle(height: 30)).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    // MARK: 其他资料

    private var files: some View {
        let kb = ctl.kb
        let others = (kb?.files ?? []).filter { $0 != priceFile?.name && $0 != LearnedQA.fileName }
        let learned = kb?.chunks.filter { $0.source == LearnedQA.fileName }.count ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Text("其他资料").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sub).padding(.bottom, 2)
            if others.isEmpty, learned == 0, priceFile == nil {
                EmptyState(icon: "tray.and.arrow.down", title: "知识库是空的", detail: "把价格表、发货说明拖到这里")
            }
            ForEach(others, id: \.self) { f in
                row(icon: "doc.text", title: (f as NSString).deletingPathExtension,
                    right: "\(kb?.chunks.filter { $0.source == f }.count ?? 0) 段") { open(f) }
            }
            if learned > 0 {
                row(icon: "lightbulb", title: "从你回复学的问答", right: "\(learned) 条") { open(LearnedQA.fileName) }
            }
            row(icon: "photo", title: "商品照片", right: photoCount == 0 ? "还没放" : "\(photoCount) 张") { ctl.openPhotoFolder() }
            Text("照片用品名起名，比如“芒果.jpg”“春见 2.jpg”。客人问“多大”“有图吗”，回完就自动发一张。")
                .font(.system(size: 12)).foregroundStyle(Theme.sub).padding(.top, 6)
            if let skipped = kb?.skipped, !skipped.isEmpty {
                Text("读不了：\(skipped.joined(separator: "、"))").font(.system(size: 12)).foregroundStyle(Theme.amber).padding(.top, 6)
            }
        }
    }

    private var photoCount: Int { ctl.productPhotos.count }

    private func row(icon: String, title: String, right: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32).background(Circle().fill(Theme.accentSoft))
                Text(title).font(.system(size: 14)).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 8)
                Text(right).font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开这个文件")
    }

    // MARK: 文件夹

    private var folderLine: some View {
        HStack(spacing: 14) {
            Button("打开文件夹") { NSWorkspace.shared.open(ctl.kbFolder) }
            Button("换文件夹…", action: chooseFolder)
        }
        .buttonStyle(.link).font(.system(size: 12)).padding(.top, 4)
        .help(ctl.kbFolder.path)
    }

    private func open(_ file: String) {
        NSWorkspace.shared.open(ctl.kbFolder.appendingPathComponent(file))
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = KnowledgeBase.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "加进知识库"
        if panel.runModal() == .OK { ctl.addKnowledgeFiles(panel.urls) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = ctl.kbFolder
        panel.prompt = "用这个文件夹"
        if panel.runModal() == .OK, let url = panel.url { ctl.setKBFolder(url) }
    }

    /// Files dropped on the page go into the knowledge folder.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url { urls.append(url) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { if !urls.isEmpty { ctl.addKnowledgeFiles(urls) } }
        return true
    }
}
