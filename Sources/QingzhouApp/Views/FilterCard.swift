import QingzhouCore
import SwiftUI

/// 回复范围: only the people on a list, only “@我” in groups, and 双击 Esc 暂停.
struct FilterCard: View {
    @EnvironmentObject var ctl: AutoReplyController
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "回复范围")
            CardBox {
                ToggleLine(title: "只回名单里的人", hint: "打开后，只点开、只回复名单里的会话，其他人一律不回",
                           isOn: $ctl.options.onlyListOn)
                if ctl.options.onlyListOn { onlyList }
                Divider()
                ToggleLine(title: "群里只回 @我 的消息", hint: groupHint, isOn: $ctl.options.groupAtOnly)
                if ctl.options.groupAtOnly { myName }
                Divider()
                ToggleLine(title: "双击 Esc 暂停", hint: "在任何窗口快速按两下 Esc，自动回复马上停下",
                           isOn: Binding(get: { ctl.options.escToStop },
                                         set: { ctl.options.escToStop = $0; ctl.escSettingChanged() }))
            }
        }
    }

    // MARK: 只回这些人

    private var onlyList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if ctl.options.onlyList.isEmpty {
                Text("名单是空的：现在谁都不回。名字写成\(ctl.target.name)里显示的样子。")
                    .font(.system(size: 12)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ctl.options.onlyList, id: \.self) { n in
                HStack {
                    Text(n).font(.system(size: 14))
                    Spacer()
                    Button { ctl.setOnlyList(n, false) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.sub).help("移出名单")
                }
                .padding(.vertical, 2)
            }
            HStack {
                TextField("输入名字，比如：客户·王女士", text: $name).textFieldStyle(.roundedBorder).onSubmit(addName)
                Button("添加", action: addName).disabled(!nameLongEnough)
            }
            if !name.trimmingCharacters(in: .whitespaces).isEmpty, !nameLongEnough {
                Text("名字至少两个字").font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
        }
    }

    private var nameLongEnough: Bool { TextMatch.normalize(name).count >= 2 }

    private func addName() {
        guard nameLongEnough else { return }
        ctl.setOnlyList(name, true)
        name = ""
    }

    // MARK: 群里只回 @我

    private var groupHint: String {
        ctl.replyToGroups ? "别人在群里 @你，才回那一条；其他群消息不回"
            : "只在“回复群聊”打开时有用（现在关着，群聊本来就不回）"
    }

    private var myName: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingLine(title: "我在群里的名字", hint: "用来认出“@我”，写成群里显示的样子") {
                TextField("比如：店小二", text: $ctl.options.myGroupName).textFieldStyle(.roundedBorder).frame(width: 150)
            }
            if ctl.replyToGroups, TextMatch.normalize(ctl.options.myGroupName).isEmpty {
                Text("还没填名字：群消息一条都不回").font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
        }
    }
}
