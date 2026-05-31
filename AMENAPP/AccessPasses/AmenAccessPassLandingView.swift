// AmenAccessPassLandingView.swift
// AMENAPP — Safe Access Pass Landing Screen
//
// Appears after scanning QR, tapping NFC, opening share link, or tapping invite.
// Never drops user directly into a chat. Always shows context and consent first.

import SwiftUI
import FirebaseAuth

struct AmenAccessPassLandingView: View {
    let accessPassId: String
    let token: String
    let preview: AmenAccessPassPreview?
    let error: AmenAccessPassError?
    let isResolving: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var acceptingAction: AmenAccessAction?
    @State private var isAccepting = false
    @State private var acceptError: String?
    @State private var showRequestMessageField = false
    @State private var requestMessage = ""
    @State private var acceptSucceeded = false
    @State private var acceptResponse: AmenAcceptAccessPassResponse?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            Group {
                if isResolving {
                    loadingState
                } else if let error {
                    errorState(error)
                } else if acceptSucceeded, let response = acceptResponse {
                    successState(response)
                } else if let preview {
                    contentState(preview)
                } else {
                    errorState(.invalidPass)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.2)
                .accessibilityLabel("Loading invite details")
            Text("Verifying invite...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorState(_ error: AmenAccessPassError) -> some View {
        VStack(spacing: 24) {
            Image(systemName: errorIcon(for: error))
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(error.userFacingTitle)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(error.errorDescription ?? "Something went wrong.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if error == .authRequired {
                Button("Sign In") {
                    AmenAccessPassDeepLinkRouter.shared.storePendingPassForAfterSignIn(
                        accessPassId: accessPassId, token: token
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Sign in to continue with this invite")
            }

            Button("Report a Problem") {}
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private func contentState(_ preview: AmenAccessPassPreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerSection(preview)

                Divider().padding(.vertical, 20)

                // Host info
                hostSection(preview)

                // Access status
                accessStatusSection(preview)

                // Safety warnings
                warningsSection(preview)

                // Community rules
                if let rules = preview.communityRulesSummary {
                    rulesSection(rules)
                }

                Divider().padding(.vertical, 20)

                // Actions
                actionsSection(preview)

                // Request message field
                if showRequestMessageField {
                    requestMessageSection
                }

                // Error
                if let err = acceptError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Footer
                footerSection
            }
            .padding(.horizontal)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }

    private func headerSection(_ preview: AmenAccessPassPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(inviteHeadline(for: preview))
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            if let subtitle = preview.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func hostSection(_ preview: AmenAccessPassPreview) -> some View {
        HStack(spacing: 10) {
            Image(systemName: hostIcon(for: preview.targetType))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let hostName = preview.verifiedHostName {
                    HStack(spacing: 4) {
                        Text("Hosted by \(hostName)")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if preview.verifiedHostBadge {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .accessibilityLabel("Verified host")
                        }
                    }
                }
                Text(preview.targetType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func accessStatusSection(_ preview: AmenAccessPassPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(preview.mode.accessStatusLabel, systemImage: modeIcon(for: preview.mode))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.top, 8)

            if preview.alreadyMember {
                Label("You're already a member", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if preview.existingRequestPending {
                Label("Your request is pending approval", systemImage: "clock.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func warningsSection(_ preview: AmenAccessPassPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let visibility = preview.visibilityWarning {
                warningPill(visibility, icon: "eye")
            }
            if let privacy = preview.privacyWarning {
                warningPill(privacy, icon: "lock")
            }
        }
        .padding(.top, preview.visibilityWarning != nil || preview.privacyWarning != nil ? 12 : 0)
    }

    private func warningPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(reduceTransparency
                    ? AnyShapeStyle(AmenTheme.Colors.backgroundElevated)
                    : AnyShapeStyle(.ultraThinMaterial))
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
    }

    private func rulesSection(_ rules: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Community Guidelines")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
            Text(rules)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func actionsSection(_ preview: AmenAccessPassPreview) -> some View {
        VStack(spacing: 12) {
            let primaryActions = preview.allowedActions.filter(\.isPrimary)
            let secondaryActions = preview.allowedActions.filter { !$0.isPrimary }

            ForEach(primaryActions, id: \.self) { action in
                primaryButton(for: action, preview: preview)
            }

            if !secondaryActions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(secondaryActions, id: \.self) { action in
                        secondaryButton(for: action, preview: preview)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func primaryButton(for action: AmenAccessAction, preview: AmenAccessPassPreview) -> some View {
        let label = preview.alreadyMember && action == .join ? "Open" :
                    preview.existingRequestPending && action == .request ? "Request Pending" :
                    action.label

        let isDisabled = (preview.alreadyMember && action == .join) ||
                         (preview.existingRequestPending && action == .request) ||
                         isAccepting

        return Button {
            handleAction(action, preview: preview)
        } label: {
            HStack {
                if isAccepting && acceptingAction == action {
                    ProgressView().tint(.white)
                }
                Text(label)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }

    private func secondaryButton(for action: AmenAccessAction, preview: AmenAccessPassPreview) -> some View {
        Button(action.label) {
            handleAction(action, preview: preview)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .accessibilityLabel(action.label)
    }

    private var requestMessageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message to host (optional)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Introduce yourself...", text: $requestMessage, axis: .vertical)
                .lineLimit(3...6)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(reduceTransparency
                            ? AnyShapeStyle(AmenTheme.Colors.backgroundElevated)
                            : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
        }
        .padding(.top, 12)
        .transition(.opacity)
    }

    // MARK: - Success State

    private func successState(_ response: AmenAcceptAccessPassResponse) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(successTitle(for: response.action))
                    .font(.title3)
                    .fontWeight(.semibold)

                if let msg = response.message {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button("Open") { dismiss() }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Open the space or group")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 16) {
            Button("Report") {}
            Button("Help") {}
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Handler

    private func handleAction(_ action: AmenAccessAction, preview: AmenAccessPassPreview) {
        if action == .request && !showRequestMessageField {
            withAnimation(reduceMotion ? nil : .easeInOut) {
                showRequestMessageField = true
            }
            return
        }

        acceptingAction = action
        isAccepting = true
        acceptError = nil

        Task {
            do {
                let response = try await AmenAccessPassService.shared.acceptAccessPass(
                    accessPassId: accessPassId,
                    token: token,
                    action: action,
                    requestMessage: requestMessage.isEmpty ? nil : requestMessage
                )
                self.acceptResponse = response
                self.acceptSucceeded = true
                self.isAccepting = false
                logAction(action, passId: accessPassId, targetType: preview.targetType)
            } catch let passError as AmenAccessPassError {
                self.acceptError = passError.errorDescription
                self.isAccepting = false
                AmenAccessPassAnalytics.shared.logDenied(passId: accessPassId, reason: passError.errorDescription ?? "unknown")
            } catch {
                self.acceptError = error.localizedDescription
                self.isAccepting = false
            }
        }
    }

    // MARK: - Helpers

    private func inviteHeadline(for preview: AmenAccessPassPreview) -> String {
        switch preview.targetType {
        case .church, .organization:
            return "Welcome to \(preview.title) on Amen"
        default:
            return "You're invited: \(preview.title)"
        }
    }

    private func hostIcon(for type: AmenAccessTargetType) -> String {
        switch type {
        case .church:       return "building.columns"
        case .organization: return "building.2"
        case .prayerRoom:   return "hands.sparkles"
        case .smallGroup:   return "person.3"
        case .event:        return "calendar"
        case .sermonNotes:  return "doc.text"
        default:            return "person.2"
        }
    }

    private func modeIcon(for mode: AmenAccessMode) -> String {
        switch mode {
        case .preview:   return "eye"
        case .join:      return "person.badge.plus"
        case .request:   return "paperplane"
        case .checkIn:   return "checkmark.circle"
        case .roleGated: return "lock.shield"
        }
    }

    private func errorIcon(for error: AmenAccessPassError) -> String {
        switch error {
        case .expiredPass:   return "clock.badge.xmark"
        case .revokedPass:   return "xmark.circle"
        case .authRequired:  return "person.crop.circle.badge.questionmark"
        case .rateLimited:   return "exclamationmark.triangle"
        default:             return "qrcode.viewfinder"
        }
    }

    private func successTitle(for action: AmenAccessAction) -> String {
        switch action {
        case .join:            return "You've joined!"
        case .request:         return "Request Sent"
        case .checkIn:         return "Checked In"
        case .followChurch:    return "Following"
        case .openSermonNotes: return "Opening Notes"
        case .askForPrayer:    return "Prayer Request Sent"
        default:               return "Done"
        }
    }

    private func logAction(_ action: AmenAccessAction, passId: String, targetType: AmenAccessTargetType) {
        switch action {
        case .join:            AmenAccessPassAnalytics.shared.logJoined(passId: passId, targetType: targetType)
        case .request:         AmenAccessPassAnalytics.shared.logRequested(passId: passId, targetType: targetType)
        case .checkIn:         AmenAccessPassAnalytics.shared.logCheckedIn(passId: passId, targetType: targetType)
        case .preview:         AmenAccessPassAnalytics.shared.logPreviewed(passId: passId, targetType: targetType)
        default:               break
        }
    }
}
