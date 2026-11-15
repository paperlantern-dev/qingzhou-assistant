import AppKit
import SwiftUI

// A stand-in for the WeChat desktop window, used to test the assistant end to end
// without touching WeChat. Layout mimics WeChat: contact list with red unread badges,
// bubbles, input at the bottom.

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let fromMe: Bool
    let text: String
    let time: Date
    /// Voice message: its length, the words, and whether “转文字” was used.
    var voiceSeconds: Int? = nil
    var transcript: String? = nil
    var transcribed = false
    /// A picture message: the pasted file's name (its text reads "[图片] name").
    var picture: String? = nil
    /// A sticker (表情): a small picture without a bubble.
    var sticker = false
    /// My picture that WeChat could not send: a red “!” next to it.
    var failed = false
}

/// A picture pasted into the input box, waiting for Return (like WeChat).
struct PastedPicture {
    let name: String
    let image: NSImage?
}

struct Contact: Identifiable, Codable {
    let id: String          // unique key
    var messages: [ChatMessage]
    var unread: Int
    var isGroup = false
    /// Shown name; a group may have exactly the same name as a person.
    var display: String? = nil
    var name: String { display ?? id }
    /// Header text: groups show their member count, like WeChat ("客户·王女士 (12)").
    var headerTitle: String { isGroup ? "\(name) (12)" : name }
}

@MainActor
final class MockChat: ObservableObject {
    @Published var contacts: [Contact]
    @Published var selected: String
    @Published var draft = ""
    @Published var scriptOn: Bool
    @Published var nextIncoming = ""
    @Published var nextSender = "客户·王女士"
    @Published var pendingPicture: PastedPicture?
    /// Sent pictures by message id, to show them (the log has their names).
    private(set) var pictures: [UUID: NSImage] = [:]
    /// Raw input events this app received (for diagnosing automated sends).
    private var events: [String] = []
    private var monitor: Any?

    let nonce = "QZ-\(Int.random(in: 1000...9999))"
    /// Where customers' pictures and stickers come from (`picture:product.png`, `sticker:smile.png`).
    var mediaFolder = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("test-fixtures/images")
    /// `--fail-pictures`: my pictures don't go through, like WeChat's red “!”.
    var failPictures = false
    private let logURL: URL?
    /// Remaining scripted questions per customer.
    private var script: [String: [String]]

    static let customers = ["客户·王女士", "客户·李先生", "客户·张小姐"]

    init(logURL: URL?, scriptOn: Bool) {
        self.logURL = logURL
        self.scriptOn = scriptOn
        script = [
            "客户·王女士": ["你好，我想问一下订单 \(nonce) 什么时候能发货？", "好的，那能开发票吗？"],
            "客户·李先生": ["voice:5:你好，满多少包邮啊？", "好的谢谢啦"],                  // voice, then thanks
            "客户·张小姐": ["请问支持七天无理由退货吗？", "你们周日有线下门店可以去试穿吗？"], // not in the knowledge base
        ]
        let old = Date().addingTimeInterval(-3600)
        contacts = Self.customers.map { name in
            Contact(id: name, messages: [
                ChatMessage(id: UUID(), fromMe: false, text: "在吗？", time: old),
                ChatMessage(id: UUID(), fromMe: true, text: "在的，请问有什么可以帮您？", time: old),
            ], unread: 0)
        } + [
            // Same name as a customer, like a real WeChat group named after its owner.
            Contact(id: "group-wang", messages: [], unread: 0, isGroup: true, display: "客户·王女士"),
            Contact(id: "文件传输助手", messages: [], unread: 0),
        ]
        // Start on a chat nobody writes to, so every customer has to be clicked into.
        selected = "文件传输助手"
        writeLog()
        if scriptOn {
            // Customers write at staggered times, so badges pile up while the assistant is busy.
            for (i, name) in Self.customers.enumerated() { scheduleNext(for: name, after: 3 + Double(i) * 6) }
            // A group member writes too; the assistant must leave the group alone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.receive("小赵: 请问今天几点发货？", from: "group-wang")
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] e in
            let win = e.window?.title ?? "-"
            let desc = e.type == .keyDown
                ? "key code=\(e.keyCode) cmd=\(e.modifierFlags.contains(.command)) window=\(win)"
                : "click at=\(Int(e.locationInWindow.x)),\(Int(e.locationInWindow.y)) window=\(win)"
            self?.events.append(desc)
            // ⌘V with a picture on the clipboard: it goes into the input box as a picture, like WeChat.
            let paste = e.type == .keyDown && e.keyCode == 9 && e.modifierFlags.contains(.command) && win == "模拟微信"
            let tookPicture = paste && self?.pastePicture() == true
            self?.writeLog()
            return tookPicture ? nil : e
        }
    }

    /// Takes a picture file or picture data from the clipboard into the input box. false = none there.
    func pastePicture() -> Bool {
        let board = NSPasteboard.general
        let kinds = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "tif", "tiff"]
        let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if let file = files.first(where: { kinds.contains($0.pathExtension.lowercased()) }) {
            pendingPicture = PastedPicture(name: file.lastPathComponent,
                                           image: NSImage(contentsOf: file) ?? NSImage(pasteboard: board))
        } else if board.availableType(from: [.png, .tiff]) != nil, let image = NSImage(pasteboard: board) {
            pendingPicture = PastedPicture(name: "图片.png", image: image)
        } else {
            return false
        }
        events.append("pasted picture=\(pendingPicture?.name ?? "")")
        return true
    }

    var current: Contact { contacts.first { $0.id == selected } ?? contacts[0] }

    func select(_ name: String) {
        selected = name
        update(name) { $0.unread = 0 }
        events.append("open chat=\(name)")
        writeLog()
    }

    /// Return or 发送: the pasted picture (if any) goes first, then the typed text.
    func sendMine() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let picture = pendingPicture
        guard picture != nil || !text.isEmpty else { return }
        let to = selected
        if let picture {
            pendingPicture = nil
            let id = UUID()
            pictures[id] = picture.image
            update(to) {
                $0.messages.append(ChatMessage(id: id, fromMe: true, text: "[图片] \(picture.name)", time: Date(),
                                               picture: picture.name, failed: failPictures))
            }
            events.append("\(failPictures ? "failed" : "sent") picture=\(picture.name)")
        }
        if !text.isEmpty {
            draft = ""
            update(to) { $0.messages.append(ChatMessage(id: UUID(), fromMe: true, text: text, time: Date())) }
        }
        writeLog()
        if scriptOn { scheduleNext(for: to, after: Double.random(in: 4...8)) }
    }

    /// Text, or a voice message written as "voice:<seconds>:<words>".
    func receive(_ text: String, from name: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // "me!:" is the owner answering although the assistant did not (a chat handed to him).
        if scriptOn, !t.hasPrefix("me"), script[name]?.first?.hasPrefix("me!:") == true { scheduleNext(for: name, after: 6) }
        if t.hasPrefix("me:") || t.hasPrefix("me!:") {   // the shop owner typing a reply themselves (from the phone)
            let said = String(t.dropFirst(t.hasPrefix("me!:") ? 4 : 3))
            update(name) { $0.messages.append(ChatMessage(id: UUID(), fromMe: true, text: said, time: Date())) }
            writeLog()
            if scriptOn { scheduleNext(for: name, after: 3) }
            return
        }
        var message = ChatMessage(id: UUID(), fromMe: false, text: t, time: Date())
        let parts = t.split(separator: ":", maxSplits: 2).map(String.init)
        if parts.count == 3, parts[0] == "voice", let secs = Int(parts[1]) {
            message = ChatMessage(id: UUID(), fromMe: false, text: "[语音]", time: Date(),
                                  voiceSeconds: secs, transcript: parts[2])
        } else if parts.count == 2, parts[0] == "picture" || parts[0] == "sticker" {
            // A customer's picture or sticker, from the media folder.
            let sticker = parts[0] == "sticker"
            message = ChatMessage(id: message.id, fromMe: false, text: sticker ? "[动画表情]" : "[图片]",
                                  time: Date(), picture: parts[1], sticker: sticker)
            pictures[message.id] = NSImage(contentsOf: mediaFolder.appendingPathComponent(parts[1]))
        }
        update(name) {
            $0.messages.append(message)
            if name != selected { $0.unread += 1 }
        }
        // Like WeChat, the chat with the newest message moves to the top of the list.
        if let i = contacts.firstIndex(where: { $0.id == name }) {
            let c = contacts.remove(at: i)
            contacts.insert(c, at: 0)
        }
        writeLog()
    }

    /// `--demo-media`: 王女士's chat shows her photo and question, my picture that failed, and her sticker.
    func demoMedia() {
        let name = "客户·王女士"
        receive("picture:product.png", from: name)
        receive("这个多少钱啊", from: name)
        let mine = UUID()
        pictures[mine] = NSImage(contentsOf: mediaFolder.appendingPathComponent("address.png"))
        update(name) {
            $0.messages.append(ChatMessage(id: mine, fromMe: true, text: "[图片] address.png", time: Date(),
                                           picture: "address.png", failed: true))
        }
        receive("sticker:smile.png", from: name)
        select(name)
    }

    /// “转文字” on a voice message: its words appear below the bubble.
    func transcribe(_ id: UUID) {
        guard let c = contacts.firstIndex(where: { $0.id == selected }),
              let m = contacts[c].messages.firstIndex(where: { $0.id == id }) else { return }
        contacts[c].messages[m].transcribed = true
        events.append("transcribed in chat=\(selected)")
        writeLog()
    }

    /// Replaces the scripted questions (e.g. for a follow-up visit) and starts them.
    /// Months of old chat above the newest messages, for 读以前的聊天.
    func useLongHistory() {
        let pairs: [(String, String)] = [
            ("脐橙是现摘的吗", "对，现摘的，个个都是好的"), ("放久了会不会不好吃", "不会，都是现摘现发"),
            ("多少钱一斤", "90一斤"), ("你们发什么快递", "顺丰，泡沫箱发"), ("能便宜点吗", "都是实在价，不讲了"),
            ("猕猴桃怎么放熟", "跟苹果放一起，两三天就软"), ("几天能到", "一般隔天就到"), ("水蜜桃是软的吗", "这批是脆的，放两天就软"),
            ("收到要马上放冰箱吗", "放冷藏，别放冷冻"), ("爱媛是什么", "果冻橙，皮薄汁多"),
            ("能开发票吗", "可以，备注抬头"), ("坏了能退吗", "拍照给我，我看下"),
        ]
        let start = Date().addingTimeInterval(-86_400 * 30)
        for name in ["客户·王女士", "客户·李先生"] {
            var old: [ChatMessage] = []
            for (i, p) in pairs.enumerated() {
                let t = start.addingTimeInterval(Double(i) * 3600)
                old.append(ChatMessage(id: UUID(), fromMe: false, text: p.0, time: t))
                old.append(ChatMessage(id: UUID(), fromMe: true, text: p.1, time: t))
            }
            // A made-up address (示例市 / 示例路 do not exist), there to test that addresses are hidden.
            old.append(ChatMessage(id: UUID(), fromMe: false, text: "地址：示例市示例区示例路88号 张三 13812345678", time: start.addingTimeInterval(50_000)))
            old.append(ChatMessage(id: UUID(), fromMe: true, text: "收到，示例市示例区示例路88号，明天发", time: start.addingTimeInterval(50_100)))
            update(name) { $0.messages = old + $0.messages }
        }
        writeLog()
    }

    func useScript(_ lines: [String: [String]]) {
        script = lines
        scriptOn = true
        for name in lines.keys { scheduleNext(for: name, after: 3) }
    }

    private func scheduleNext(for name: String, after seconds: Double) {
        guard var lines = script[name], !lines.isEmpty else { return }
        let line = lines.removeFirst()
        script[name] = lines
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.receive(line, from: name)
        }
    }

    private func update(_ name: String, _ change: (inout Contact) -> Void) {
        guard let i = contacts.firstIndex(where: { $0.id == name }) else { return }
        change(&contacts[i])
    }

    /// Ground-truth log (independent of OCR) so tests can verify what was really sent, and to whom.
    private func writeLog() {
        guard let logURL else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let payload: [String: AnyEncodable] = [
            "nonce": AnyEncodable(nonce), "contacts": AnyEncodable(contacts), "inputEvents": AnyEncodable(events),
        ]
        try? enc.encode(payload).write(to: logURL)
    }
}

struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeFn = value.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}

// MARK: - Chat window

private let weGreen = Color(red: 0.58, green: 0.93, blue: 0.41)
private let weRed = Color(red: 0.98, green: 0.32, blue: 0.32)

struct ChatWindowView: View {
    @ObservedObject var chat: MockChat
    @FocusState private var inputFocused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(chat.current.headerTitle).font(.system(size: 17, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 20).frame(height: 56)
                Divider()
                messageList
                Divider()
                inputArea.frame(height: 150)
            }
            .background(Color(white: 0.96))
        }
        .foregroundColor(.black)
        .environment(\.colorScheme, .light)
        .frame(minWidth: 820, minHeight: 600)
        .onAppear { openWindow(id: "control"); inputFocused = true }
        // Like WeChat: opening a chat puts the cursor in its input box.
        .onChange(of: chat.selected) { inputFocused = true }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color(white: 0.9)).frame(height: 56)
                .overlay(Text("搜索").font(.system(size: 12)).foregroundColor(.gray))
            ForEach(chat.contacts) { c in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.4)).frame(width: 36, height: 36)
                        .overlay(alignment: .topTrailing) {
                            if c.unread > 0 {
                                Text("\(c.unread)")
                                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Circle().fill(weRed))
                                    .offset(x: 6, y: -6)
                            }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.name).font(.system(size: 13))
                        Text(c.messages.last?.text ?? "").font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                    }
                    Spacer()
                    // Like WeChat: time of the last message on the right ("07:16").
                    if let t = c.messages.last?.time {
                        Text(t, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.system(size: 11)).foregroundColor(.gray)
                            .frame(maxHeight: .infinity, alignment: .top).padding(.top, 14)
                    }
                }
                .padding(.horizontal, 12).frame(height: 62)
                .background(c.id == chat.selected ? Color(white: 0.8) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { chat.select(c.id) }
            }
            Spacer()
        }
        .background(Color(white: 0.91))
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(chat.current.messages) { bubbleRow($0).id($0.id) }
                }
                .padding(.vertical, 16)
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scrollToEnd(proxy) } }
            .onChange(of: chat.current.messages.count) { scrollToEnd(proxy) }
            .onChange(of: chat.selected) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = chat.current.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private func bubbleRow(_ m: ChatMessage) -> some View {
        let avatar = RoundedRectangle(cornerRadius: 4)
            .fill(m.fromMe ? Color.blue.opacity(0.35) : Color.orange.opacity(0.45))
            .frame(width: 36, height: 36)
        let bubble = VStack(alignment: .leading, spacing: 6) {
            if m.picture != nil {   // like WeChat: just the picture, no bubble and no text
                HStack(spacing: 8) {
                    if m.failed {   // WeChat's red “!” for a message that did not go out
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 18)).foregroundColor(.red)
                    }
                    pictureView(chat.pictures[m.id], maxSide: m.sticker ? 90 : 160)
                }
            } else {
                Group {
                    if let secs = m.voiceSeconds {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("\(secs)\"")
                        }
                        .frame(width: CGFloat(60 + secs * 6), alignment: .leading)
                    } else {
                        Text(m.text)
                    }
                }
                .font(.system(size: 15))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 5).fill(m.fromMe ? weGreen : Color.white))
                .contextMenu {
                    if m.voiceSeconds != nil {
                        Button("收藏") {}
                        Button("转文字") { chat.transcribe(m.id) }
                        Button("引用") {}
                    }
                }
                if m.transcribed, let words = m.transcript {   // like WeChat: words below the voice bubble
                    Text(words)
                        .font(.system(size: 15))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.7)))
                }
            }
        }
        .frame(maxWidth: 340, alignment: m.fromMe ? .trailing : .leading)
        return HStack(alignment: .top, spacing: 10) {
            if m.fromMe { Spacer(minLength: 60); bubble; avatar } else { avatar; bubble; Spacer(minLength: 60) }
        }
        .padding(.horizontal, 20)
    }

    /// A picture message (or a placeholder when its picture could not be read).
    private func pictureView(_ image: NSImage?, maxSide: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").font(.system(size: maxSide * 0.6)).foregroundColor(.gray)
            }
        }
        .frame(maxWidth: maxSide, maxHeight: maxSide, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                ForEach(["face.smiling", "folder", "scissors", "bubble.left"], id: \.self) {
                    Image(systemName: $0).foregroundColor(.gray)
                }
            }
            .padding(.top, 10)
            TextField("", text: $chat.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($inputFocused)
                .onSubmit { chat.sendMine(); inputFocused = true }
            if let pasted = chat.pendingPicture {   // a pasted picture waits in the input box until Return
                pictureView(pasted.image, maxSide: 40)
            }
            Spacer()
            HStack {
                Spacer()
                Button("发送(S)") { chat.sendMine() }
                    .buttonStyle(.bordered)
            }
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 20)
        .background(Color.white)
    }
}

// MARK: - Control window (not part of the chat; the assistant does not capture it)

struct ControlView: View {
    @ObservedObject var chat: MockChat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模拟器控制（扮演客户）").font(.headline)
            Picker("谁发", selection: $chat.nextSender) {
                ForEach(MockChat.customers, id: \.self) { Text($0).tag($0) }
            }
            HStack {
                TextField("客户要发的消息", text: $chat.nextIncoming)
                    .onSubmit(sendIncoming)
                Button("客户发送", action: sendIncoming)
            }
            Toggle("自动剧本：3 位客户错开发消息，我回复后客户再追问", isOn: $chat.scriptOn)
            Text("本次编号：\(chat.nonce)").font(.caption).foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 440)
    }

    private func sendIncoming() {
        chat.receive(chat.nextIncoming, from: chat.nextSender)
        chat.nextIncoming = ""
    }
}

@main
struct MockWeChatApp: App {
    @NSApplicationDelegateAdaptor(MockAppDelegate.self) var delegate

    // The windows are made by MockAppDelegate: launched with some arguments, macOS treats them as
    // files to open and skips SwiftUI's windows (the assistant's own app does the same).
    var body: some Scene {
        Settings { EmptyView() }
    }

    /// The chat, set up from the launch arguments.
    @MainActor static let chat: MockChat = {
        let args = CommandLine.arguments
        var logURL: URL?
        if let i = args.firstIndex(of: "--log"), i + 1 < args.count { logURL = URL(fileURLWithPath: args[i + 1]) }
        if let a = args.first(where: { $0.hasPrefix("--log=") }) { logURL = URL(fileURLWithPath: String(a.dropFirst(6))) }
        let chat = MockChat(logURL: logURL, scriptOn: args.contains("--script"))
        if args.contains("--recall") {   // a later day: only 王女士 writes, asking about last time
            chat.useScript(["客户·王女士": ["你还记得我上次问的是哪个订单号吗？"]])
        }
        if args.contains("--shop") {   // a small shop: price, reservation, consent, “我想想”
            chat.useScript([
                "客户·王女士": ["特级红富士多少钱一斤？", "那帮我留两箱10斤装的，到了告诉我"],
                "客户·李先生": ["以后有新到的水蜜桃记得告诉我哦"],
                "客户·张小姐": ["脐橙收到后怎么保存？", "好的，我想想，晚点再下单"],
            ])
        }
        if args.contains("--photos") {   // asking to see a product: its photo follows the reply
            chat.useScript([
                "客户·王女士": ["特级红富士多大的，有图吗"],
                "客户·李先生": ["脐橙怎么卖", "发张图看看"],
                "客户·张小姐": ["水蜜桃多少钱一斤"],
            ])
        }
        if args.contains("--catalog") {   // vague product questions: the answer is the whole price list
            chat.useScript([
                "客户·王女士": ["你们有什么产品"],
                "客户·李先生": ["都卖些啥水果？发个价格表看看"],
                "客户·张小姐": ["水蜜桃能便宜点吗"],
            ])
        }
        if args.contains("--combo") {   // a combination to a budget, then “that's too little”
            chat.useScript(["客户·王女士": ["帮我搭配一下，500块左右，自己家吃", "这个加起来没到500吧，我要500左右的"]])
        }
        if args.contains("--long-history") { chat.useLongHistory() }
        if args.contains("--bargain") {   // a rule hands the chat to the owner, who answers himself
            chat.useScript(["客户·王女士": ["水蜜桃能便宜点吗", "me!:不好意思哈，都是当天的货，已经是实在价了", "有烂的要投诉的", "me!:拍个照给我，烂的按个退给你"]])
        }
        if args.contains("--learn") {   // a question the knowledge base can't answer; the owner answers it
            chat.useScript(["客户·王女士": ["你们店门口能停车吗？", "me:能停，店门口有三个车位", "me:周末人多建议早点来"]])
        }
        if let a = args.first(where: { $0.hasPrefix("--media=") }) { chat.mediaFolder = URL(fileURLWithPath: String(a.dropFirst(8))) }
        if args.contains("--fail-pictures") { chat.failPictures = true }
        if args.contains("--media-script") {   // pictures and stickers from customers
            chat.useScript([
                "客户·王女士": ["picture:product.png", "这个多少钱啊"],
                "客户·李先生": ["picture:address.png"],
                "客户·张小姐": ["脐橙收到后怎么保存？", "sticker:smile.png"],
            ])
        }
        if let o = args.firstIndex(of: "--open"), o + 1 < args.count { chat.select(args[o + 1]) }   // start on this chat
        if args.contains("--demo-media") { chat.demoMedia() }
        if args.contains("--voice-now") {
            chat.select("客户·李先生")
            chat.receive("voice:5:你好，满多少包邮啊？", from: "客户·李先生")
        }
        return chat
    }()
}

/// Opens the chat window and the control window, whatever the launch arguments.
final class MockAppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MainActor.assumeIsolated {
            let chat = MockWeChatApp.chat
            let main = makeWindow("模拟微信", ChatWindowView(chat: chat), size: NSSize(width: 860, height: 640))
            main.center()
            let control = makeWindow("模拟器控制", ControlView(chat: chat), size: NSSize(width: 440, height: 186))
            control.setFrameTopLeftPoint(NSPoint(x: 0, y: NSScreen.main?.visibleFrame.maxY ?? 900))
            windows = [main, control]
            control.orderFront(nil)
            main.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor
    private func makeWindow<V: View>(_ title: String, _ view: V, size: NSSize) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        return w
    }
}
