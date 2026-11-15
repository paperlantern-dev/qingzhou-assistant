import Foundation
import Testing
@testable import QingzhouCore

@Test("One backup a day: folders and settings are copied, a second run the same day does nothing")
func backupOncePerDay() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    let memory = base.appendingPathComponent("客户记忆/店主反馈")
    try fm.createDirectory(at: memory, withIntermediateDirectories: true)
    try "a".write(to: memory.appendingPathComponent("x.json"), atomically: true, encoding: .utf8)
    let root = base.appendingPathComponent("备份")
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let sources = [DataBackup.Source(name: "客户记忆", folder: base.appendingPathComponent("客户记忆")),
                   DataBackup.Source(name: "知识库", folder: base.appendingPathComponent("没有这个文件夹"))]

    let made = try #require(try DataBackup.run(sources: sources, settings: Data("{}".utf8), into: root, now: day))
    #expect(fm.fileExists(atPath: made.appendingPathComponent("客户记忆/店主反馈/x.json").path))
    #expect(fm.fileExists(atPath: made.appendingPathComponent("设置.json").path))
    #expect(!fm.fileExists(atPath: made.appendingPathComponent("知识库").path))
    #expect(try DataBackup.run(sources: sources, settings: nil, into: root, now: day + 3600) == nil)
}

@Test("Only the newest backups are kept; other things in the folder are left alone")
func backupKeepsNewest() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    try fm.createDirectory(at: root.appendingPathComponent("我自己放的"), withIntermediateDirectories: true)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    for i in 0..<5 { _ = try DataBackup.run(sources: [], settings: Data("{}".utf8), into: root, now: start + Double(i) * 86_400, keep: 3) }
    let left = try fm.contentsOfDirectory(atPath: root.path).sorted()
    #expect(left.count == 4 && left.contains("我自己放的"))
    #expect(left.first == DataBackup.dayName(start + 2 * 86_400))
}
