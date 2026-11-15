import Foundation
import QingzhouCore

/// 从我的回复学知识: when the knowledge base had no answer and the owner replied themselves,
/// the question and the owner's reply wait on 首页; only approved ones go into the knowledge base.
extension AutoReplyController {
    func refreshAnswerSuggestions() {
        answerSuggestions = answerStore.items.filter(\.isReady)
    }

    /// The knowledge base had no answer: wait for what the owner writes back in this chat.
    func watchForOwnerAnswer(chat: String, who: String, question: String) {
        guard !question.isEmpty else { return }
        answerStore.watch(chat: chat, who: who, question: question)
        dayLog.addUnanswered(who: who, question: Privacy.redact(question).text)
        refreshAnswerSuggestions()
    }

    /// A rule handed this chat to the owner (讲价, 售后…): learn how he words his answer.
    func watchOwnerWording(chat: String, who: String, question: String) {
        guard !question.isEmpty else { return }
        answerStore.watch(chat: chat, who: who, question: question, manner: true)
    }

    /// The owner tells what a reply on 动态 should have been; it is used from the next reply on.
    func teach(question: String, reply: String, better: String) {
        let text = better.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lessons.add(Lesson(kind: .rewritten, question: Privacy.redact(question).text, draft: reply, final: Privacy.redact(text).text))
        dayLog.addLearned()
        add(.info, "记住了：“\(question.prefix(20))”以后这样回：\(text.prefix(30))")
    }

    /// Looks in a customer's remembered chat for the owner's reply to a waiting question.
    func learnOwnerAnswers(in record: CustomerRecord) {
        let open = answerStore.open(in: record.chatID)
        // While a reply is being sent, its text is not yet in the assistant's record: wait.
        let live = liveSteps(at: Date())
        guard !open.isEmpty, live.steps.isEmpty || live.ended else { return }
        let sent = assistantWritten()
        for s in open {
            // The owner may answer in several messages: the answer grows until it is approved.
            guard let found = OwnerAnswer.find(question: s.question, in: record.messages, assistantSent: sent) else { continue }
            let answer = Privacy.redact(found).text
            guard answer != s.answer else { continue }
            // His wording in a chat handed to him is learned right away, unless it names a number
            // or promises something: that waits on 首页 like a knowledge answer.
            if s.isManner, s.answer.isEmpty, !OwnerAnswer.needsApproval(answer) {
                // Several waiting messages are joined with " / "; he answered the last one.
                let asked = s.question.components(separatedBy: " / ").last ?? s.question
                lessons.add(Lesson(kind: .ownerSaid, question: Privacy.redact(asked).text, draft: "", final: answer))
                answerStore.remove(s.id)
                dayLog.addLearned()
                add(.info, "学到你回「\(s.who)」的说法：\(answer.prefix(30))")
                note(.learned, who: s.who, title: "学到你的说法", detail: "“\(answer)”")
                continue
            }
            answerStore.setAnswer(answer, for: s.id)
            add(.info, "学到你对「\(s.who)」的回答，放到首页等你确认：\(answer.prefix(30))")
        }
        refreshAnswerSuggestions()
    }

    /// Puts an approved question and answer into the knowledge base.
    func approveAnswer(_ id: UUID, question: String, answer: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !a.isEmpty else { return }
        do {
            try LearnedQA.append(question: Privacy.redact(q).text, answer: Privacy.redact(a).text, to: kbFolder)
            answerStore.remove(id)
            dayLog.addLearned()
            refreshAnswerSuggestions()
            reloadKB()
            add(.info, "已记进知识库「\(LearnedQA.fileName)」：\(q.prefix(20)) → \(a.prefix(30))")
        } catch {
            add(.error, "没能写进知识库：\(error.localizedDescription)")
        }
    }

    func discardAnswer(_ id: UUID) {
        answerStore.remove(id)
        refreshAnswerSuggestions()
    }

    /// What the assistant itself sent, so only the owner's own words are learned.
    private func assistantWritten() -> [String] {
        let kinds: Set<Activity.Kind> = [.replied, .outreach, .drafted]
        return activity.filter { kinds.contains($0.kind) }.map(\.detail)
            + (UserDefaults.standard.stringArray(forKey: "assistantSentTexts") ?? [])
    }
}
