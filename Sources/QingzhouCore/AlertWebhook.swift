import Foundation

/// Phone alerts through a group robot: a WeCom (企业微信) or Feishu (飞书) webhook. Only these
/// hosts are allowed, over https, so customer messages can't be sent anywhere else.
public enum AlertWebhook {
    public enum Kind: Equatable {
        case weCom, feishu
        public var name: String { self == .weCom ? "企业微信群机器人" : "飞书机器人" }
    }

    public static func kind(of address: String) -> Kind? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        switch host {
        case "qyapi.weixin.qq.com":
            return url.path.hasPrefix("/cgi-bin/webhook/send") ? .weCom : nil
        case "open.feishu.cn", "open.larksuite.com":
            return url.path.hasPrefix("/open-apis/bot/v2/hook/") ? .feishu : nil
        default:
            return nil
        }
    }

    /// The POST request carrying `text`, or nil when the address is not an allowed robot webhook.
    public static func request(to address: String, text: String) -> URLRequest? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = kind(of: trimmed), let url = URL(string: trimmed) else { return nil }
        let body: [String: Any] = kind == .weCom
            ? ["msgtype": "text", "text": ["content": text]]
            : ["msg_type": "text", "content": ["text": text]]
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// “【轻舟助手】…”: who wrote, what, and why it was left to the user.
    public static func message(who: String, text: String, reason: String) -> String {
        "【轻舟助手】需要你处理\n客户：\(who.prefix(30))\n消息：\(Privacy.redact(String(text.prefix(200))).text)\n原因：\(reason.prefix(40))"
    }

    /// nil when the robot accepted the message (WeCom: errcode 0; Feishu: code 0 or StatusCode 0),
    /// else what it said went wrong.
    public static func problem(in answer: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any] else {
            return "机器人没有正常回应"
        }
        for key in ["errcode", "code", "StatusCode"] {
            if let code = json[key] as? Int {
                if code == 0 { return nil }
                return (json["errmsg"] ?? json["msg"] ?? json["StatusMessage"]) as? String ?? "错误码 \(code)"
            }
        }
        return "机器人没有正常回应"
    }
}
