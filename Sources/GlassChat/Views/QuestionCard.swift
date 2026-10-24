import SwiftUI

/// The questions of `app_ask_user` waiting in a chat: one at a time, then a summary to confirm.
/// The same card shows in the chat and in the notch.
struct QuestionCard: View {
    let chatID: Chat.ID
    private var center = QuestionCenter.shared
    @State private var other = ""
    @State private var chosen: Set<String> = []

    init(chatID: Chat.ID) {
        self.chatID = chatID
    }

    var body: some View {
        if let pending = center.pending[chatID] {
            VStack(alignment: .leading, spacing: 10) {
                if pending.isReviewing {
                    summary(pending)
                } else {
                    question(pending, pending.questions[pending.index])
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
            .frame(maxWidth: 560, alignment: .leading)
            .onChange(of: pending.index) { _, _ in other = ""; chosen = [] }
        }
    }

    private func question(_ pending: PendingQuestions, _ q: AskQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let header = q.header {
                    Text(header)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: .capsule)
                }
                Text("\(pending.index + 1)/\(pending.questions.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(q.question).font(.headline)

            ForEach(q.options, id: \.self) { option in
                Button {
                    if q.multiSelect {
                        if chosen.contains(option.label) { chosen.remove(option.label) } else { chosen.insert(option.label) }
                    } else {
                        center.answer(.one(option.label), in: chatID)
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if q.multiSelect {
                            Image(systemName: chosen.contains(option.label) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(chosen.contains(option.label) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                            if let description = option.description {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            TextField("Other…", text: $other)
                .textFieldStyle(.roundedBorder)
                .onSubmit { answerOther(q) }

            HStack {
                Button("Back") { center.back(in: chatID) }
                    .disabled(pending.index == 0)
                Button("Skip") { center.answer(.skipped, in: chatID) }
                Spacer()
                Button("Cancel") { center.dismiss(in: chatID) }
                if q.multiSelect {
                    Button("Next") { answerOther(q) }
                        .buttonStyle(.glassProminent)
                        .disabled(chosen.isEmpty && other.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func summary(_ pending: PendingQuestions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pending.questions.enumerated()), id: \.offset) { i, q in
                VStack(alignment: .leading, spacing: 2) {
                    Text(q.question).font(.callout.weight(.medium))
                    Text(Self.text(of: pending.answers[i]))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Back") { center.back(in: chatID) }
                Spacer()
                Button("Cancel") { center.dismiss(in: chatID) }
                Button("Confirm") { center.confirm(in: chatID) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The typed answer (with the ticked options, for several).
    private func answerOther(_ q: AskQuestion) {
        let typed = other.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.multiSelect {
            let all = q.options.map(\.label).filter(chosen.contains) + (typed.isEmpty ? [] : [typed])
            guard !all.isEmpty else { return }
            center.answer(.many(all), in: chatID)
        } else {
            guard !typed.isEmpty else { return }
            center.answer(.one(typed), in: chatID)
        }
    }

    private static func text(of answer: AskAnswer) -> String {
        switch answer {
        case .skipped: "Skipped"
        case .one(let text): text
        case .many(let texts): texts.joined(separator: ", ")
        }
    }
}
