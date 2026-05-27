import SwiftUI

// Berean Context Panel — bottom sheet surfacing contextual intelligence for a Church Note.
// Liquid Glass used only for the floating capsule, not as a body background.
// Every AI result carries a provenance label with source, confidence, and why-suggested.
struct BereanContextPanelView: View {

    @ObservedObject var viewModel: ChurchNotesContextViewModel
    @State private var selectedSection: CNContextSection = .relatedScripture
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionPicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Berean Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    provenanceDisclaimer
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss Berean context panel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? Color(.systemBackground) : .regularMaterial)
    }

    // MARK: - Section Picker (Liquid Glass floating capsule strip)

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CNContextSection.allCases) { section in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                            selectedSection = section
                        }
                    } label: {
                        Label(section.displayTitle, systemImage: section.sfSymbol)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedSection == section
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.secondarySystemFill),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                selectedSection == section ? Color.accentColor : Color.secondary
                            )
                    }
                    .accessibilityLabel(section.displayTitle)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.loadState {
        case .loading:
            CNLoadingView(label: "Loading context\u{2026}")
        case .error(let message):
            CNErrorView(message: message) {
                // Retry is handled by the parent view re-calling loadContext
            }
        case .empty, .idle:
            CNEmptyStateView(
                icon: "sparkles",
                title: "No context yet",
                message: "Add more content to your note to generate context."
            )
        case .loaded:
            if let result = viewModel.contextResult {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        sectionContent(result: result)
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Section Content Routing

    @ViewBuilder
    private func sectionContent(result: CNContextResult) -> some View {
        switch selectedSection {
        case .relatedScripture:
            CNSectionContainer(title: selectedSection.displayTitle, isEmpty: result.relatedScriptures.isEmpty) {
                ForEach(result.relatedScriptures) { scripture in
                    CNScriptureCard(scripture: scripture)
                }
            }
        case .relatedNotes:
            CNSectionContainer(title: selectedSection.displayTitle, isEmpty: result.relatedNotes.isEmpty) {
                ForEach(result.relatedNotes) { note in
                    CNRelatedNoteCard(note: note)
                }
            }
        case .themes:
            CNSectionContainer(title: selectedSection.displayTitle, isEmpty: result.detectedThemes.isEmpty) {
                ForEach(result.detectedThemes) { theme in
                    CNThemeCard(theme: theme)
                }
            }
        case .prayerPrompts:
            CNSectionContainer(title: selectedSection.displayTitle, isEmpty: result.prayerPrompts.isEmpty) {
                ForEach(result.prayerPrompts) { prompt in
                    CNPrayerPromptCard(prompt: prompt)
                }
            }
        case .reflectionQuestions:
            CNSectionContainer(title: selectedSection.displayTitle, isEmpty: result.reflectionQuestions.isEmpty) {
                ForEach(result.reflectionQuestions) { question in
                    CNReflectionQuestionCard(question: question)
                }
            }
        case .smallGroupQuestions:
            CNSectionContainer(title: selectedSection.displayTitle, isEmpty: result.smallGroupQuestions.isEmpty) {
                ForEach(result.smallGroupQuestions) { question in
                    CNSmallGroupQuestionCard(question: question) { approved in
                        // Approval handled in parent view
                    }
                }
            }
        case .actionSuggestions:
            CNSectionContainer(title: selectedSection.displayTitle, isEmpty: result.actionSuggestions.isEmpty) {
                ForEach(result.actionSuggestions) { suggestion in
                    CNActionSuggestionCard(
                        suggestion: suggestion,
                        onApprove: { Task { await viewModel.approveActionSuggestion(suggestion) } },
                        onEdit: { newText in viewModel.editActionSuggestion(id: suggestion.id, newText: newText) },
                        onReject: { Task { await viewModel.rejectActionSuggestion(suggestion) } }
                    )
                }
            }
        }
    }

    // MARK: - Provenance Disclaimer

    private var provenanceDisclaimer: some View {
        Label("AI-assisted", systemImage: "sparkles")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("AI-assisted content — all suggestions require your review")
    }
}

// MARK: - Section Container

private struct CNSectionContainer<Content: View>: View {
    let title: String
    let isEmpty: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEmpty {
                CNEmptyStateView(
                    icon: "tray",
                    title: "Nothing here yet",
                    message: "More context will appear as you build your note."
                )
            } else {
                content()
            }
        }
    }
}

// MARK: - Scripture Card

private struct CNScriptureCard: View {
    let scripture: CNRelatedScripture

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scripture.reference)
                .font(.headline)
            if let text = scripture.text {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            CNProvenanceRow(label: scripture.provenance)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scripture: \(scripture.reference). \(scripture.provenance.confidence.accessibilityDescription)")
    }
}

// MARK: - Related Note Card

private struct CNRelatedNoteCard: View {
    let note: CNRelatedNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(.headline)
            if let sermon = note.sermonTitle {
                Text(sermon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.connectionSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                ForEach(note.sharedThemes.prefix(3), id: \.self) { theme in
                    Text(theme)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            CNProvenanceRow(label: note.provenance)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Related note: \(note.title). \(note.connectionSummary)")
    }
}

// MARK: - Theme Card

private struct CNThemeCard: View {
    let theme: CNDetectedTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(theme.theme)
                    .font(.headline)
                Spacer()
                if theme.isRecurring {
                    Label("Recurring", systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Recurring theme in your notes")
                }
            }
            Text(theme.recurringLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let quote = theme.exampleQuotes.first {
                Text("\u{201C}\(quote)\u{201D}")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            CNProvenanceRow(label: theme.provenance)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme: \(theme.theme). \(theme.isRecurring ? "Recurring in your notes." : "") \(theme.provenance.confidence.accessibilityDescription)")
    }
}

// MARK: - Prayer Prompt Card

private struct CNPrayerPromptCard: View {
    let prompt: CNPrayerPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt.text)
                .font(.body)
            CNProvenanceRow(label: prompt.provenance)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Prayer prompt: \(prompt.text). \(prompt.provenance.confidence.accessibilityDescription)")
    }
}

// MARK: - Reflection Question Card

private struct CNReflectionQuestionCard: View {
    let question: CNReflectionQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.text)
                .font(.body)
            CNProvenanceRow(label: question.provenance)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Reflection question: \(question.text)")
    }
}

// MARK: - Small Group Question Card

private struct CNSmallGroupQuestionCard: View {
    let question: CNSmallGroupQuestion
    let onApprove: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.text)
                .font(.body)
            HStack {
                CNProvenanceRow(label: question.provenance)
                Spacer()
                Button {
                    onApprove(true)
                } label: {
                    Label("Use in group", systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Approve this small group question")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Action Suggestion Card

private struct CNActionSuggestionCard: View {
    let suggestion: CNActionSuggestion
    let onApprove: () -> Void
    let onEdit: (String) -> Void
    let onReject: () -> Void
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(suggestion.type.displayLabel, systemImage: suggestion.type.sfSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                approvalBadge
            }
            if isEditing {
                TextField("Edit\u{2026}", text: $editText, axis: .vertical)
                    .font(.body)
                    .padding(8)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("Save") {
                        onEdit(editText)
                        isEditing = false
                    }
                    .font(.caption.weight(.medium))
                    Button("Cancel") { isEditing = false }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(suggestion.displayText)
                    .font(.body)
            }
            if let quote = suggestion.sourceQuote {
                Text("From: \u{201C}\(String(quote.prefix(80)))\u{201C}")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.tertiary)
            }
            CNProvenanceRow(label: suggestion.provenance)
            if suggestion.approvalState == .pending {
                approvalControls
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { editText = suggestion.displayText }
    }

    @ViewBuilder
    private var approvalBadge: some View {
        switch suggestion.approvalState {
        case .approved, .edited:
            Label("Approved", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .rejected:
            Label("Rejected", systemImage: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .pending:
            EmptyView()
        }
    }

    private var approvalControls: some View {
        HStack(spacing: 12) {
            Button {
                onApprove()
            } label: {
                Text("Approve")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Approve this action suggestion")

            Button {
                isEditing = true
            } label: {
                Text("Edit")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }
            .accessibilityLabel("Edit this action suggestion before approving")

            Button {
                onReject()
            } label: {
                Text("Reject")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Reject this action suggestion")
        }
    }
}

// MARK: - Provenance Row

struct CNProvenanceRow: View {
    let label: CNProvenanceLabel
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(confidenceColor)
                    .frame(width: 6, height: 6)
                Text("\(label.confidence.displayLabel) \u{B7} \(label.source)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if isExpanded {
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Source: \(label.source). Confidence: \(label.confidence.accessibilityDescription). Tap to \(isExpanded ? "hide" : "show") why this was suggested.")

        if isExpanded {
            Text(label.whySuggested)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confidenceColor: Color {
        switch label.confidence {
        case .confirmed:   return .green
        case .possible:    return .orange
        case .needsReview: return .red
        }
    }
}

// MARK: - Shared Empty / Loading / Error Views

struct CNEmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

struct CNLoadingView: View {
    let label: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(label)
    }
}

struct CNErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
