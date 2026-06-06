// SafeSharePrompt.swift
// AMENAPP — Liquid Glass safety gate for the Berean "Share Safely" action.
//
// Signature (frozen):
//   SafeSharePrompt(payload: ShareDraft, onApprove: () -> Void, onCancel: () -> Void)
//
// States: .checking → .approved | .blocked | .error
// Fail-closed: content cannot be shared until moderation explicitly passes.

import SwiftUI
import FirebaseAuth

// MARK: - State machine

private enum ShareCheckState: Equatable {
    case checking
    case approved
    case blocked
    case error(String)
}

// MARK: - View

struct SafeSharePrompt: View {

    let payload: BereanShareDraft
    let onApprove: () -> Void
    let onCancel: () -> Void

    @State private var checkState: ShareCheckState = .checking
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ZStack {
                // Always solid white background — no blur behind safety content
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignTokens.spacingL) {
                        statusCard
                        if checkState == .approved || checkState == .blocked {
                            previewCard
                        }
                        actionArea
                    }
                    .padding(.horizontal, DesignTokens.spacingM)
                    .padding(.top, DesignTokens.spacingM)
                    .padding(.bottom, DesignTokens.spacingXL)
                }
            }
            .navigationTitle("Share Safely")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if checkState != .checking {
                        Button("Cancel") { onCancel() }
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            if reduceTransparency {
                Color(.systemBackground)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .task { await runModeration() }
    }

    // MARK: - Status card

    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: DesignTokens.spacingS) {
            switch checkState {
            case .checking:
                checkingContent
            case .approved:
                approvedContent
            case .blocked:
                blockedContent
            case .error(let msg):
                errorContent(message: msg)
            }
        }
        .padding(DesignTokens.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bereanLiquidGlass(cornerRadius: DesignTokens.radiusCard)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(.amenSpringStandard, value: checkState)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Checking state

    private var checkingContent: some View {
        HStack(spacing: DesignTokens.spacingM) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(DesignTokens.textSecondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text("Checking content for safety…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("This only takes a moment.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .accessibilityLabel("Checking content for safety")
    }

    // MARK: - Approved state

    private var approvedContent: some View {
        HStack(spacing: DesignTokens.spacingM) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text("Looks good")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Your content is ready to share.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
    }

    // MARK: - Blocked state

    private var blockedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            HStack(spacing: DesignTokens.spacingM) {
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                    Text("This content needs a review before sharing.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
            HStack(spacing: DesignTokens.spacingS) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textTertiary)
                Text("We keep this community safe for people of all ages.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .accessibilityLabel("Content blocked for safety. We keep this community safe for people of all ages.")
    }

    // MARK: - Error state

    private func errorContent(message: String) -> some View {
        HStack(spacing: DesignTokens.spacingM) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text("Could not complete safety check.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
    }

    // MARK: - Preview card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            HStack(spacing: DesignTokens.spacingS) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textTertiary)
                Text("Sharing to \(payload.destinationLabel)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            Text(payload.text)
                .font(.system(size: 15))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(DesignTokens.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bereanLiquidGlass(cornerRadius: DesignTokens.radiusCard)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.amenSpringStandard, value: checkState)
    }

    // MARK: - Action area

    @ViewBuilder
    private var actionArea: some View {
        switch checkState {
        case .checking:
            EmptyView()

        case .approved:
            VStack(spacing: DesignTokens.spacingS) {
                Button {
                    HapticManager.notification(type: .success)
                    onApprove()
                } label: {
                    Text("Share")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.radiusCapsule, style: .continuous)
                                .fill(Color.black)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm share to \(payload.destinationLabel)")

                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel and close")
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.amenSpringStandard, value: checkState)

        case .blocked:
            Button {
                onCancel()
            } label: {
                Text("Got it")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusCapsule, style: .continuous)
                            .fill(Color.black)
                    )
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.amenSpringStandard, value: checkState)

        case .error:
            VStack(spacing: DesignTokens.spacingS) {
                Button {
                    checkState = .checking
                    Task { await runModeration() }
                } label: {
                    Text("Try again")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.radiusCapsule, style: .continuous)
                                .fill(Color.black)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.amenSpringStandard, value: checkState)
        }
    }

    // MARK: - Moderation

    @MainActor
    private func runModeration() async {
        checkState = .checking
        let userId = Auth.auth().currentUser?.uid
        let req = BereanAIRequest(
            surface: .bereanChat,
            category: .safetyScreening,
            userInput: payload.text,
            userId: userId,
            allowCache: false,
            isPrivate: false
        )
        let result = await BereanCoreService.shared.process(req)
        let isBlocked = result.safetyFlags.contains { $0.actionRequired == .block }
        withAnimation(.amenSpringStandard) {
            if isBlocked {
                checkState = .blocked
                HapticManager.notification(type: .error)
            } else {
                checkState = .approved
            }
        }
    }
}

// MARK: - Preview

#Preview("Approved") {
    SafeSharePrompt(
        payload: BereanShareDraft(
            text: "I am so grateful for this community. Romans 8:28 says all things work together for good.",
            destinationLabel: "Community"
        ),
        onApprove: {},
        onCancel: {}
    )
}

#Preview("Blocked") {
    SafeSharePrompt(
        payload: BereanShareDraft(
            text: "Some content that requires review.",
            destinationLabel: "Community"
        ),
        onApprove: {},
        onCancel: {}
    )
}
