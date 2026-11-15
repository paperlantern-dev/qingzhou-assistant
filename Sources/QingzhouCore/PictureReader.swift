import CoreGraphics
import Foundation
import Vision

/// What this Mac sees in a customer's picture, before anything goes to a cloud model.
public struct PictureInfo: Equatable {
    /// Words in the picture (private details already hidden).
    public let text: String
    /// What it may show, in English (e.g. "fruit", "apple"), most likely first.
    public let labels: [String]
    /// The picture has an address, phone number or ID in it: it must not be sent to the cloud.
    public let hasPrivateText: Bool
    /// This Mac could not read the picture, so it cannot tell whether it is private: it stays here.
    public let readFailed: Bool

    public init(text: String, labels: [String], hasPrivateText: Bool, readFailed: Bool = false) {
        self.text = text
        self.labels = labels
        self.hasPrivateText = hasPrivateText
        self.readFailed = readFailed
    }

    public var mayGoToCloud: Bool { !hasPrivateText && !readFailed }

    /// How the picture appears in the conversation given to the model, e.g.
    /// “[图片1：见附图1；本机看到：fruit、apple；图里的字：红富士 2斤]”.
    public func note(number: Int, attached: Bool) -> String {
        var parts: [String] = []
        if attached { parts.append("见附图\(number)") }
        if !labels.isEmpty { parts.append("本机看到：" + labels.joined(separator: "、")) }
        if !text.isEmpty { parts.append("图里的字：" + text.prefix(120)) }
        if hasPrivateText { parts.append("图里有地址或电话，已隐藏，没有发给你看") }
        if readFailed { parts.append("这张图本机没读清，没有发给你看") }
        return parts.isEmpty ? "[图片\(number)]" : "[图片\(number)：" + parts.joined(separator: "；") + "]"
    }
}

/// Reads a picture on this Mac: its words (Vision OCR) and what it may show (Vision classification).
public enum PictureReader {
    public static func read(_ image: CGImage) -> PictureInfo {
        guard let lines = (try? OCRService.recognize(image))?.lines else {
            return PictureInfo(text: "", labels: labels(of: image), hasPrivateText: false, readFailed: true)
        }
        let hidden = Privacy.redact(lines.map(\.text).joined(separator: " "))
        return PictureInfo(text: hidden.text, labels: labels(of: image), hasPrivateText: hidden.changed)
    }

    /// Up to three likely contents, e.g. ["fruit", "apple"].
    static func labels(of image: CGImage) -> [String] {
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).filter { $0.confidence > 0.3 }.prefix(3).map(\.identifier)
    }
}
