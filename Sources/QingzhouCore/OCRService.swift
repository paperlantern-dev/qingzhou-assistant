import CoreGraphics
import Foundation
import Vision

public struct OCRLine {
    public let text: String
    public let confidence: Float
    /// Normalized bounding box (Vision coordinates, origin bottom-left).
    public let box: CGRect
}

public struct OCRResult {
    public let lines: [OCRLine]
    public let durationMs: Int
    public var text: String { lines.map(\.text).joined(separator: "\n") }
}

public enum OCRService {
    /// Runs Apple Vision text recognition fully on this Mac.
    public static func recognize(_ image: CGImage) throws -> OCRResult {
        let start = Date()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let observations = request.results ?? []
        // Top-to-bottom, then left-to-right reading order.
        let sorted = observations.sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        let lines = sorted.compactMap { obs -> OCRLine? in
            guard let best = obs.topCandidates(1).first else { return nil }
            return OCRLine(text: best.string, confidence: best.confidence, box: obs.boundingBox)
        }
        return OCRResult(lines: lines, durationMs: Int(Date().timeIntervalSince(start) * 1000))
    }
}
