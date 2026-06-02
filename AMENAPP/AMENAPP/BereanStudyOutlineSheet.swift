import SwiftUI
import FirebaseAnalytics

// MARK: - Study Outline Sheet

struct BereanStudyOutlineSheet: View {
    let topic: String
    let onContinueChat: (String) -> Void
    let onSaveToNotes: (BereanStudyOutline) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var outline: BereanStudyOutline? = nil
    @State private var isLoading = true
    @State private var showSavedToast = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let outline {
                    contentView(outline)
                } else {
                    errorView
                }
            }
            .navigationTitle("Study Outline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? .thickMaterial : .regularMaterial)
        .overlay(alignment: .top) {
            if showSavedToast {
                Text("Saved to Church Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .padding(.top, 56)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSavedToast)
        .task { await load() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(.secondary)
            Text("Building study outline…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(topic)
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .accessibilityLabel("Building study outline, please wait")
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Couldn't build outline")
                .font(.headline)
            Button("Continue in Berean") {
                onContinueChat("Create a study outline for: \(topic)")
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
            Spacer()
        }
        .padding(24)
    }

    // MARK: - Content

    private func contentView(_ outline: BereanStudyOutline) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title + question
                VStack(alignment: .leading, spacing: 6) {
                    Text(outline.title)
                        .font(.title3.bold())
                    Text(outline.mainQuestion)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Key passages
                if !outline.keyPassages.isEmpty {
                    outlineSection(icon: "book.closed", label: "Key passages") {
                        AnyView(FlowLayout(items: outline.keyPassages) { ref in
                            Text(ref)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.07), in: Capsule())
                                .overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 0.5))
                        })
                    }
                }

                // Historical context
                if let context = outline.historicalContextNote, !context.isEmpty {
                    outlineSection(icon: "clock.arrow.circlepath", label: "Historical context") {
                        AnyView(Text(context)
                            .font(.subheadline)
                            .foregroundStyle(.secondary))
                    }
                }

                // Reflection questions
                if !outline.reflectionQuestions.isEmpty {
                    outlineSection(icon: "bubble.left.and.text.bubble.right", label: "Reflection questions") {
                        AnyView(VStack(alignment: .leading, spacing: 10) {
                            ForEach(outline.reflectionQuestions, id: \.self) { q in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(q)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        })
                    }
                }

                // Next steps
                if !outline.nextSteps.isEmpty {
                    outlineSection(icon: "arrow.right.circle", label: "Next steps") {
                        AnyView(VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(outline.nextSteps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1).")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18, alignment: .leading)
                                    Text(step)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        })
                    }
                }

                // Actions
                actions(outline)
            }
            .padding(20)
        }
    }

    private func outlineSection<C: View>(icon: String, label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func actions(_ outline: BereanStudyOutline) -> some View {
        VStack(spacing: 10) {
            Button {
                onContinueChat("Using this study outline as our starting point: \(outline.title). \(outline.mainQuestion) Let's begin.")
                Analytics.logEvent("berean_study_outline_created", parameters: ["source": "continue_chat"])
                dismiss()
            } label: {
                Label("Continue in Berean", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)

            Button {
                onSaveToNotes(outline)
                showSavedToast = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    showSavedToast = false
                }
            } label: {
                Label("Save to Church Notes", systemImage: "note.text.badge.plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func load() async {
        isLoading = true
        outline = await BereanGrokService.shared.createStudyOutline(topic: topic)
        isLoading = false
    }
}
