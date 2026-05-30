// ComposerAudienceSheet.swift
// AMENAPP — SocialLayer
//
// Audience & reply controls bottom sheet for the AMEN social composer.
// Controls: who can see a post, who can reply, review-&-approve toggle,
// and cross-post destination stubs (future feature).
//
// ─────────────────────────────────────────────────────────────────────
// INTEGRATION NOTE:
//   In CreatePostView (or wherever the composer is hosted), add:
//
//   @State private var showAudienceSheet = false
//   @State private var audienceDraft: ComposerAudience = .everyone
//   @State private var replyPolicyDraft: ComposerReplyPolicy = .anyone
//   @State private var reviewAndApproveDraft = false
//   @State private var crossPostDraft: [CrossPostDestination] = [
//       CrossPostDestination(name: "Twitter/X",   isEnabled: false, iconName: "xmark.circle"),
//       CrossPostDestination(name: "Facebook",     isEnabled: false, iconName: "f.circle"),
//       CrossPostDestination(name: "Instagram",    isEnabled: false, iconName: "camera.circle"),
//   ]
//
//   Then attach the sheet:
//   .sheet(isPresented: $showAudienceSheet) {
//       ComposerAudienceSheet(
//           audience:               $audienceDraft,
//           replyPolicy:            $replyPolicyDraft,
//           reviewAndApprove:       $reviewAndApproveDraft,
//           crossPostDestinations:  $crossPostDraft,
//           onDone: { showAudienceSheet = false }
//       )
//   }
//
//   When the user taps Done, copy the draft values into your ComposerDraft:
//   draft.audience               = audienceDraft
//   draft.replyPolicy            = replyPolicyDraft
//   draft.reviewAndApproveReplies = reviewAndApproveDraft
//   draft.crossPostDestinations  = crossPostDraft
// ─────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - ComposerAudienceSheet

struct ComposerAudienceSheet: View {

    @Binding var audience: ComposerAudience
    @Binding var replyPolicy: ComposerReplyPolicy
    @Binding var reviewAndApprove: Bool
    @Binding var crossPostDestinations: [CrossPostDestination]
    var onDone: () -> Void

    // Pre-populate cross-post destinations the first time the sheet appears
    // if the caller passed an empty array (convenience fallback).
    private let defaultDestinations: [CrossPostDestination] = [
        CrossPostDestination(name: "Twitter/X",   isEnabled: false, iconName: "xmark.circle"),
        CrossPostDestination(name: "Facebook",     isEnabled: false, iconName: "f.circle"),
        CrossPostDestination(name: "Instagram",    isEnabled: false, iconName: "camera.circle"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    audienceSection
                    sectionDivider
                    replyPolicySection
                    if replyPolicy != .anyone {
                        sectionDivider
                        reviewAndApproveSection
                    }
                    sectionDivider
                    crossPostSection
                    // Bottom breathing room above home indicator
                    Spacer().frame(height: 32)
                }
            }
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    dragHandleHeader
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    doneButton
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(32)
        .onAppear {
            if crossPostDestinations.isEmpty {
                crossPostDestinations = defaultDestinations
            }
        }
    }

    // MARK: - Drag handle (rendered inside the toolbar principal slot)

    private var dragHandleHeader: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color(.separator))
                .frame(width: 36, height: 4)
                .padding(.top, 4)
            Text("Audience & Replies")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
    }

    // MARK: - Done button

    private var doneButton: some View {
        Button("Done") {
            onDone()
        }
        .fontWeight(.semibold)
        .foregroundStyle(AmenTheme.Colors.amenBlue)
        .accessibilityHint("Save audience and reply settings and close this sheet")
    }

    // MARK: - Section divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(AmenTheme.Colors.separatorSubtle)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    // MARK: - "Who can see this?" section

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Who can see this?")
            ForEach(ComposerAudience.allCases, id: \.self) { option in
                AudiencePickerRow(
                    icon: option.icon,
                    label: option.displayName,
                    isSelected: audience == option
                ) {
                    withAnimation(Motion.springPress) {
                        audience = option
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - "Who can reply?" section

    private var replyPolicySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Who can reply?")
            ForEach(ComposerReplyPolicy.allCases, id: \.self) { option in
                AudiencePickerRow(
                    icon: option.icon,
                    label: option.displayName,
                    isSelected: replyPolicy == option
                ) {
                    withAnimation(Motion.springPress) {
                        replyPolicy = option
                        // Reset review toggle if opening to anyone
                        if option == .anyone {
                            reviewAndApprove = false
                        }
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - "Review & approve replies" section

    private var reviewAndApproveSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Moderation")
            HStack(spacing: 12) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(AmenTheme.Colors.amenBlue.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review & approve replies")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("Replies won't be visible until you approve them")
                        .font(.system(size: 12))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $reviewAndApprove)
                    .labelsHidden()
                    .tint(AmenTheme.Colors.amenBlue)
                    .accessibilityLabel("Review and approve replies")
                    .accessibilityHint("When on, replies won't appear until you approve them")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(Motion.springPress) {
                    reviewAndApprove.toggle()
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - "Also share on…" cross-post section

    private var crossPostSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Also share on\u{2026}")
            ForEach($crossPostDestinations) { $dest in
                CrossPostRow(destination: $dest)
            }
            // Informational note
            Text("Cross-posting is a future feature. Toggling will not send anything yet.")
                .font(.system(size: 11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
        .padding(.top, 8)
    }

    // MARK: - Section header helper

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .default))
            .tracking(0.6)
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - AudiencePickerRow

/// A single 52pt-tall selectable row: icon circle + label + optional checkmark.
private struct AudiencePickerRow: View {

    let icon: String
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon circle — 28pt, amenBlue tinted
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? AmenTheme.Colors.amenBlue.opacity(0.15)
                                : AmenTheme.Colors.textSecondary.opacity(0.08)
                        )
                        .frame(width: 28, height: 28)
                        .animation(Motion.springPress, value: isSelected)

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? AmenTheme.Colors.amenBlue
                                : AmenTheme.Colors.textSecondary
                        )
                        .animation(Motion.springPress, value: isSelected)
                }

                // Label
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Checkmark — only shown when selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .background(
                isPressed
                    ? AmenTheme.Colors.pressedOverlay
                    : Color.clear
            )
            .animation(Motion.springPress, value: isPressed)
        }
        .buttonStyle(AmenPressStyle(scale: 0.985))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - CrossPostRow

/// A single cross-post destination row: icon circle + name + "Coming Soon" badge + toggle.
private struct CrossPostRow: View {

    @Binding var destination: CrossPostDestination

    var body: some View {
        HStack(spacing: 12) {
            // Destination icon circle
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.textSecondary.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: destination.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            // Name
            Text(destination.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            // "Coming Soon" badge
            ComingSoonBadge()

            Spacer()

            // Toggle (UI-only stub — no API call)
            Toggle("", isOn: $destination.isEnabled)
                .labelsHidden()
                .tint(AmenTheme.Colors.amenBlue)
                .accessibilityLabel("Share on \(destination.name)")
                .accessibilityHint("Coming soon — toggling will not post yet")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

// MARK: - ComingSoonBadge

private struct ComingSoonBadge: View {
    var body: some View {
        Text("Coming Soon")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AmenTheme.Colors.amenBlue)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.amenBlue.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(AmenTheme.Colors.amenBlue.opacity(0.25), lineWidth: 0.5)
            )
            .accessibilityLabel("Coming soon")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ComposerAudienceSheet") {
    @Previewable @State var audience: ComposerAudience = .everyone
    @Previewable @State var replyPolicy: ComposerReplyPolicy = .anyone
    @Previewable @State var reviewAndApprove = false
    @Previewable @State var crossPostDestinations: [CrossPostDestination] = []

    Color(.systemBackground)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ComposerAudienceSheet(
                audience: $audience,
                replyPolicy: $replyPolicy,
                reviewAndApprove: $reviewAndApprove,
                crossPostDestinations: $crossPostDestinations,
                onDone: {}
            )
        }
}
#endif
