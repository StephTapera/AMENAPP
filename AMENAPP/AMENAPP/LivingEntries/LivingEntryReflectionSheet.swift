import SwiftUI

struct LivingEntryReflectionSheet: View {
    let entry: LivingEntry
    var onSubmit: (String, LivingEntryHelpfulness) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    @State private var helpfulness: LivingEntryHelpfulness = .helpful
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LivingEntryLiquidGlassCard(contextTint: .black.opacity(0.04), elevated: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(entry.title)
                                .font(.title3.weight(.semibold))
                            if !entry.previewBody.isEmpty {
                                Text(entry.previewBody)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(prompts, id: \.self) { prompt in
                            Text(prompt)
                                .font(.headline)
                            if prompt == prompts.last {
                                TextEditor(text: $answer)
                                    .frame(minHeight: 120)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How did this land?")
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                            ForEach(options, id: \.rawValue) { option in
                                Button {
                                    helpfulness = option
                                } label: {
                                    Text(option.label)
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(helpfulness == option ? Color.black : Color.white.opacity(0.7))
                                )
                                .foregroundStyle(helpfulness == option ? .white : .black)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving..." : "Save") {
                        Task {
                            isSubmitting = true
                            await onSubmit(answer, helpfulness)
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private var prompts: [String] {
        switch entry.type {
        case .churchNote, .sermonInsight:
            return [
                "What should you remember from this?",
                "Did this change how you want to live this week?",
                "Do you want Berean to help turn this into a prayer, note, or action?"
            ]
        case .prayer:
            return [
                "Keep praying, mark answered, or archive?",
                "What do you want to remember about this?"
            ]
        default:
            return [
                "Was this helpful, mistimed, or no longer needed?",
                "Should Amen remind you differently next time?"
            ]
        }
    }

    private var options: [LivingEntryHelpfulness] {
        switch entry.type {
        case .churchNote, .sermonInsight:
            return [.meaningful, .helpful, .mistimed]
        case .prayer:
            return [.meaningful, .helpful, .notNeeded]
        default:
            return [.helpful, .mistimed, .notNeeded]
        }
    }
}

private extension LivingEntryHelpfulness {
    var label: String {
        switch self {
        case .helpful: return "Helpful"
        case .mistimed: return "Mistimed"
        case .notNeeded: return "Not Needed"
        case .meaningful: return "Meaningful"
        }
    }
}
