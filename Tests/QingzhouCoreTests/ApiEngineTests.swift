import Foundation
import Testing
@testable import QingzhouCore

@Test("Ready-made APIs: DeepSeek, 通义千问, OpenAI, all https")
func apiPresets() {
    let names = ApiConfig.presets.map(\.name)
    #expect(names.contains("DeepSeek") && names.contains("通义千问") && names.contains("OpenAI"))
    #expect(ApiConfig.presets.allSatisfy { $0.problem == nil })
    #expect(ApiConfig.presets.first { $0.name == "通义千问" }?.visionModel?.isEmpty == false)
}

@Test("An API address must be https (or this Mac, for tests), and a model is needed")
func apiConfigChecks() {
    #expect(ApiConfig(name: "x", baseURL: "http://example.com/v1", model: "m").problem != nil)
    #expect(ApiConfig(name: "x", baseURL: "https://example.com/v1", model: "").problem != nil)
    #expect(ApiConfig(name: "x", baseURL: "https://example.com/v1", model: "m").problem == nil)
    #expect(ApiConfig(name: "x", baseURL: "http://127.0.0.1:8765/v1", model: "m").problem == nil)
}

@Test("The request carries the key, the model and the prompt with private details hidden")
func apiRequest() throws {
    let config = ApiConfig(name: "x", baseURL: "https://example.com/v1/", model: "chat-1")
    let request = try OpenAICompatibleEngine.request(config: config, apiKey: "sk-test", prompt: "对方：我电话13900000001",
                                                     images: [])
    #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    let body = try #require(request.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["model"] as? String == "chat-1")
    let text = String(data: body, encoding: .utf8) ?? ""
    #expect(!text.contains("13900000001") && text.contains("电话"))
}

@Test("Pictures go along as data URLs, using the vision model; without one they are left out")
func apiRequestWithPictures() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let pic = dir.appendingPathComponent("p.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pic)
    let vision = ApiConfig(name: "x", baseURL: "https://e.com/v1", model: "text-1", visionModel: "vl-1")
    let withPic = String(data: try #require(try OpenAICompatibleEngine.request(config: vision, apiKey: "k", prompt: "看图",
                                                                               images: [pic]).httpBody), encoding: .utf8) ?? ""
    #expect(withPic.contains("vl-1") && withPic.contains("data:image/png;base64,"))
    let plain = ApiConfig(name: "x", baseURL: "https://e.com/v1", model: "text-1")
    let noPic = String(data: try #require(try OpenAICompatibleEngine.request(config: plain, apiKey: "k", prompt: "看图",
                                                                             images: [pic]).httpBody), encoding: .utf8) ?? ""
    #expect(!noPic.contains("base64") && noPic.contains("text-1"))
}

@Test("Answers and errors are read from the reply")
func apiAnswers() throws {
    let ok = Data(#"{"choices":[{"message":{"role":"assistant","content":"你好呀"}}]}"#.utf8)
    #expect(try OpenAICompatibleEngine.answer(from: ok, status: 200) == "你好呀")
    #expect(throws: ReplyError.self) { try OpenAICompatibleEngine.answer(from: Data(#"{"error":{"message":"bad key"}}"#.utf8), status: 401) }
    do {
        _ = try OpenAICompatibleEngine.answer(from: Data(#"{"error":{"message":"bad key"}}"#.utf8), status: 401)
    } catch {
        #expect(error.localizedDescription.contains("密钥"))
    }
}

@Test("Presets use the newest fast models: GPT-6.1 Terra, DeepSeek Flash, Qwen 3.8 Flash")
func apiPresetsAreNewest() {
    let byName = Dictionary(uniqueKeysWithValues: ApiConfig.presets.map { ($0.name, $0) })
    #expect(byName["OpenAI"]?.model == "gpt-6.1-terra")
    #expect(byName["DeepSeek"]?.model == "deepseek-flash" && byName["DeepSeek"]?.visionModel == "deepseek-flash")
    #expect(byName["通义千问"]?.model == "qwen3.8-flash" && byName["通义千问"]?.visionModel == "qwen3.8-omni-flash")
}

@Test("Thinking is switched off for speed: OpenAI reasoning none (no temperature), DeepSeek thinking disabled")
func apiFastSwitches() throws {
    func body(_ c: ApiConfig) throws -> [String: Any] {
        let r = try OpenAICompatibleEngine.request(config: c, apiKey: "k", prompt: "你好", images: [])
        let data = try #require(r.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    let presets = Dictionary(uniqueKeysWithValues: ApiConfig.presets.map { ($0.name, $0) })
    let openai = try body(try #require(presets["OpenAI"]))
    #expect(openai["reasoning_effort"] as? String == "none" && openai["temperature"] == nil)
    let deepseek = try body(try #require(presets["DeepSeek"]))
    #expect((deepseek["thinking"] as? [String: Any])?["type"] as? String == "disabled")
    let relay = try body(ApiConfig(name: "x", baseURL: "https://api.cometapi.com/v1", model: "gpt-6.1-terra"))
    #expect(relay["reasoning_effort"] as? String == "none")   // through a relay too
    let custom = try body(ApiConfig(name: "x", baseURL: "https://e.com/v1", model: "m"))
    #expect(custom["reasoning_effort"] == nil && custom["thinking"] == nil)
}

@Test("Each platform offers 2–3 newest models to switch between, the preset's own first")
func apiModelChoices() {
    for preset in ApiConfig.presets {
        let ids = preset.modelChoices.map(\.id)
        #expect((2...3).contains(ids.count) && ids.first == preset.model)
    }
    #expect(ApiConfig.presets.first { $0.name == "OpenAI" }?.modelChoices.map(\.id).contains("gpt-6.1-sol") == true)
    #expect(ApiConfig(name: "x", baseURL: "https://e.com/v1", model: "m").modelChoices.isEmpty)
}

@Test("A model that can't switch thinking off is asked again with low")
func apiReasoningFallback() throws {
    let refused = Data(#"{"error":{"message":"Unsupported value: 'reasoning_effort' does not support 'none' with this model."}}"#.utf8)
    #expect(OpenAICompatibleEngine.needsSomeReasoning(data: refused, status: 400))
    #expect(!OpenAICompatibleEngine.needsSomeReasoning(data: refused, status: 401))
    #expect(!OpenAICompatibleEngine.needsSomeReasoning(data: Data(#"{"error":{"message":"bad"}}"#.utf8), status: 400))
    let config = ApiConfig(name: "x", baseURL: "https://api.openai.com/v1", model: "gpt-6.1-sol")
    let body = try #require(try OpenAICompatibleEngine.request(config: config, apiKey: "k", prompt: "你好", images: [],
                                                               reasoning: "low").httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["reasoning_effort"] as? String == "low")
}

@Test("\"No access to model\" is asked again; a wrong key is not")
func apiAccessRetry() {
    let flicker = Data(#"{"error":{"message":"Project `p` does not have access to model `gpt-6.1-terra`"}}"#.utf8)
    #expect(OpenAICompatibleEngine.accessFlickers(data: flicker, status: 403))
    #expect(!OpenAICompatibleEngine.accessFlickers(data: Data(#"{"error":{"message":"Incorrect API key"}}"#.utf8), status: 401))
    #expect(!OpenAICompatibleEngine.accessFlickers(data: flicker, status: 200))
}

@Test("Saved presets from before move to the new models and keep their id")
func apiOldPresetsUpgrade() {
    let old = ApiConfig(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat")
    let new = ApiConfig.upgraded(old)
    #expect(new.id == old.id && new.model == "deepseek-flash")
    let mine = ApiConfig(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-v4-pro")
    #expect(ApiConfig.upgraded(mine) == mine)   // a model the owner chose stays
}
