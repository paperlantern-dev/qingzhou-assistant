import Foundation
import QingzhouCore

/// Settings added after the first version (不回名单, 辅助模式, 手机提醒, 主动智能), saved as one value.
struct AssistantOptions: Codable, Equatable {
    /// People never replied to automatically (family, friends, suppliers).
    var neverReply: [String] = []
    /// 卖完了的: names on the price table the owner marked as sold out (until he says they are back).
    var soldOut: [String] = []
    /// 辅助模式: replies wait on 首页 as drafts; nothing is sent until the user clicks 发送.
    var assistMode = false
    /// Tell the user's phone through a WeCom/Feishu group robot when something is left for them.
    var alertsOn = false
    /// 主动智能: greet customers who went quiet. Off unless the user turns it on.
    var revisitOn = false
    var revisitMinDays = 7
    var revisitMaxDays = 30
    var revisitPerDay = 3
    /// 店铺人设和话术, written by the owner (or learned from their chats); goes into every reply prompt.
    var persona = ""
    /// 关键词触发 rules: the shop presets from the start.
    var triggers: [TriggerRule] = TriggerRule.presets
    /// 白名单: when on, only these people get automatic replies.
    var onlyListOn = false
    var onlyList: [String] = []
    /// In group chats (when 回复群聊 is on), only answer messages that @ me.
    var groupAtOnly = true
    /// My name in groups, to recognise “@我”.
    var myGroupName = ""
    /// Press Esc twice quickly to stop auto-reply.
    var escToStop = true
    /// 看图: customers' pictures are shown to the reply model (never ones with an address or phone in them).
    var picturesToModel = true
    /// Models reached through an API (keys are in the Keychain), and the one in use.
    var apiConfigs: [ApiConfig] = ApiConfig.presets
    var apiActive: UUID?
    /// 定时群发: off unless the user turns it on.
    var broadcastOn = false
    var broadcasts: [Broadcast] = []
    /// The preset 关键词触发 rules were put in (once).
    var presetsAdded = true

    init() {}

    /// Settings saved by an older version keep defaults for what they don't have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AssistantOptions()
        neverReply = try c.decodeIfPresent([String].self, forKey: .neverReply) ?? d.neverReply
        soldOut = try c.decodeIfPresent([String].self, forKey: .soldOut) ?? d.soldOut
        assistMode = try c.decodeIfPresent(Bool.self, forKey: .assistMode) ?? d.assistMode
        alertsOn = try c.decodeIfPresent(Bool.self, forKey: .alertsOn) ?? d.alertsOn
        revisitOn = try c.decodeIfPresent(Bool.self, forKey: .revisitOn) ?? d.revisitOn
        revisitMinDays = try c.decodeIfPresent(Int.self, forKey: .revisitMinDays) ?? d.revisitMinDays
        revisitMaxDays = try c.decodeIfPresent(Int.self, forKey: .revisitMaxDays) ?? d.revisitMaxDays
        revisitPerDay = try c.decodeIfPresent(Int.self, forKey: .revisitPerDay) ?? d.revisitPerDay
        persona = try c.decodeIfPresent(String.self, forKey: .persona) ?? d.persona
        triggers = try c.decodeIfPresent([TriggerRule].self, forKey: .triggers) ?? d.triggers
        // Settings from before the presets get them once; ones the owner deleted later stay deleted.
        if try c.decodeIfPresent(Bool.self, forKey: .presetsAdded) != true {
            triggers = TriggerRule.missingPresets(in: triggers) + triggers
        }
        onlyListOn = try c.decodeIfPresent(Bool.self, forKey: .onlyListOn) ?? d.onlyListOn
        onlyList = try c.decodeIfPresent([String].self, forKey: .onlyList) ?? d.onlyList
        groupAtOnly = try c.decodeIfPresent(Bool.self, forKey: .groupAtOnly) ?? d.groupAtOnly
        myGroupName = try c.decodeIfPresent(String.self, forKey: .myGroupName) ?? d.myGroupName
        escToStop = try c.decodeIfPresent(Bool.self, forKey: .escToStop) ?? d.escToStop
        broadcastOn = try c.decodeIfPresent(Bool.self, forKey: .broadcastOn) ?? d.broadcastOn
        picturesToModel = try c.decodeIfPresent(Bool.self, forKey: .picturesToModel) ?? d.picturesToModel
        apiConfigs = (try c.decodeIfPresent([ApiConfig].self, forKey: .apiConfigs) ?? d.apiConfigs).map(ApiConfig.upgraded)
        apiActive = try c.decodeIfPresent(UUID.self, forKey: .apiActive)
        broadcasts = try c.decodeIfPresent([Broadcast].self, forKey: .broadcasts) ?? d.broadcasts
    }

    private static let key = "assistantOptions"

    static func load() -> AssistantOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(AssistantOptions.self, from: data) else { return AssistantOptions() }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
