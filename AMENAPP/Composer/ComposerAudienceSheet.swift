// ComposerAudienceSheet.swift
// AMENAPP
//
// Audience & Reply Controls sheet for the AMEN composer.
// Matches the reference screenshot: reply policy radio rows,
// review-and-approve toggle, audience / cross-post row, sticky Done button.
//
// Dependencies (never re-declared here):
//   ComposerDraft, ComposerReplyPolicy, CrossPostDestination — ComposerContract.swift
//   AmenTheme.Colors.* — AmenTheme.swift
//   Motion.adaptive(), Motion.popToggle — Motion.swift

import SwiftUI

// MARK: - ComposerAudienceSheet

struct ComposerAudienceSheet: View {

    @Binding var draft: ComposerDraft
    @Binding var isPresented: Bool

    @State private var showCrossPostSheet = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // ---- Scrollable content ----
                ScrollView {
                    VStack(spacing: 0) {
                        replyPolicySection
                        reviewToggleRow
                        audienceSection
                        // Bottom padding so sticky button doesn't obscure last row
                        Color.clear.frame(height: 88)
                    }
                    .padding(.top, 8)
                }

                // ---- Sticky Done button ----
                doneButton
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCrossPostSheet) {
            ComposerCrossPostSheet(draft: $draft, isPresented: $showCrossPostSheet)
        }
        // VoiceOver announcement for the whole sheet
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Who can reply and quote, \(draft.replyPolicy.displayName) selected"
        )
    }

    // MARK: - Reply Policy Section

    private var replyPolicySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who can reply and quote")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(ComposerReplyPolicy.allCases, id: \.self) { policy in
                    RadioRow(
                        policy: policy,
                        isSelected: draft.replyPolicy == policy
                    ) {
                        withAnimation(Motion.adaptive(Motion.popToggle)) {
                            draft.replyPolicy = policy
                        }
                    }

                    if policy != ComposerReplyPolicy.allCases.last {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .amenCard(cornerRadius: 12, shadow: false)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Review & Approve Toggle Row

    private var reviewToggleRow: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review and approve replies")
                        .font(.body)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Text("Replies won't appear without your approval")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $draft.reviewAndApproveReplies)
                    .labelsHidden()
                    .tint(AmenTheme.Colors.amenBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .amenCard(cornerRadius: 12, shadow: false)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        // VoiceOver
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Review and approve replies")
        .accessibilityHint("Replies won't appear without your approval")
        .accessibilityValue(draft.reviewAndApproveReplies ? "on" : "off")
    }

    // MARK: - Audience Section

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Audience")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

            Button {
                showCrossPostSheet = true
            } label: {
                HStack {
                    Text("Also share on...")
                        .font(.body)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Spacer()

                    Text(crossPostSummary)
                        .font(.body)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .amenPress()
            .amenCard(cornerRadius: 12, shadow: false)
            .padding(.horizontal, 16)
            // VoiceOver
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Also share on")
            .accessibilityValue(crossPostSummary)
            .accessibilityHint("Double tap to choose cross-posting destinations")
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button {
            isPresented = false
        } label: {
            Text("Done")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .amenPress()
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background(
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityLabel("Done")
        .accessibilityHint("Closes this sheet and saves your settings")
    }

    // MARK: - Helpers

    /// Summary text for the cross-post row: "Off" if none enabled, else a comma-joined list.
    private var crossPostSummary: String {
        let enabled = draft.crossPostDestinations.filter(\.isEnabled).map(\.name)
        return enabled.isEmpty ? "Off" : enabled.joined(separator: ", ")
    }
}

// MARK: - RadioRow

/// Reusable radio-button row for ComposerReplyPolicy selection.
private struct RadioRow: View {

    let policy: ComposerReplyPolicy
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: policy.icon)
                    .font(.body)
                    .foregroundStyle(
                        isSelected
                            ? AmenTheme.Colors.amenBlue
                            : AmenTheme.Colors.textSecondary
                    )
                    .frame(width: 28, height: 28)

                Text(policy.displayName)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                radioIndicator
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver
        .accessibilityElement(children: .combine)
        .accessibilityLabel(policy.displayName)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var radioIndicator: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.textTertiary,
                    lineWidth: isSelected ? 0 : 1.5
                )
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(AmenTheme.Colors.amenBlue)
                    .frame(width: 22, height: 22)

                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
            }
        }
        .animation(Motion.adaptive(Motion.popToggle), value: isSelected)
    }
}

// MARK: - ComposerCrossPostSheet

/// Placeholder cross-post destination picker.
/// Each row toggles `isEnabled` on the matching CrossPostDestination in the draft.
/// Actual posting logic is deferred to a future integration milestone.
struct ComposerCrossPostSheet: View {

    @Binding var draft: ComposerDraft
    @Binding var isPresented: Bool

    // Default platforms seeded when none exist yet.
    private static let defaultDestinations: [CrossPostDestination] = [
        CrossPostDestination(id: UUID(), name: "Instagram",  isEnabled: false, iconName: "camera.fill"),
        CrossPostDestination(id: UUID(), name: "X (Twitter)", isEnabled: false, iconName: "xmark.circle.fill"),
        CrossPostDestination(id: UUID(), name: "Facebook",   isEnabled: false, iconName: "person.2.fill"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(destinationIndices, id: \.self) { index in
                        crossPostRow(index: index)
                    }
                } header: {
                    Text("Share your post to these platforms at the same time.")
                        .font(.footnote)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .textCase(nil)
                }

                Section {
                    Text("Cross-posting connects your ministry presence across platforms. Integration setup required in Settings.")
                        .font(.footnote)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Also Share On")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear(perform: seedDestinationsIfNeeded)
    }

    // MARK: - Private helpers

    /// Indices into draft.crossPostDestinations for ForEach binding.
    private var destinationIndices: [Int] {
        draft.crossPostDestinations.indices.map { $0 }
    }

    @ViewBuilder
    private func crossPostRow(index: Int) -> some View {
        let dest = draft.crossPostDestinations[index]
        Toggle(isOn: Binding(
            get: { draft.crossPostDestinations[index].isEnabled },
            set: { draft.crossPostDestinations[index].isEnabled = $0 }
        )) {
            Label {
                Text(dest.name)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            } icon: {
                Image(systemName: dest.iconName)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .tint(AmenTheme.Colors.amenBlue)
        .accessibilityLabel(dest.name)
        .accessibilityValue(dest.isEnabled ? "on" : "off")
    }

    /// Seeds the draft with default destinations if none have been set yet.
    private func seedDestinationsIfNeeded() {
        guard draft.crossPostDestinations.isEmpty else { return }
        draft.crossPostDestinations = Self.defaultDestinations
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Audience Sheet") {
    @Previewable @State var draft = ComposerDraft()
    @Previewable @State var presented = true

    Color(uiColor: .systemBackground)
        .sheet(isPresented: $presented) {
            ComposerAudienceSheet(draft: $draft, isPresented: $presented)
        }
}

#Preview("Cross-Post Sheet") {
    @Previewable @State var draft = ComposerDraft()
    @Previewable @State var presented = true

    Color(uiColor: .systemBackground)
        .sheet(isPresented: $presented) {
            ComposerCrossPostSheet(draft: $draft, isPresented: $presented)
        }
}
#endif
