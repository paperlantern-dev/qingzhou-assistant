import Foundation
import QingzhouCore

/// One step of the reply being worked on, shown live on 首页 (读取会话 → 检索知识库 → 正在输入…).
struct ReplyStep: Identifiable {
    let id = UUID()
    let time = Date()
    let title: String
    let detail: String

    /// Steps that end a reply: sent, left on 首页 for the user, or given up.
    static let endings: Set<String> = ["已发送", "放到首页，等你确认", "没有发送"]

    var ends: Bool { Self.endings.contains(title) }
}

/// 实时显示每一步: the steps of the reply in progress, for 首页.
extension AutoReplyController {
    /// Steps stay on 首页 this long after the last one while the reply is still going…
    static let stepsShownWhileGoing: TimeInterval = 120
    /// …and this long after the reply ended.
    static let stepsShownAfterEnd: TimeInterval = 60

    /// A new reply starts: forget the last one's steps.
    func beginSteps(who: String, said: String) {
        steps = [ReplyStep(title: "读取会话", detail: "\(who)：\(said)")]
    }

    func step(_ title: String, _ detail: String = "") {
        steps.append(ReplyStep(title: title, detail: detail))
    }

    /// What 首页 shows at `now`: the steps (empty when there is nothing current) and whether that
    /// reply is over. Once “今天” has a line after the last step (已回复, 交给你…) the steps go away.
    func liveSteps(at now: Date) -> (steps: [ReplyStep], ended: Bool) {
        guard isRunning, let last = steps.last else { return ([], false) }
        // Its result is already a line in “今天” (已回复…): showing the steps too would say it twice.
        if noteTime(after: last) != nil { return ([], true) }
        let endedAt = last.ends ? last.time : nil
        let shownUntil = endedAt.map { $0 + Self.stepsShownAfterEnd } ?? last.time + Self.stepsShownWhileGoing
        return now < shownUntil ? (steps, endedAt != nil) : ([], false)
    }

    /// Closes a reply that stopped without an ending step or a line in “今天” (演练, an error,
    /// a reply gone stale), so it doesn't look like it is still going.
    func endStepsIfOpen() {
        guard let last = steps.last, !last.ends, noteTime(after: last) == nil else { return }
        step("没有发送")
    }

    /// When “今天” got a line after this step, if it did.
    private func noteTime(after step: ReplyStep) -> Date? {
        activity.last.map(\.time).flatMap { $0 > step.time ? $0 : nil }
    }
}
