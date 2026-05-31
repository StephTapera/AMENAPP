import SwiftUI

struct PostActionReflectionSheet: View {
    let reflection: PostActionReflection
    let onComplete: (PostActionReflection) -> Void
    let onDismiss: () -> Void

    @State private var step = 0
    @State private var intentText = ""
    @State private var outcomeText = ""
    @State private var lessonText = ""
    @State private var isSaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    progressIndicator.padding(.top, 12)

                    TabView(selection: $step) {
                        questionStep(
                            question: reflection.actionType.reflectionQuestion,
                            placeholder: "Write what comes to mind...",
                            binding: $outcomeText,
                            tag: 0
                        )

                        questionStep(
                            question: "What were you hoping would happen?",
                            placeholder: "Your intention going in...",
                            binding: $intentText,
                            tag: 1
                        )

                        questionStep(
                            question: "What would you carry forward from this?",
                            placeholder: "A lesson, a pattern, a prayer...",
                            binding: $lessonText,
                            tag: 2
                        )
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: step)

                    actionRow
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onDismiss)
                        .foregroundStyle(Color.secondary)
                        .accessibilityLabel("Skip reflection")
                }
            }
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.primary : Color.secondary.opacity(0.2))
                    .frame(width: i == step ? 24 : 8, height: 6)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
        .padding(.bottom, 24)
        .accessibilityHidden(true)
    }

    private func questionStep(question: String, placeholder: String, binding: Binding<String>, tag: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(question)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if binding.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: binding)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            }
            .padding(16)
            .amenGlass(.thin, cornerRadius: 18)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .tag(tag)
    }

    private var actionRow: some View {
        HStack {
            if step > 0 {
                Button(action: { withAnimation { step -= 1 } }) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .amenGlass(.thin, cornerRadius: 999)
                }
                .accessibilityLabel("Previous question")
            }

            Spacer()

            if step < 2 {
                Button(action: { withAnimation { step += 1 } }) {
                    Text("Next")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.primary, in: Capsule())
                }
                .accessibilityLabel("Next question")
            } else {
                Button(action: saveReflection) {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save reflection")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.primary, in: Capsule())
                }
                .accessibilityLabel("Save your reflection")
                .disabled(isSaving)
            }
        }
    }

    private func saveReflection() {
        isSaving = true
        let updated = PostActionReflection(
            id: reflection.id,
            userId: reflection.userId,
            sourceActionId: reflection.sourceActionId,
            actionType: reflection.actionType,
            intentBefore: intentText.isEmpty ? nil : intentText,
            outcomeReflection: outcomeText.isEmpty ? nil : outcomeText,
            lessonLearned: lessonText.isEmpty ? nil : lessonText,
            completedAt: Date()
        )
        onComplete(updated)
    }
}

// MARK: - Intent vs Outcome Card (for display)

struct IntentVsOutcomeCard: View {
    let reflection: PostActionReflection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let intent = reflection.intentBefore {
                labeledText("What I intended", text: intent)
            }
            if let outcome = reflection.outcomeReflection {
                Divider().opacity(0.3)
                labeledText("How it went", text: outcome)
            }
            if let lesson = reflection.lessonLearned {
                Divider().opacity(0.3)
                labeledText("What I learned", text: lesson)
            }
        }
        .padding(16)
        .amenGlass(.thin, cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }

    private func labeledText(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
        }
    }
}
