import QingzhouCore
import SwiftUI

/// The models reached through an API: pick one, add your own, fill in keys, test.
struct ApiList: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var editing: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ctl.options.apiConfigs) { config in
                row(config)
                if editing == config.id {
                    ApiEditor(original: config, done: { editing = nil })
                }
            }
            Button {
                let new = ApiConfig(name: "我的模型", baseURL: "https://", model: "")
                ctl.options.apiConfigs.append(new)
                editing = new.id
            } label: { Label("添加 API", systemImage: "plus") }
                .buttonStyle(.link).font(.system(size: 13))
            Text("可以加任何兼容 OpenAI 格式的接口。密钥存在 macOS 钥匙串里；发出去之前，地址、电话、收货人会被屏蔽。")
                .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ config: ApiConfig) -> some View {
        let active = ctl.activeApi?.id == config.id
        let hasKey = !ctl.apiKey(for: config).isEmpty
        return HStack(spacing: 8) {
            Button { ctl.options.apiActive = config.id } label: {
                Image(systemName: active ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(active ? Theme.accent : Theme.sub)
            }
            .buttonStyle(.plain).help("用这个")
            VStack(alignment: .leading, spacing: 1) {
                Text(config.name).font(.system(size: 14, weight: active ? .semibold : .regular))
                Text(config.model + ((config.visionModel ?? "").isEmpty ? " · 不看图" : " · 能看图"))
                    .font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
            Spacer()
            if !config.modelChoices.isEmpty && editing != config.id {
                modelMenu(config)
            }
            TagView(text: hasKey ? "已填密钥" : "没填密钥", kind: hasKey ? .green : .neutral)
            Button(editing == config.id ? "收起" : "编辑") { editing = editing == config.id ? nil : config.id }
                .buttonStyle(.link).font(.system(size: 13))
        }
        .padding(.vertical, 2)
    }

    /// Switch to another of this platform's newest models in one click.
    private func modelMenu(_ config: ApiConfig) -> some View {
        Menu("换模型") {
            ForEach(config.modelChoices, id: \.self) { choice in
                Button {
                    guard let i = ctl.options.apiConfigs.firstIndex(where: { $0.id == config.id }) else { return }
                    ctl.options.apiConfigs[i].model = choice.id
                } label: {
                    if choice.id == config.model {
                        Label("\(choice.id)（\(choice.note)）", systemImage: "checkmark")
                    } else {
                        Text("\(choice.id)（\(choice.note)）")
                    }
                }
            }
        }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 13))
    }
}

/// Editing one API: address, model, picture model, key; save, test, delete.
private struct ApiEditor: View {
    @EnvironmentObject var ctl: AutoReplyController
    let original: ApiConfig
    let done: () -> Void
    @State private var config: ApiConfig
    @State private var key = ""
    @State private var result: String?
    @State private var testing = false

    init(original: ApiConfig, done: @escaping () -> Void) {
        self.original = original
        self.done = done
        _config = State(initialValue: original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("名称", $config.name)
            field("接口地址", $config.baseURL)
            field("模型", $config.model)
            field("看图模型（可不填）", Binding(get: { config.visionModel ?? "" }, set: { config.visionModel = $0 }))
            HStack {
                Text("密钥").font(.system(size: 13)).frame(width: 110, alignment: .leading)
                SecureField(ctl.apiKey(for: original).isEmpty ? "粘贴 API Key" : "已保存；重新粘贴会替换", text: $key)
                    .textFieldStyle(.roundedBorder)
            }
            if let problem = config.problem {
                Text(problem).font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
            HStack(spacing: 10) {
                Button("保存", action: save).disabled(config.problem != nil)
                Button(testing ? "测试中…" : "测试") { Task { await test() } }
                    .disabled(testing || config.problem != nil)
                Spacer()
                Button("删除", role: .destructive) { ctl.removeApi(original); done() }.buttonStyle(.link)
            }
            .font(.system(size: 13))
            if let result {
                Text(result).font(.system(size: 12))
                    .foregroundStyle(result.hasPrefix("能用") ? Theme.green : Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft.opacity(0.5)))
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).frame(width: 110, alignment: .leading)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        if let i = ctl.options.apiConfigs.firstIndex(where: { $0.id == original.id }) { ctl.options.apiConfigs[i] = config }
        if !key.isEmpty { ctl.setApiKey(key, for: config); key = "" }
        result = "已保存"
    }

    private func test() async {
        save()
        testing = true
        result = await ctl.testApi(config)
        testing = false
    }
}
