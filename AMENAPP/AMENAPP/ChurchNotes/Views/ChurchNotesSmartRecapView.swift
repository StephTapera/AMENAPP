import SwiftUI

// Smart Recap — source-grounded note recap shown after church or note completion.
// All content is editable before saving. Nothing is inserted silently.
struct ChurchNotesSmartRecapView: View {

    @ObservedObject var viewModel: ChurchNotesContextViewModel
    let noteId: String
    let noteText: String
    @State private var isEditingRecap = false
    @State private var editText = ""
    @State private var isSaved = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recapHeader
                    recapBody
                    prayerItemsSection
                    nextStepSection
                    relatedScriptureSection
                    provenanceSection
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Today\u{2019}s Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss recap")
                }
            }
        }
        .task {
            await viewModel.loadExistingRecap(noteId: noteId)
            if viewModel.smartRecap == nil {
                await viewModel.generateRecap(noteId: noteId, noteText: noteText)
            }
            editText = viewModel.smartRecap?.displayText ?? ""
        }
    }

    // MARK: - Header

    private var recapHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("AI-assisted recap", systemImage: "sparkles")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Here\u{2019}s what stood out today")
                .font(.title2.weight(.bold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI-assisted recap: Here's what stood out today")
    }

    // MARK: - Recap Body

    @ViewBuilder
    private var recapBody: some View {
        switch viewModel.recapLoadState {
        case .loading:
            CNLoadingView(label: "Generating your recap\u{2026}")
                .frame(height: 120)
        case .error(let msg):
            CNErrorView(message: msg) {
                Task { await viewModel.generateRecap(noteId: noteId, noteText: noteText) }
            }
        case .empty, .idle:
            Text("No recap available yet. Try adding more content to your note.")
                .font(.body)
                .foregroundStyle(.secondary)
        case .loaded:
            if let recap = viewModel.smartRecap {
                recapTextArea(recap: recap)
            }
        }
    }

    private func recapTextArea(recap: CNSmartRecap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditingRecap {
                TextEditor(text: $editText)
                    .font(.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Edit your recap. Current text: \(editText)")
                HStack {
                    Button("Save edits") {
                        viewModel.editRecap(newText: editText)
                        isEditingRecap = false
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel("Save your edits to the recap")
                    Button("Cancel") {
                        editText = recap.displayText
                        isEditingRecap = false
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text(recap.displayText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    editText = recap.displayText
                    isEditingRecap = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Edit this recap text")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Prayer Items

    @ViewBuilder
    private var prayerItemsSection: some View {
        if let recap = viewModel.smartRecap, !recap.prayerItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("3 things to pray through", systemImage: "hands.sparkles.fill")
                    .font(.headline)
                ForEach(Array(recap.prayerItems.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.subheadline)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Three things to pray through: \(recap.prayerItems.joined(separator: ". "))")
        }
    }

    // MARK: - Next Step

    @ViewBuilder
    private var nextStepSection: some View {
        if let step = viewModel.smartRecap?.nextStep {
            VStack(alignment: .leading, spacing: 8) {
                Label("One next step before Sunday", systemImage: "arrow.forward.circle.fill")
                    .font(.headline)
                Text(step)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("One next step before Sunday: \(step)")
        }
    }

    // MARK: - Related Scripture

    @ViewBuilder
    private var relatedScriptureSection: some View {
        if let recap = viewModel.smartRecap, !recap.relatedScriptures.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Related scriptures", systemImage: "book.fill")
                    .font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(recap.relatedScriptures, id: \.self) { ref in
                        Text(ref)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemFill), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Provenance

    @ViewBuilder
    private var provenanceSection: some View {
        if let recap = viewModel.smartRecap {
            CNProvenanceRow(label: recap.provenance)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !isSaved {
                Button {
                    Task {
                        await viewModel.saveEditedRecap()
                        withAnimation(reduceMotion ? nil : .easeOut) {
                            isSaved = true
                        }
                    }
                } label: {
                    Text("Save recap to notes")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Save this recap to your notes")
            } else {
                Label("Saved to notes", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Recap saved to your notes")
            }

            Button {
                dismiss()
            } label: {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Skip saving the recap")
        }
    }
}

// MARK: - Flow Layout (for scripture chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Smart Recap Trigger Button

struct ChurchNotesSmartRecapButton: View {
    @ObservedObject var viewModel: ChurchNotesContextViewModel
    let noteId: String
    let noteText: String
    private let flags = AMENFeatureFlags.shared

    var body: some View {
        if flags.churchNotesSmartRecapEnabled {
            Button {
                viewModel.isSmartRecapPresented = true
            } label: {
                Label("Smart Recap", systemImage: "sparkles")
            }
            .sheet(isPresented: $viewModel.isSmartRecapPresented) {
                ChurchNotesSmartRecapView(
                    viewModel: viewModel,
                    noteId: noteId,
                    noteText: noteText
                )
                .presentationDetents([.large])
            }
        }
    }
}
