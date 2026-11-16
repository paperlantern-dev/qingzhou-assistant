import Foundation
import QingzhouCore

/// 每天备份: customer memory, knowledge files and settings, copied once a day (see DataBackup).
extension AutoReplyController {
    static var backupFolder: URL {
        AppData.root.appendingPathComponent("备份", isDirectory: true)
    }

    /// Makes today's backup if there is none yet. Not in test runs (they use other folders).
    func backupIfDue() {
        guard Self.saveSettings else { return }
        let sources = [DataBackup.Source(name: "客户记忆", folder: memory.folder),
                       DataBackup.Source(name: "知识库", folder: kbFolder)]
        let settings = UserDefaults.standard.data(forKey: "assistantOptions")
        let root = Self.backupFolder
        Task.detached(priority: .utility) {
            do {
                guard let made = try DataBackup.run(sources: sources, settings: settings, into: root) else { return }
                await MainActor.run { self.add(.info, "今天的备份做好了：\(made.lastPathComponent)（留最近 14 天）") }
            } catch {
                await MainActor.run { self.add(.error, "今天的备份没做成：\(error.localizedDescription)") }
            }
        }
    }
}
