import Foundation

/// A copy of the owner's data (customer memory, knowledge files, settings) once a day, in a
/// folder named by the date. Plain copies: to get something back, copy it out of the folder.
public enum DataBackup {
    public struct Source {
        public let name: String
        public let folder: URL
        public init(name: String, folder: URL) {
            self.name = name
            self.folder = folder
        }
    }

    public static func dayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Makes today's backup unless there is one already (then returns nil). Keeps the newest `keep`.
    @discardableResult
    public static func run(sources: [Source], settings: Data?, into root: URL, now: Date = Date(), keep: Int = 14) throws -> URL? {
        let fm = FileManager.default
        let day = root.appendingPathComponent(dayName(now), isDirectory: true)
        guard !fm.fileExists(atPath: day.path) else { return nil }
        // Written under another name first, so a half-made backup never looks like a finished one.
        let partial = root.appendingPathComponent(".正在备份", isDirectory: true)
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        for s in sources where fm.fileExists(atPath: s.folder.path) {
            try fm.copyItem(at: s.folder, to: partial.appendingPathComponent(s.name))
        }
        try settings?.write(to: partial.appendingPathComponent("设置.json"))
        try fm.moveItem(at: partial, to: day)
        prune(root, keep: keep)
        return day
    }

    /// Removes the oldest dated folders beyond `keep`; anything not named like a date stays.
    private static func prune(_ root: URL, keep: Int) {
        let fm = FileManager.default
        let days = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }.sorted()
        for old in days.dropLast(keep) { try? fm.removeItem(at: root.appendingPathComponent(old)) }
    }
}
