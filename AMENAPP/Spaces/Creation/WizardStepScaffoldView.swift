// WizardStepScaffoldView.swift
// AMENAPP — Spaces v2 Creation Wizard, Step 2 (Agent D)
//
// Shows Berean's live SSE stream while loading, then presents the scaffold
// for acceptance, editing, or skipping. This is the differentiator over Slack.

import SwiftUI

struct WizardStepScaffoldView: View {

    @ObservedObject var vm: SpacesCreationViewModel
    @State private var showEditSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if vm.isLoadingScaffold {
                    loadingState
                } else if let error = vm.scaffoldError {
                    errorState(message: error)
                } else if let scaffold = vm.draft.scaffold {
                    scaffoldContent(scaffold)
                } else {
                    loadingState // initial state before task fires
                }
            }
            .padding(20)
        }
        .task {
            // Only request scaffold if we haven't already received one
            if vm.draft.scaffold == nil && !vm.isLoadingScaffold {
                await vm.requestScaffold()
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let scaffold = vm.draft.scaffold {
                ScaffoldEditSheet(scaffold: scaffold) { updated in
                    vm.draft.scaffold = updated
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Loading / streaming state

    private var loadingState: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Text("Berean is thinking\u{2026}")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if !vm.scaffoldStreamBuffer.isEmpty {
                Text(vm.scaffoldStreamBuffer)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.default, value: vm.scaffoldStreamBuffer)
                    .padding(16)
                    .wizardGlassCard()
                    .accessibilityLabel("Berean response streaming")
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AmenTheme.Colors.amenGold)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean is generating a scaffold. Please wait.")
    }

    // MARK: - Error state

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.amenBronze)

            Text("Berean is unavailable")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                AmenLiquidGlassPillButton(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    isLoading: false,
                    isDisabled: false
                ) {
                    Task { await vm.requestScaffold() }
                }

                skipButton
            }
        }
        .padding(20)
        .wizardGlassCard()
    }

    // MARK: - Scaffold content

    private func scaffoldContent(_ scaffold: BereanScaffoldResponse) -> some View {
        VStack(spacing: 16) {
            // AI disclosure header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Text("Berean suggested this scaffold")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Study content
            if vm.draft.intent == .study {
                studyScaffoldSection(scaffold)
            } else {
                discussionScaffoldSection(scaffold)
            }

            // Action row
            actionRow
        }
    }

    // MARK: - Study scaffold

    private func studyScaffoldSection(_ scaffold: BereanScaffoldResponse) -> some View {
        VStack(spacing: 12) {
            // Passage refs
            if !scaffold.passageRefs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Passages", icon: "book.closed.fill")
                    // Use wrapping chips via LazyVGrid
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(scaffold.passageRefs, id: \.self) { ref in
                            Text(ref)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AmenTheme.Colors.amenGold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(AmenTheme.Colors.amenGold.opacity(0.12))
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .stroke(AmenTheme.Colors.amenGold.opacity(0.3), lineWidth: 0.8)
                                        }
                                }
                        }
                    }
                }
                .padding(14)
                .wizardGlassCard()
            }

            // Cadence
            if let cadence = scaffold.cadence {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                    Text(cadence)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(14)
                .wizardGlassCard()
            }

            // Discussion prompts
            if !scaffold.discussionPrompts.isEmpty {
                promptListCard(
                    header: "Discussion Prompts",
                    icon: "text.bubble.fill",
                    prompts: scaffold.discussionPrompts
                )
            }
        }
    }

    // MARK: - Discussion / Group scaffold

    private func discussionScaffoldSection(_ scaffold: BereanScaffoldResponse) -> some View {
        VStack(spacing: 12) {
            if !scaffold.starterPrompts.isEmpty {
                promptListCard(
                    header: "Starter Threads",
                    icon: "bubble.left.and.bubble.right.fill",
                    prompts: scaffold.starterPrompts
                )
            }

            if !scaffold.suggestedNorms.isEmpty {
                promptListCard(
                    header: "Suggested Norms",
                    icon: "hand.raised.fill",
                    prompts: scaffold.suggestedNorms
                )
            }
        }
    }

    // MARK: - Shared prompt list card

    private func promptListCard(header: String, icon: String, prompts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(header, icon: icon)

            ForEach(prompts.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .center)
                    Text(prompts[i])
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
        .padding(14)
        .wizardGlassCard()
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 12) {
            skipButton

            // Edit button
            Button {
                showEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background {
                        Capsule(style: .continuous)
                            .fill(LiquidGlassTokens.blurThin)
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens editor to modify scaffold")

            Spacer()

            // Accept button
            AmenLiquidGlassPillButton(
                title: "Looks good",
                systemImage: "checkmark",
                isLoading: false,
                isDisabled: false
            ) {
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
                    vm.acceptScaffold()
                }
            }
        }
    }

    private var skipButton: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.liquidSpring) {
                vm.skipScaffold()
            }
        } label: {
            Text("Skip")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Continue without a scaffold")
    }
}

// MARK: - ScaffoldEditSheet

private struct ScaffoldEditSheet: View {

    @State private var editableScaffold: BereanScaffoldResponse
    let onSave: (BereanScaffoldResponse) -> Void
    @Environment(\.dismiss) private var dismiss

    init(scaffold: BereanScaffoldResponse, onSave: @escaping (BereanScaffoldResponse) -> Void) {
        self._editableScaffold = State(initialValue: scaffold)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                if !editableScaffold.passageRefs.isEmpty {
                    Section("Passages") {
                        ForEach(editableScaffold.passageRefs.indices, id: \.self) { i in
                            TextField("Passage", text: $editableScaffold.passageRefs[i])
                        }
                    }
                }

                if !editableScaffold.discussionPrompts.isEmpty {
                    Section("Discussion Prompts") {
                        ForEach(editableScaffold.discussionPrompts.indices, id: \.self) { i in
                            TextField("Prompt", text: $editableScaffold.discussionPrompts[i])
                        }
                    }
                }

                if !editableScaffold.starterPrompts.isEmpty {
                    Section("Starter Threads") {
                        ForEach(editableScaffold.starterPrompts.indices, id: \.self) { i in
                            TextField("Thread title", text: $editableScaffold.starterPrompts[i])
                        }
                    }
                }

                if !editableScaffold.suggestedNorms.isEmpty {
                    Section("Suggested Norms") {
                        ForEach(editableScaffold.suggestedNorms.indices, id: \.self) { i in
                            TextField("Norm", text: $editableScaffold.suggestedNorms[i])
                        }
                    }
                }
            }
            .navigationTitle("Edit Scaffold")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editableScaffold)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
