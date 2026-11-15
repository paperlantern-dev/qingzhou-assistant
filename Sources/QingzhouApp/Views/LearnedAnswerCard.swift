import QingzhouCore
import SwiftUI

/// A question the knowledge base could not answer and the owner's own reply, both editable:
/// 记进知识库 adds it to the knowledge base, 不要 drops it.
struct LearnedAnswerCard: View {
    @EnvironmentObject var ctl: AutoReplyController
    let suggestion: AnswerSuggestion
    @State private var question: String
    @State private var answer: String

    init(suggestion: AnswerSuggestion) {
        self.suggestion = suggestion
        _question = State(initialValue: suggestion.question.replacingOccurrences(of: " / ", with: "，"))
        _answer = State(initialValue: suggestion.answer)
    }

    var body: some View {
        CardBox(border: Theme.green.opacity(0.45)) {
            HStack {
                Text("\(suggestion.who) 问的").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(suggestion.at.shortLabel).font(.system(size: 13)).foregroundStyle(Theme.sub)
            }
            field("客人问", $question, height: 36)
            field("你的回答", $answer, height: 60)
            Text("改成对所有客人都适用的说法再记，比如去掉只对这位客人说的价格或称呼")
                .font(.system(size: 12)).foregroundStyle(Theme.sub)
            HStack(spacing: 8) {
                Button { ctl.approveAnswer(suggestion.id, question: question, answer: answer) } label: {
                    Text("记进知识库").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.green)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("不要") { ctl.discardAnswer(suggestion.id) }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.sub)
            TextEditor(text: text)
                .font(.system(size: 14)).scrollContentBackground(.hidden).scrollIndicators(.never)
                .frame(minHeight: height, maxHeight: 96).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSoft))
        }
    }
}
