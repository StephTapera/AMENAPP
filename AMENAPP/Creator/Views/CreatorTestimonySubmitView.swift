// CreatorTestimonySubmitView.swift
// AMENAPP — Creator Spotlight / Wave 2
//
// Testimony submission surface.
// CONSTITUTION LOCK: NO star rating, NO numeric rating, NO "Tap to Rate".
// Fail-closed: EmptyView when creatorTestimonyEnabled is false.

import SwiftUI

struct CreatorTestimonySubmitView: View {

    let creatorId: String
    let contentId: String?

    @ObservedObject var viewModel: CreatorTestimonyViewModel

    @State private var selectedTags: Set<ReflectionTag> = []
    @State private var writtenText: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxChars = 500

    var body: some View {
        if !AMENFeatureFlags.shared.creatorTestimonyEnabled {
            EmptyView()
        } else {
            content
        }
    }

    // MARK: - Content

    private var content: some View {
        ZStack {
            // Sheet background
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionTitle
                    tagPicker
                    reflectionField
                    submitButton
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .overlay {
            if viewModel.submitSuccess {
                confirmationOverlay
            }
        }
        .alert(
            "Couldn't share reflection",
            isPresented: Binding(
                get: { viewModel.submitError != nil },
                set: { if !$0 { viewModel.submitError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.submitError = nil }
        } message: {
            Text(viewModel.submitError ?? "")
        }
    }

    // MARK: - Section Title

    private var sectionTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Share a Reflection")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Your reflection will be reviewed before it appears.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tag Picker

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What resonated with you?")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            ReflectionTagLayout(spacing: 8) {
                ForEach(ReflectionTag.allCases, id: \.self) { tag in
                    TagChip(
                        label: tag.displayLabel,
                        isSelected: selectedTags.contains(tag)
                    ) {
                        toggleTag(tag)
                    }
                }
            }
        }
    }

    // MARK: - Written Reflection

    private var reflectionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Written Reflection (optional)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )

                if writtenText.isEmpty {
                    Text("What was meaningful about this?")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $writtenText)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .onChange(of: writtenText) { newValue in
                        if newValue.count > maxChars {
                            writtenText = String(newValue.prefix(maxChars))
                        }
                    }
            }
            .frame(minHeight: 100)

            HStack {
                Spacer()
                Text("\(writtenText.count)/\(maxChars)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            Task { await handleSubmit() }
        } label: {
            ZStack {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Share Reflection")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(selectedTags.isEmpty ? Color.blue.opacity(0.4) : Color.blue)
            )
        }
        .disabled(selectedTags.isEmpty || viewModel.isSubmitting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedTags.isEmpty)
    }

    // MARK: - Confirmation Overlay

    private var confirmationOverlay: some View {
        ZStack {
            Color(.systemBackground).opacity(0.95).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Your reflection is being reviewed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("It will appear once our team approves it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") {
                    viewModel.resetSubmitState()
                    dismiss()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.top, 8)
            }
            .padding(32)
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Actions

    private func toggleTag(_ tag: ReflectionTag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func handleSubmit() async {
        await viewModel.submit(
            creatorId: creatorId,
            contentId: contentId,
            tags: Array(selectedTags),
            written: writtenText.isEmpty ? nil : writtenText
        )
    }
}

// MARK: - Tag Chip

private struct TagChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.green : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            isSelected
                                ? Color.green.opacity(0.15)
                                : Color(.secondarySystemBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    isSelected ? Color.green.opacity(0.5) : Color(.separator),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - FlowLayout

/// Simple flow layout for chip rows.
private struct ReflectionTagLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - ReflectionTag Display

private extension ReflectionTag {
    var displayLabel: String {
        switch self {
        case .scriptureHelpful:       return "Scripture was helpful"
        case .encouragedDeeperStudy:  return "Encouraged deeper study"
        case .practical:              return "Practical"
        case .goodForGroups:          return "Good for groups"
        case .helpfulForNewBelievers: return "Helpful for new believers"
        case .clear:                  return "Clear teaching"
        }
    }
}
