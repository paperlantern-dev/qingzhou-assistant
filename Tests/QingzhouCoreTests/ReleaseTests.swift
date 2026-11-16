import Foundation
import Testing
@testable import QingzhouCore

// What goes into the download: only reviewed sample knowledge, checked for private details.

private let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

private func folder(_ files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qz-release-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, text) in files { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    return dir
}

/// Runs scripts/stage_samples.sh. Returns its exit code and the names of the files it packaged.
private func stage(samples: [String: String], reviewed: [String]) throws -> (code: Int32, packaged: [String]) {
    let src = try folder(samples), dest = try folder([:])
    let list = try folder(["reviewed.txt": reviewed.joined(separator: "\n") + "\n"]).appendingPathComponent("reviewed.txt")
    let run = Process()
    run.executableURL = URL(fileURLWithPath: "/bin/bash")
    run.arguments = [projectRoot.appendingPathComponent("scripts/stage_samples.sh").path, src.path, list.path, dest.path]
    run.standardOutput = Pipe()
    run.standardError = Pipe()
    try run.run()
    run.waitUntilExit()
    return (run.terminationStatus, try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted())
}

@Test("Packaging takes only the reviewed samples: a real price list beside them is left out")
func packagingLeavesOutUnreviewedFiles() throws {
    let r = try stage(samples: ["示例-价格表.csv": "品名,价格\n苹果,5", "我家真实价格表.csv": "品名,进价\n苹果,2",
                                "客户名单.md": "王小明 13900000001"],
                      reviewed: ["示例-价格表.csv"])
    #expect(r.code == 0)
    #expect(r.packaged == ["示例-价格表.csv"])
}

@Test("Packaging stops when a reviewed sample has private details in it", arguments: [
    "客服电话 13900000001", "加微信：apple_shop2024", "发票寄 shop@example.com", "国外打 +44 20 7946 0958",
    "收货人：王小明", "详细地址：示例路88号", "店在示例市示例路88号", "sk-abcdefghijklmnopqrstuvwx", "见 /Users/someone/价格.csv",
])
func packagingStopsOnPrivateSamples(line: String) throws {
    let r = try stage(samples: ["示例-店铺介绍.md": "# 店铺介绍\n\(line)\n"], reviewed: ["示例-店铺介绍.md"])
    #expect(r.code != 0, "packaged a sample containing: \(line)")
}

@Test("Packaging stops when a reviewed sample is missing")
func packagingStopsOnMissingSample() throws {
    #expect(try stage(samples: [:], reviewed: ["示例-价格表.csv"]).code != 0)
}

@Test("The project's sample folder holds exactly the reviewed samples, and nothing private")
func projectSamplesAreReviewedAndClean() throws {
    let listed = try String(contentsOf: projectRoot.appendingPathComponent("scripts/reviewed-samples.txt"), encoding: .utf8)
        .components(separatedBy: "\n").filter { !$0.isEmpty }.sorted()
    let dir = projectRoot.appendingPathComponent("knowledge-samples")
    let present = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix(".") }
        .map { $0.precomposedStringWithCanonicalMapping }.sorted()
    #expect(present == listed.map { $0.precomposedStringWithCanonicalMapping })
    for name in listed {
        let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
        #expect(!Privacy.redact(text).changed, "\(name) has something the privacy rules would hide")
    }
    #expect(try stage(samples: Dictionary(uniqueKeysWithValues: listed.map {
        ($0, try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8))
    }), reviewed: listed).code == 0)
}

@Test("The owner's own data folders are ignored by git")
func ownDataIsIgnoredByGit() throws {
    let ignore = try String(contentsOf: projectRoot.appendingPathComponent(".gitignore"), encoding: .utf8)
    for line in ["/knowledge/", "客户记忆/", "备份/", "dist/", ".env*"] {
        #expect(ignore.components(separatedBy: "\n").contains(line), "\(line) is not in .gitignore")
    }
}
