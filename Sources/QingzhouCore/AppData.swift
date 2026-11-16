import Foundation

/// Where the app keeps the owner's own data (customer records, pictures, backups):
/// ~/Library/Application Support/轻舟助手, never inside the project folder.
public enum AppData {
    public static let root: URL = root(
        arguments: CommandLine.arguments,
        support: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        temp: FileManager.default.temporaryDirectory)

    /// A test run (`--autotest`) gets an empty folder of its own, or the one named with `--data-dir`,
    /// so it never reads or changes the owner's real records.
    static func root(arguments: [String], support: URL, temp: URL) -> URL {
        if let i = arguments.firstIndex(of: "--data-dir"), i + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
        }
        if arguments.contains("--autotest") {
            return temp.appendingPathComponent("qingzhou-test-data-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        return support.appendingPathComponent("轻舟助手", isDirectory: true)
    }
}
