import CoreGraphics
import Foundation
import Testing
@testable import QingzhouCore

private func photo(_ name: String) -> ProductPhotos.Photo {
    ProductPhotos.Photo(product: ProductPhotos.product(fileName: name), file: URL(fileURLWithPath: "/p/\(name)"))
}

private let photos = ["芒果.jpg", "春见 2.jpg", "砂糖橘.png", "特级砂糖橘.png"].map(photo)

@Test("A photo's product is its file name without the number", arguments: [
    ("芒果.jpg", "芒果"), ("春见 2.jpg", "春见"), ("春见-1.png", "春见"), ("春见(3).heic", "春见"), ("智利车厘子_2.jpg", "智利车厘子"),
])
func productFromFileName(file: String, product: String) {
    #expect(ProductPhotos.product(fileName: file) == product)
}

@Test("Asking to see something", arguments: [
    ("芒果有图吗", true), ("发张照片", true), ("芒果多大", true), ("长什么样", true), ("看看", true),
    ("我再看看", false), ("芒果多少钱", false), ("[图片1：见附图1]", false), ("我想想再看看", false),
])
func asksToSee(text: String, expected: Bool) {
    #expect(ProductPhotos.asksToSee(text) == expected)
}

@Test("The photo of the product they ask to see; the longest name wins")
func picksNamedProduct() {
    #expect(ProductPhotos.pick(pending: ["芒果多大"], photos: photos)?.product == "芒果")
    #expect(ProductPhotos.pick(pending: ["特级砂糖橘有图吗"], photos: photos)?.product == "特级砂糖橘")
    #expect(ProductPhotos.pick(pending: ["春见", "发张图看看"], photos: photos)?.file.lastPathComponent == "春见 2.jpg")
}

@Test("“发张图看看” means the product talked about just before")
func picksFromEarlierTalk() {
    let earlier = ["今天有什么水果", "今天有芒果荔枝", "芒果怎么卖", "60一斤"]
    #expect(ProductPhotos.pick(pending: ["发张图看看"], earlier: earlier, photos: photos)?.product == "芒果")
    #expect(ProductPhotos.pick(pending: ["发张图看看"], earlier: ["你好"], photos: photos) == nil)
}

@Test("No photo when they did not ask, there is none of it, or it is sold out")
func picksNothing() {
    #expect(ProductPhotos.pick(pending: ["芒果多少钱"], photos: photos) == nil)
    #expect(ProductPhotos.pick(pending: ["荔枝有图吗"], photos: photos) == nil)
    #expect(ProductPhotos.pick(pending: ["芒果有图吗"], photos: photos, soldOut: ["芒果"]) == nil)
    #expect(ProductPhotos.pick(pending: ["我再看看"], earlier: ["芒果怎么卖"], photos: photos) == nil)
}

@Test("Only pictures in the folder count, by file name")
func listsFolder() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("photos-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in ["芒果.jpg", "春见 2.png", "说明.txt", "1.jpg"] { try Data([1]).write(to: dir.appendingPathComponent(name)) }
    #expect(ProductPhotos.list(folder: dir).map(\.product) == ["春见", "芒果"])
    #expect(ProductPhotos.list(folder: dir.appendingPathComponent("没有")).isEmpty)
}

private let wechat = ChatTarget.weChat.layout
private let size = CGSize(width: 1000, height: 700)

@Test("A window that reads fine has no problems")
func screenReadsFine() {
    let ok = ScreenCheck.Facts(lines: 40, listNames: 9, title: "王女士", bubbles: 6, windowSize: size)
    #expect(ScreenCheck.problems(ok, layout: wechat).isEmpty)
    // No chat open yet: nothing to read on the right, and that is fine.
    let none = ScreenCheck.Facts(lines: 12, listNames: 9, title: "", bubbles: 0, windowSize: size)
    #expect(ScreenCheck.problems(none, layout: wechat).isEmpty)
}

@Test("A moved layout is noticed")
func screenReadsWrong() {
    let noList = ScreenCheck.Facts(lines: 40, listNames: 0, title: "王女士", bubbles: 6, windowSize: size)
    #expect(ScreenCheck.problems(noList, layout: wechat) == ["左边的聊天列表没读到"])
    let noTitle = ScreenCheck.Facts(lines: 40, listNames: 9, title: " ", bubbles: 6, windowSize: size)
    #expect(ScreenCheck.problems(noTitle, layout: wechat) == ["读到了聊天内容，但没读到是谁的聊天"])
    let blank = ScreenCheck.Facts(lines: 0, listNames: 0, title: "", bubbles: 0, windowSize: size)
    #expect(ScreenCheck.problems(blank, layout: wechat) == ["窗口里一个字都没读到"])
    let small = ScreenCheck.Facts(lines: 40, listNames: 9, title: "王女士", bubbles: 6, windowSize: CGSize(width: 500, height: 700))
    #expect(ScreenCheck.problems(small, layout: wechat).first?.contains("窗口太小") == true)
}

@Test("An update is told once the version changes, not the first time")
func appUpdate() {
    #expect(ScreenCheck.update(lastChecked: "4.1.15", now: "4.2.0") == "4.1.15 → 4.2.0")
    #expect(ScreenCheck.update(lastChecked: "4.1.15", now: "4.1.15") == nil)
    #expect(ScreenCheck.update(lastChecked: nil, now: "4.1.15") == nil)
    #expect(ScreenCheck.update(lastChecked: "4.1.15", now: nil) == nil)
}
