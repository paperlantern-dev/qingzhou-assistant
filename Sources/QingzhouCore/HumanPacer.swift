import Foundation

/// Human-like timing: notice and read the message, then "type" the reply.
public struct PacingConfig {
    public let name: String
    public let readDelay: ClosedRange<Double>      // seconds before starting to reply
    public let secondsPerChar: ClosedRange<Double> // typing speed
    public let maxTyping: Double
    public let minGapBetweenSends: Double

    public static let human = PacingConfig(
        name: "像真人（随机 2–5 秒，AI 写回复的时间也算在里面）",
        readDelay: 0.5...2, secondsPerChar: 0.04...0.08, maxTyping: 3, minGapBetweenSends: 2
    )
    public static let fastTest = PacingConfig(
        name: "快速测试（1–2 秒）",
        readDelay: 1...2, secondsPerChar: 0.02...0.05, maxTyping: 2, minGapBetweenSends: 1
    )
}

public struct HumanPacer {
    public let config: PacingConfig
    public init(config: PacingConfig) { self.config = config }

    public func readDelay<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        Double.random(in: config.readDelay, using: &rng)
    }

    /// How long to wait before sending. A person reads, then types; the time the reply took to
    /// write already passed while "reading and typing", so only what is left of it is waited.
    public static func waitBeforeSending(read: Double, typing: Double, elapsed: Double, gapLeft: Double) -> Double {
        max(read + typing - elapsed, gapLeft, 0)
    }

    public func typingDelay<R: RandomNumberGenerator>(for reply: String, using rng: inout R) -> Double {
        let perChar = Double.random(in: config.secondsPerChar, using: &rng)
        return min(config.maxTyping, Double(reply.count) * perChar)
    }
}
