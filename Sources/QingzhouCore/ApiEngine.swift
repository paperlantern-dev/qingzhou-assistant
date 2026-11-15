import Foundation

/// A model reached directly through an OpenAI-compatible API (DeepSeek, 通义千问, OpenAI, …).
/// The key itself is not part of it: it lives in the macOS Keychain.
public struct ApiConfig: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    /// e.g. https://api.deepseek.com/v1 (“/chat/completions” is added)
    public var baseURL: String
    public var model: String
    /// A model that can look at pictures (empty or nil: pictures are left out).
    public var visionModel: String?

    public init(name: String, baseURL: String, model: String, visionModel: String? = nil) {
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.visionModel = visionModel
    }

    /// The fastest current model of each (checked in their docs, 2026-11): text and pictures.
    public static let presets: [ApiConfig] = [
        ApiConfig(name: "DeepSeek", baseURL: "https://api.deepseek.com", model: "deepseek-flash", visionModel: "deepseek-flash"),
        ApiConfig(name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen3.8-flash",
                  visionModel: "qwen3.8-omni-flash"),
        ApiConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-6.1-terra", visionModel: "gpt-6.1-terra"),
    ]

    /// The newest models of each platform to switch between (2026-11), fastest first.
    /// Matched by the address, so a renamed config still gets them. Only the text model changes.
    public var modelChoices: [ModelChoice] {
        let host = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host ?? ""
        if host.hasSuffix("openai.com") {
            return [ModelChoice(id: "gpt-6.1-terra", note: "快，推荐"),
                    ModelChoice(id: "gpt-6-luna", note: "最便宜"),
                    ModelChoice(id: "gpt-6.1-sol", note: "更聪明，慢一些")]
        }
        if host.hasSuffix("deepseek.com") {
            return [ModelChoice(id: "deepseek-flash", note: "快，推荐"),
                    ModelChoice(id: "deepseek-v4-pro", note: "更聪明，慢一些")]
        }
        if host.hasSuffix("aliyuncs.com") {
            return [ModelChoice(id: "qwen3.8-flash", note: "快，推荐"),
                    ModelChoice(id: "qwen3.8-max", note: "更聪明，慢一些")]
        }
        return []
    }

    /// Models this app suggested before; a saved preset still on one of them moves to today's.
    private static let oldDefaults: Set<String> = ["deepseek-chat", "qwen-plus", "gpt-4o-mini"]

    /// A saved config, moved to the newest preset model when it still has the old suggested one.
    public static func upgraded(_ config: ApiConfig) -> ApiConfig {
        guard oldDefaults.contains(config.model), let preset = presets.first(where: { $0.name == config.name }) else {
            return config
        }
        var c = config
        c.baseURL = preset.baseURL
        c.model = preset.model
        c.visionModel = preset.visionModel
        return c
    }

    /// What is wrong with it, or nil. Only https (or this Mac, for testing), and a model is needed.
    public var problem: String? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)), let host = url.host else {
            return "接口地址不对"
        }
        let local = host == "127.0.0.1" || host == "localhost"
        guard url.scheme == "https" || (url.scheme == "http" && local) else { return "接口地址要用 https://" }
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { return "要填模型名" }
        return nil
    }

    var canSeePictures: Bool { !(visionModel ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
}

/// One model to pick from, with a few words on what it is good for.
public struct ModelChoice: Equatable, Hashable {
    public let id: String
    public let note: String
}

/// Replies through an OpenAI-compatible chat API. Private details are hidden before sending.
public struct OpenAICompatibleEngine: ReplyEngine {
    public let config: ApiConfig
    private let apiKey: String
    private let session: URLSession

    public init(config: ApiConfig, apiKey: String, session: URLSession = .shared) {
        self.config = config
        self.apiKey = apiKey
        self.session = session
    }

    public var label: String { "\(config.name) API（云端，地址电话已屏蔽）" }
    public var runsOnDevice: Bool { false }

    public func reply(to prompt: String) async throws -> ReplyResult {
        try await reply(to: prompt, images: [])
    }

    public func reply(to prompt: String, images: [URL]) async throws -> ReplyResult {
        guard !apiKey.isEmpty else { throw ReplyError.notAvailable("还没填 \(config.name) 的 API 密钥") }
        let start = Date()
        var reasoning = "none"
        var (data, status) = try await send(Self.request(config: config, apiKey: apiKey, prompt: prompt, images: images))
        for _ in 0..<Self.retries {
            if Self.needsSomeReasoning(data: data, status: status) {
                // Some models (gpt-6.1-sol and the like) can't switch thinking off; "low" is their quickest.
                reasoning = "low"
            } else if Self.accessFlickers(data: data, status: status) {
                // Just after a model is enabled, OpenAI's servers disagree for a while: ask again shortly.
                try? await Task.sleep(for: .seconds(1))
            } else {
                break
            }
            (data, status) = try await send(Self.request(config: config, apiKey: apiKey, prompt: prompt, images: images,
                                                          reasoning: reasoning))
        }
        let text = try Self.answer(from: data, status: status)
        return ReplyResult(text: text, engineLabel: label, durationMs: Int(Date().timeIntervalSince(start) * 1000))
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw ReplyError.failed("连不上 \(config.name)：\(error.localizedDescription)")
        }
    }

    /// How many times a call is sent again (to think a little, or after a "no access" flicker).
    static let retries = 3

    /// "Project does not have access to model": right after enabling a model this comes and goes.
    static func accessFlickers(data: Data, status: Int) -> Bool {
        guard status == 401 || status == 403 else { return false }
        return (String(data: data, encoding: .utf8) ?? "").contains("does not have access to model")
    }

    /// The model refused `reasoning_effort: none` (it always thinks a little).
    static func needsSomeReasoning(data: Data, status: Int) -> Bool {
        guard status == 400 else { return false }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("reasoning_effort") && text.contains("'none'")
    }

    /// The chat request. Pictures go along (as data URLs, with the vision model) only when the
    /// config has one.
    public static func request(config: ApiConfig, apiKey: String, prompt: String, images: [URL],
                               reasoning: String = "none") throws -> URLRequest {
        if let problem = config.problem { throw ReplyError.notAvailable(problem) }
        let base = config.baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/chat/completions") else {
            throw ReplyError.notAvailable("接口地址不对")
        }
        let text = Privacy.forCloud(prompt)
        let pictures = config.canSeePictures ? images.compactMap(dataURL) : []
        let content: Any = pictures.isEmpty
            ? text
            : [["type": "text", "text": text]] + pictures.map { ["type": "image_url", "image_url": ["url": $0]] }
        var body: [String: Any] = [
            "model": pictures.isEmpty ? config.model : (config.visionModel ?? config.model),
            "messages": [["role": "user", "content": content]],
        ]
        // The newest models think before answering by default; short chat replies don't need it.
        // Decided by the model's name, so it also works through a relay (CometAPI and the like).
        let model = (body["model"] as? String ?? "").lowercased()
        if model.hasPrefix("gpt-6") || model.hasPrefix("gpt-5") || model.hasPrefix("o") && model.dropFirst().first?.isNumber == true {
            body["reasoning_effort"] = reasoning   // reasoning models take no temperature
        } else if model.hasPrefix("deepseek") {
            body["thinking"] = ["type": "disabled"]
            body["temperature"] = 0.3
        } else {
            body["temperature"] = 0.3
        }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])
        return request
    }

    /// The model's words, or a plain-language error.
    public static func answer(from data: Data, status: Int) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
        switch status {
        case 200:
            let choices = json?["choices"] as? [[String: Any]]
            let text = ((choices?.first?["message"] as? [String: Any])?["content"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { throw ReplyError.failed("模型没有返回内容") }
            return text
        case 401, 403:
            if message.contains("does not have access to model") {
                throw ReplyError.notAvailable("密钥没问题，但这个账号/项目还没开通这个模型：去平台后台充值、开通模型权限或完成组织验证（\(message)）")
            }
            throw ReplyError.notAvailable("API 密钥不对或没有权限：密钥要和接口地址是同一家平台发的（\(message)）")
        case 402: throw ReplyError.failed("API 账户余额不足（\(message)）")
        case 429: throw ReplyError.failed("调用太频繁或额度用完了（\(message)）")
        default: throw ReplyError.failed("接口返回 \(status)：\(message.prefix(200))")
        }
    }

    private static func dataURL(_ file: URL) -> String? {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        let type = file.pathExtension.lowercased() == "jpg" || file.pathExtension.lowercased() == "jpeg" ? "jpeg" : "png"
        return "data:image/\(type);base64,\(data.base64EncodedString())"
    }
}
