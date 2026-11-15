import Foundation
import QingzhouCore

/// 手机提醒: when something is left for the user, post it to their WeCom/Feishu group robot.
extension AutoReplyController {
    private static var lastAlert: [String: Date] = [:]

    var alertKind: AlertWebhook.Kind? { AlertWebhook.kind(of: alertAddress) }

    /// Called when a message is put on “需要你处理”, or a draft waits. At most one alert per chat
    /// every 10 minutes.
    func alertIfWanted(chat: String, who: String, message: String, reason: String) {
        guard options.alertsOn, alertKind != nil else { return }
        if let last = Self.lastAlert.first(where: { ChatID.same($0.key, chat) })?.value,
           Date().timeIntervalSince(last) < 600 { return }
        Self.lastAlert[chat] = Date()
        let text = AlertWebhook.message(who: who, text: message, reason: reason)
        Task {
            if let problem = await sendAlert(text) {
                add(.warn, "手机提醒没发出去：\(problem)")
            } else {
                add(.info, "已发手机提醒：「\(who)」\(reason)")
            }
        }
    }

    /// Sends one message to the robot. nil = it arrived, else what went wrong.
    func sendAlert(_ text: String) async -> String? {
        guard let request = AlertWebhook.request(to: alertAddress, text: text) else {
            return "地址不是企业微信群机器人或飞书机器人的 Webhook"
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return "机器人返回 HTTP \(http.statusCode)" }
            return AlertWebhook.problem(in: data)
        } catch {
            return error.localizedDescription
        }
    }
}
