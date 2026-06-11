// BereanSafetyOverlayView.swift
// AMENAPP
//
// Liquid Glass safety overlay — appears above keyboard/composer when risk is detected.
// Non-modal, non-intrusive. Smooth glass pill that expands into an action sheet.
// Does NOT modify any existing PostCard, message bubble, or conversation view.

import SwiftUI
import FirebaseAuth

// MARK: - Main Overlay View

struct BereanSafetyOverlayView: View {
    let conversationId: String

    @ObservedObject var safetyService   = BereanConversationSafetyService.shared
    @ObservedObject var recipientService = BereanRecipientProtectionService.shared

    @State private var isExpanded: Bool = false
    @State private var showBoundaryPicker: Bool = false

    var body: some View {
        VStack(spacing: 8) {

            // Media consent cards
            ForEach(recipientService.pendingMediaRequests) { request in
                BereanMediaConsentCard(request: request)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Safety shield pill / sheet
            if let intervention = safetyService.activeIntervention {
                if isExpanded {
                    BereanSafetySheet(
                        intervention: intervention,
                        conversationId: conversationId,
                        isExpanded: $isExpanded,
                        showBoundaryPicker: $showBoundaryPicker
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    BereanSafetyShieldPill(
                        intervention: intervention,
                        isExpanded: $isExpanded
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Boundary message picker (shown inline below the sheet)
            if showBoundaryPicker {
                BereanBoundaryMessagePicker(
                    conversationId: conversationId,
                    showBoundaryPicker: $showBoundaryPicker
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: safetyService.activeIntervention != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)
        .animation(.easeInOut(duration: 0.25), value: showBoundaryPicker)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: recipientService.pendingMediaRequests.count)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - Shield Pill

struct BereanSafetyShieldPill: View {
    let intervention: SafetyIntervention
    @Binding var isExpanded: Bool

    private var symbolName: String {
        intervention.level >= .elevated ? "exclamationmark.shield.fill" : "shield.fill"
    }

    private var accentColor: Color {
        switch intervention.level {
        case .safe:     return .green
        case .mild:     return Color(red: 0.35, green: 0.6, blue: 1.0)
        case .moderate: return Color(red: 1.0,  green: 0.75, blue: 0.2)
        case .elevated: return Color(red: 1.0,  green: 0.45, blue: 0.2)
        case .critical: return Color(red: 0.9,  green: 0.2,  blue: 0.2)
        }
    }

    var body: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundColor(accentColor)
                    .font(.systemScaled(15, weight: .semibold))

                Text(intervention.message)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                Image(systemName: "chevron.up")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
                }
            )
            .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safety Sheet (inline, not modal)

struct BereanSafetySheet: View {
    let intervention: SafetyIntervention
    let conversationId: String
    @Binding var isExpanded: Bool
    @Binding var showBoundaryPicker: Bool

    private var accentColor: Color {
        switch intervention.level {
        case .safe:     return .green
        case .mild:     return Color(red: 0.35, green: 0.6, blue: 1.0)
        case .moderate: return Color(red: 1.0,  green: 0.75, blue: 0.2)
        case .elevated: return Color(red: 1.0,  green: 0.45, blue: 0.2)
        case .critical: return Color(red: 0.9,  green: 0.2,  blue: 0.2)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header row
            HStack(spacing: 10) {
                Image(systemName: intervention.level >= .elevated
                      ? "exclamationmark.shield.fill" : "shield.fill")
                    .foregroundColor(accentColor)
                    .font(.systemScaled(22, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(intervention.message)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundColor(.primary)

                    if let scripture = intervention.scripture {
                        Text(scripture)
                            .font(.systemScaled(12, weight: .regular))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                Spacer()

                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Option buttons
            VStack(spacing: 8) {
                ForEach(intervention.options) { option in
                    SafetyOptionButton(
                        option: option,
                        conversationId: conversationId,
                        isExpanded: $isExpanded,
                        showBoundaryPicker: $showBoundaryPicker
                    )
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.09), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Safety Option Button

private struct SafetyOptionButton: View {
    let option: SafetyIntervention.SafetyOption
    let conversationId: String
    @Binding var isExpanded: Bool
    @Binding var showBoundaryPicker: Bool

    var body: some View {
        Button {
            handleAction(option.action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 20)

                Text(option.title)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                    Capsule()
                        .strokeBorder(Color(white: 0.85), lineWidth: 0.5)
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func handleAction(_ action: SafetyIntervention.SafetyOption.SafetyAction) {
        switch action {
        case .dismiss:
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                BereanConversationSafetyService.shared.dismissIntervention()
                isExpanded = false
            }

        case .redirectConversation:
            // SECURITY FIX (MEDIUM 2026-06-11): Use Motion.adaptive to respect reduce-motion.
            // The .dismiss case above already uses Motion.adaptive — these five cases were missed.
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                BereanConversationSafetyService.shared.dismissIntervention()
                isExpanded = false
            }
            dlog("[BereanOverlay] redirect conversation selected conv=\(conversationId)")

        case .pauseChat(let minutes):
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                BereanConversationSafetyService.shared.dismissIntervention()
                isExpanded = false
            }
            dlog("[BereanOverlay] pause chat \(minutes)min conv=\(conversationId)")

        case .sendBoundaryMessage:
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                showBoundaryPicker = true
                isExpanded = false
            }

        case .continueLogged:
            Task {
                await BereanAccountabilityService.shared.recordSignal(.flaggedConversation)
            }
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                BereanConversationSafetyService.shared.dismissIntervention()
                isExpanded = false
            }
            dlog("[BereanOverlay] continuing logged conv=\(conversationId)")

        case .restrictSender:
            Task {
                await BereanRecipientProtectionService.shared.quietlyRestrict(
                    senderId: "",
                    in: conversationId
                )
            }
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                BereanConversationSafetyService.shared.dismissIntervention()
                isExpanded = false
            }
            dlog("[BereanOverlay] restrict sender conv=\(conversationId)")
        }
    }
}

// MARK: - Boundary Message Picker

struct BereanBoundaryMessagePicker: View {
    let conversationId: String
    @Binding var showBoundaryPicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a boundary message")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(BoundaryMessage.presets) { preset in
                BoundaryPresetRow(preset: preset, conversationId: conversationId) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showBoundaryPicker = false
                    }
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
    }
}

private struct BoundaryPresetRow: View {
    let preset: BoundaryMessage
    let conversationId: String
    let onSent: () -> Void

    @State private var isSending: Bool = false

    var body: some View {
        Button {
            guard !isSending else { return }
            isSending = true
            Task {
                await BereanRecipientProtectionService.shared.sendBoundaryMessage(preset, in: conversationId)
                BereanConversationSafetyService.shared.dismissIntervention()
                onSent()
                dlog("[BereanOverlay] boundary message sent: \(preset.text)")
            }
        } label: {
            HStack {
                Text(preset.text)
                    .font(.systemScaled(13, weight: .regular))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .fill(Color.white.opacity(0.45))
                    Capsule()
                        .strokeBorder(Color(white: 0.85), lineWidth: 0.5)
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Conflict Rewrite Bar

struct BereanConflictRewriteBar: View {
    let originalText: String
    let rewrittenText: String
    let onUseRewrite: (String) -> Void
    let onSendAsIs: () -> Void
    let onEdit: (String) -> Void

    @State private var isVisible: Bool = true

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 10) {
                // Scripture header
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.systemScaled(11))
                        .foregroundColor(.secondary)
                    Text("A gentle answer turns away wrath. (Proverbs 15:1)")
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundColor(.secondary)
                        .italic()
                }

                // Rewrite suggestion
                Text(rewrittenText)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(white: 0.96))
                    )

                // Action buttons
                HStack(spacing: 8) {
                    ConflictRewriteActionButton(title: "Use this instead", icon: "checkmark.circle.fill") {
                        onUseRewrite(rewrittenText)
                        withAnimation { isVisible = false }
                    }

                    ConflictRewriteActionButton(title: "Send as is", icon: "arrow.right.circle") {
                        onSendAsIs()
                        withAnimation { isVisible = false }
                    }

                    ConflictRewriteActionButton(title: "Edit", icon: "pencil.circle") {
                        onEdit(rewrittenText)
                        withAnimation { isVisible = false }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
                }
            )
            .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isVisible)
        }
    }
}

private struct ConflictRewriteActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(title)
                    .font(.systemScaled(12, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.white.opacity(0.5))
                    Capsule().strokeBorder(Color(white: 0.85), lineWidth: 0.5)
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Media Consent Card

struct BereanMediaConsentCard: View {
    let request: MediaConsentRequest

    var body: some View {
        VStack(spacing: 10) {
            // Blurred placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.88))
                    .frame(height: 80)

                VStack(spacing: 4) {
                    Image(systemName: "photo.fill")
                        .font(.systemScaled(22))
                        .foregroundColor(.secondary)
                    Text("Sensitive image — tap to view")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                MediaConsentButton(title: "View", icon: "eye.fill", style: .primary) {
                    BereanRecipientProtectionService.shared.approveMedia(request.id)
                }

                MediaConsentButton(title: "Decline", icon: "xmark.circle", style: .secondary) {
                    BereanRecipientProtectionService.shared.declineMedia(request.id)
                }

                MediaConsentButton(title: "Always require approval", icon: "lock.shield", style: .secondary) {
                    BereanRecipientProtectionService.shared.setAlwaysRequireApproval(
                        from: request.senderId,
                        in: ""
                    )
                    BereanRecipientProtectionService.shared.declineMedia(request.id)
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(white: 0.88), lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
    }
}

private struct MediaConsentButton: View {
    enum Style { case primary, secondary }

    let title: String
    let icon: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(title)
                    .font(.systemScaled(12, weight: .medium))
            }
            .foregroundColor(style == .primary ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Group {
                    if style == .primary {
                        Capsule().fill(Color.accentColor)
                    } else {
                        ZStack {
                            Capsule().fill(.ultraThinMaterial)
                            Capsule().fill(Color.white.opacity(0.5))
                            Capsule().strokeBorder(Color(white: 0.85), lineWidth: 0.5)
                        }
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

struct BereanSafetyOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            BereanSafetyOverlayView(conversationId: "preview_conv_001")
        }
        .background(Color(white: 0.95))
        .previewDisplayName("Safety Overlay")
    }
}

struct BereanConflictRewriteBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            BereanConflictRewriteBar(
                originalText: "you're actually stupid",
                rewrittenText: "I disagree with you, but I want to understand your perspective.",
                onUseRewrite: { _ in },
                onSendAsIs: {},
                onEdit: { _ in }
            )
        }
        .background(Color(white: 0.95))
        .previewDisplayName("Conflict Rewrite Bar")
    }
}

struct BereanMediaConsentCard_Previews: PreviewProvider {
    static var previews: some View {
        BereanMediaConsentCard(
            request: MediaConsentRequest(
                id: "preview_media_001",
                senderId: "user_abc",
                mediaType: "image",
                riskLevel: 0.6,
                isBlurred: true,
                timestamp: Date()
            )
        )
        .padding()
        .background(Color(white: 0.95))
        .previewDisplayName("Media Consent Card")
    }
}
