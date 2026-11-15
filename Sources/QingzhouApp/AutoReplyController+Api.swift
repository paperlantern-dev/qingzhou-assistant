import Foundation
import QingzhouCore

/// Models reached directly through an API (DeepSeek, 通义千问, OpenAI or one the user adds).
extension AutoReplyController {
    /// Tests can use a key without saving it (`--api-key`).
    static var testApiKey: String?

    /// The API in use: the chosen one, else the first that has a key, else the first.
    var activeApi: ApiConfig? {
        let list = options.apiConfigs
        return list.first { $0.id == options.apiActive } ?? list.first { !apiKey(for: $0).isEmpty } ?? list.first
    }

    func apiKey(for config: ApiConfig) -> String {
        Self.testApiKey ?? Keychain.read("api-\(config.id.uuidString)") ?? ""
    }

    /// Saves (or with "" removes) the key of one API in the Keychain.
    func setApiKey(_ key: String, for config: ApiConfig) {
        guard Self.saveSettings else { return }
        if !Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: "api-\(config.id.uuidString)") {
            add(.error, "\(config.name) 的密钥没能存进钥匙串")
        }
        objectWillChange.send()
    }

    func apiEngine() -> ReplyEngine {
        guard let config = activeApi else { return OpenAICompatibleEngine(config: ApiConfig.presets[0], apiKey: "") }
        return OpenAICompatibleEngine(config: config, apiKey: apiKey(for: config))
    }

    func removeApi(_ config: ApiConfig) {
        setApiKey("", for: config)
        options.apiConfigs.removeAll { $0.id == config.id }
        if options.apiActive == config.id { options.apiActive = nil }
    }

    /// Sends one short question, to check the address, model and key. Returns what happened.
    func testApi(_ config: ApiConfig) async -> String {
        let engine = OpenAICompatibleEngine(config: config, apiKey: apiKey(for: config))
        do {
            let r = try await engine.reply(to: "请只回复两个字：你好")
            return "能用 · \(String(format: "%.1f", Double(r.durationMs) / 1000)) 秒 · 回复：\(r.text.prefix(20))"
        } catch {
            return "不能用：\(error.localizedDescription)"
        }
    }
}
