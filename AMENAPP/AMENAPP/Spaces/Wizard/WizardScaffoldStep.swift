// WizardScaffoldStep.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// Step 2: Scaffold — Berean-generated Space proposal.
//
// Loading state: animated shimmer placeholder (3 lines).
// Loaded state: glass card with amenGold header, passage refs (Study),
//   cadence, 3 discussion prompt chips, description, Edit / Use This buttons.
// Error state: glass error card with retry button.
//
// "Edit" toggles inline TextFields over each editable field.
// "Use this" calls viewModel.advance() to move to Step 3.

import SwiftUI

// MARK: - WizardScaffoldStep

struct WizardScaffoldStep: View {

    @ObservedObject var viewModel: SpaceCreationViewModel
    @State private var isEditing: Bool = false

    @State private var editDescription: String = ""
    @State private var editPassageRefs: String = ""
    @State private var editCadence: String = ""
    @State private var editPrompt0: String = ""
    @State private var editPrompt1: String = ""
    @State private var editPrompt2: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 20) {
            headerLabel

            Group {
                if viewModel.isScaffolding {
                    shimmerCard
                } else if let error = viewModel.scaffoldError {
                    errorCard(error)
                } else if let scaffold = viewModel.scaffold {
                    scaffoldCard(scaffold)
                } else {
                    shimmerCard
                }
            }
            .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isScaffolding)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .onChange(of: viewModel.scaffold) {
            if let s = viewModel.scaffold { syncEditState(from: s) }
        }
    }

    // MARK: - Header

    private var headerLabel: some View {
        VStack(spacing: 6) {
            Text("Berean suggests a structure")
                .font(.title2.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Review, edit, or use as-is to continue.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Shimmer placeholder

    private var shimmerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .frame(width: 130, height: 16)
                Spacer()
            }
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .frame(height: 14)
                    .opacity(1.0 - Double(index) * 0.2)
            }
        }
        .foregroundStyle(AmenTheme.Colors.shimmerBase)
        .padding(20)
        .amenGlassCard()
        .amenSkeleton()
        .accessibilityLabel("Loading Berean suggestions")
    }

    // MARK: - Scaffold card

    private func scaffoldCard(_ scaffold: SpaceBereanScaffold) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .accessibilityHidden(true)

                Text("Berean suggests")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)

                Spacer()
            }

            Divider().background(AmenTheme.Colors.separatorSubtle)

            // Passage refs (Study only)
            if viewModel.selectedType == .bibleStudy {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Passages", systemImage: "book.closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)

                    if isEditing {
                        TextField("Passage refs (comma-separated)", text: $editPassageRefs)
                            .font(.subheadline)
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .textFieldStyle(.plain)
                    } else {
                        let refs = scaffold.passageRefs ?? []
                        Text(refs.isEmpty ? "No specific passages" : refs.joined(separator: " · "))
                            .font(.subheadline.weight(refs.isEmpty ? .regular : .medium))
                            .foregroundStyle(refs.isEmpty ? AmenTheme.Colors.textSecondary : AmenTheme.Colors.textPrimary)
                    }
                }
            }

            // Cadence
            if let cadence = scaffold.cadenceSuggestion, !cadence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Cadence", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)

                    if isEditing {
                        TextField("Cadence suggestion", text: $editCadence)
                            .font(.subheadline)
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .textFieldStyle(.plain)
                    } else {
                        Text(cadence)
                            .font(.subheadline)
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                }
            }

            // Discussion prompts
            if !scaffold.discussionPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Discussion prompts", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)

                    if isEditing {
                        Group {
                            TextField("Prompt 1", text: $editPrompt0).font(.subheadline).textFieldStyle(.plain)
                            TextField("Prompt 2", text: $editPrompt1).font(.subheadline).textFieldStyle(.plain)
                            TextField("Prompt 3", text: $editPrompt2).font(.subheadline).textFieldStyle(.plain)
                        }
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    } else {
                        ForEach(Array(scaffold.discussionPrompts.prefix(3).enumerated()), id: \.offset) { _, prompt in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                                    .padding(.top, 6)
                                    .accessibilityHidden(true)
                                Text(prompt)
                                    .font(.subheadline)
                                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            // Description
            VStack(alignment: .leading, spacing: 6) {
                Label("Description", systemImage: "text.alignleft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)

                if isEditing {
                    TextField("Description", text: $editDescription, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                } else {
                    Text(scaffold.description)
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().background(AmenTheme.Colors.separatorSubtle)

            HStack(spacing: 12) {
                Button {
                    if !isEditing { syncEditState(from: scaffold) }
                    else { applyEditsToScaffold() }
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3)) {
                        isEditing.toggle()
                    }
                } label: {
                    Text(isEditing ? "Cancel" : "Edit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                .fill(AmenTheme.Colors.surfaceChip)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    if isEditing { applyEditsToScaffold() }
                    viewModel.advance()
                } label: {
                    Text("Use this")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                .fill(AmenTheme.Colors.amenGold)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use this suggestion and continue")
            }
        }
        .padding(20)
        .amenGlassCard()
    }

    // MARK: - Error card

    private func errorCard(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(AmenTheme.Colors.statusError)
                .accessibilityHidden(true)

            Text("Berean couldn't generate a suggestion")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(error.userFriendlyMessage)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.requestScaffold() }
            } label: {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AmenTheme.Colors.amenGold)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Try generating suggestions again")
        }
        .padding(24)
        .amenGlassCard()
    }

    // MARK: - Edit state sync

    private func syncEditState(from scaffold: SpaceBereanScaffold) {
        editDescription = scaffold.description
        editPassageRefs = (scaffold.passageRefs ?? []).joined(separator: ", ")
        editCadence = scaffold.cadenceSuggestion ?? ""
        let prompts = (scaffold.discussionPrompts + ["", "", ""]).prefix(3)
        editPrompt0 = prompts[0]
        editPrompt1 = prompts[1]
        editPrompt2 = prompts[2]
    }

    private func applyEditsToScaffold() {
        guard var s = viewModel.scaffold else { return }
        s.description = editDescription
        let refs = editPassageRefs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        s.passageRefs = refs.isEmpty ? nil : refs
        s.cadenceSuggestion = editCadence.isEmpty ? nil : editCadence
        s.discussionPrompts = [editPrompt0, editPrompt1, editPrompt2].filter { !$0.isEmpty }
        viewModel.scaffold = s
    }
}

#if DEBUG
#Preview("WizardScaffoldStep") {
    let vm = SpaceCreationViewModel()
    vm.selectedType = .bibleStudy
    vm.scaffold = SpaceBereanScaffold(
        description: "A deep dive into Paul's letter on grace and faith.",
        passageRefs: ["Romans 1–8", "Romans 12:1-2"],
        cadenceSuggestion: "5-week study",
        discussionPrompts: ["What does justified by faith mean to you?", "How does Romans 8 speak to your season?", "What is a living sacrifice this week?"],
        suggestedTitle: nil
    )
    return WizardScaffoldStep(viewModel: vm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
}
#endif
