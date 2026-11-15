import QingzhouCore
import SwiftUI

/// 不自动回复的人: family, friends, suppliers. Their chats are never opened, answered or remembered.
struct NeverReplyCard: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "不自动回复的人")
            CardBox {
                Text("家人、朋友、供应商……名字写成\(ctl.target.name)里显示的样子。他们的会话不点开、不回复、不记录。")
                    .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
                ForEach(ctl.options.neverReply, id: \.self) { n in
                    HStack {
                        Text(n).font(.system(size: 14))
                        Spacer()
                        Button { ctl.setNeverReply(n, false) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Theme.sub).help("移出名单")
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    TextField("输入名字，比如：妈妈", text: $name).textFieldStyle(.roundedBorder).onSubmit(addName)
                    Button("添加", action: addName).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addName() {
        ctl.setNeverReply(name, true)
        name = ""
    }
}

/// 手机提醒: when something waits for the user, post it to a WeCom or Feishu group robot.
struct AlertCard: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var address = ""
    @State private var testing = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "手机提醒")
            CardBox {
                ToggleLine(title: "有事要你处理时提醒我", hint: "发到企业微信群机器人或飞书机器人，手机上就能看到",
                           isOn: $ctl.options.alertsOn)
                HStack {
                    TextField("粘贴机器人的 Webhook 地址", text: $address).textFieldStyle(.roundedBorder).onSubmit(save)
                    Button("保存", action: save).disabled(address == ctl.alertAddress || (kind == nil && !address.isEmpty))
                }
                Text(kindLine).font(.system(size: 12))
                    .foregroundStyle(kind == nil && !address.isEmpty ? Theme.amber : Theme.sub)
                HStack(spacing: 10) {
                    Button(testing ? "发送中…" : "发一条测试", action: test).disabled(testing || ctl.alertKind == nil)
                    if let result {
                        Text(result).font(.system(size: 12)).foregroundStyle(result.hasPrefix("已") ? Theme.green : Theme.amber)
                    }
                }
                Text("会把客户的名字和这句话发到你的群里。飞书机器人如果开了“自定义关键词”，填“轻舟”。")
                    .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { address = ctl.alertAddress }
    }

    private var kind: AlertWebhook.Kind? { AlertWebhook.kind(of: address) }

    private var kindLine: String {
        if address.isEmpty { return "在群设置里添加机器人，复制它的 Webhook 地址" }
        guard let kind else { return "这不是企业微信群机器人或飞书机器人的地址" }
        return address == ctl.alertAddress ? "已保存 · \(kind.name)" : "\(kind.name) · 点“保存”"
    }

    private func save() {
        guard address.isEmpty || kind != nil else { return }
        ctl.alertAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        address = ctl.alertAddress
        result = nil
    }

    private func test() {
        testing = true
        result = nil
        Task {
            let problem = await ctl.sendAlert("【轻舟助手】测试提醒：有客户消息要你处理时，会这样提醒你。")
            testing = false
            result = problem.map { "没发出去：\($0)" } ?? "已发出，看看手机"
        }
    }
}

/// 主动智能 (off by default): greets customers who went quiet. Shops that want it turn it on.
struct RevisitCard: View {
    @EnvironmentObject var ctl: AutoReplyController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "主动智能（默认关闭）")
            CardBox {
                ToggleLine(title: "主动问候很久没聊的客户",
                           hint: "每天问候几位安静了一段时间的老客户，一人一句、不推销。和“只回复、不追单”相反，需要时再打开。",
                           isOn: $ctl.options.revisitOn)
                if ctl.options.revisitOn {
                    Divider()
                    SettingLine(title: "至少安静 \(ctl.options.revisitMinDays) 天") {
                        Stepper("", value: $ctl.options.revisitMinDays, in: 1...60).labelsHidden()
                    }
                    .onChange(of: ctl.options.revisitMinDays) {
                        if ctl.options.revisitMaxDays < ctl.options.revisitMinDays {
                            ctl.options.revisitMaxDays = ctl.options.revisitMinDays
                        }
                    }
                    SettingLine(title: "最多安静 \(ctl.options.revisitMaxDays) 天（再久就不打扰了）") {
                        Stepper("", value: $ctl.options.revisitMaxDays, in: max(ctl.options.revisitMinDays, 2)...365)
                            .labelsHidden()
                    }
                    SettingLine(title: "每天最多问候 \(ctl.options.revisitPerDay) 位") {
                        Stepper("", value: $ctl.options.revisitPerDay, in: 1...20).labelsHidden()
                    }
                    Text((ctl.options.assistMode ? "辅助模式下，问候先放在首页等你确认。" : "写好就自动发。")
                         + "只在 9–21 点发；说过“别发了”的、不自动回复的、等预留到货的，都不会问候；每次安静期只问候一次。")
                        .font(.system(size: 12)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
