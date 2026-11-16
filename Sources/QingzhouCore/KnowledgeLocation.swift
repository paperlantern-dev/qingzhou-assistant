import Foundation

/// Where the owner's own knowledge files live: outside the project folder, so real prices and
/// shop details are never committed or packaged with the app. The project only carries reviewed samples.
public enum KnowledgeLocation {
    /// ~/Documents/轻舟助手知识库 (a test run uses a folder inside its own data folder instead).
    public static func userFolder(home: URL, testData: URL?) -> URL {
        testData?.appendingPathComponent("知识库", isDirectory: true)
            ?? home.appendingPathComponent("Documents/轻舟助手知识库", isDirectory: true)
    }

    /// Makes the owner's folder on first use and returns it. Files in an older in-project `knowledge`
    /// folder are copied over (the originals stay where they are); with none, the samples are copied.
    /// A folder that already exists is never changed.
    @discardableResult
    public static func prepare(userFolder: URL, legacy: URL?, samples: URL?) -> URL {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: userFolder.path) else { return userFolder }
        func files(_ folder: URL?) -> [URL] {
            guard let folder else { return [] }
            return ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                 options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        }
        let own = files(legacy)
        let source = own.isEmpty ? files(samples) : own
        try? fm.createDirectory(at: userFolder, withIntermediateDirectories: true)   // empty = shown as an empty knowledge base
        for file in source {
            try? fm.copyItem(at: file, to: userFolder.appendingPathComponent(file.lastPathComponent))
        }
        return userFolder
    }
}
