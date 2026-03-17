//
//  MessageSafetyUI.swift
//  AMENAPP
//
//  Safety UI components for messaging.
//  These views surface gateway decisions to users without being alarmist —
//  clear, calm, and actionable.
//

import SwiftUI
import FirebaseAuth

// MARK: - Safety Warning Banner (shown to recipient)

/// Banner shown to the recipient when a message is delivered with a `warnRecipient` decision.
/// Sits above the message bubble. Doesn't change the message bubble itself.
struct MessageSafetyWarningBanner: View {
    let signals: [SafetySignal]
    let onReport: () -> Void
    let onBlock: () -> Void
    @State private var isExpanded = false

    private var primaryDescription: String {
        let highestWeight = signals.max(by: { $0.weight < $1.weight })
        switch highestWeight {
        // ── Highest-risk signals — explicit, actionable messages ──────────────
        case .groomingIntent:
            return "This message contains language patterns associated with grooming. If you feel unsafe, block this person and report immediately."
        case .sexualSolicitation:
            return "This message may contain sexual solicitation. This violates our Community Guidelines. You can block and report."
        case .ageMentionWithSexual:
            return "We detected content that may involve minors in an inappropriate context. This has been flagged for urgent review."
        case .isolationLanguage:
            return "This message uses language designed to isolate you (e.g. \"don't tell anyone\"). Trust your instincts — you can block and report."
        // ── Financial / scam signals ──────────────────────────────────────────
        case .moneyTransferRequest, .giftCardRequest:
            return "This person is asking you to send money or gift cards. This is a common scam pattern."
        case .modelingScam:
            return "This message contains an unsolicited offer that may be a scam."
        // ── Contact / location signals ────────────────────────────────────────
        case .contactExchange:
            return "This message contains personal contact information."
        case .locationRequest:
            return "This person is asking for your location."
        case .offPlatformMigration:
            return "This person is asking you to move your conversation to another app."
        case .externalLinkExchange:
            return "This message contains an external link. Open links only from people you trust."
        // ── Social pressure signals ───────────────────────────────────────────
        case .loveBombing:
            return "This message uses unusually intense language from someone you may not know well."
        default:
            return "We flagged something in this message. You can report or block if you feel uncomfortable."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(primaryDescription)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded {
                HStack(spacing: 10) {
                    Button(action: onReport) {
                        Label("Report", systemImage: "flag.fill")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.1))
                            )
                    }

                    Button(action: onBlock) {
                        Label("Block", systemImage: "hand.raised.fill")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                            )
                    }

                    Spacer()

                    Text("Learn more")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }
}

// MARK: - Held Message Indicator (shown to sender)

/// Replaces the normal "Sending…" state for messages that are held for review.
/// Shown in the sender's own message bubble area.
struct HeldMessageIndicator: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

                Image(systemName: "clock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Message under review")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.primary)

                Text("We're checking this before delivery. This usually takes a few seconds.")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.yellow.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear { pulse = true }
    }
}

// MARK: - Strike Notice (shown to sender after block)

/// Inline notice shown at the bottom of the input area after a message is blocked.
/// Does not use a sheet or alert — stays in context.
///
/// Enhancements:
///   - Liquid Glass background (ultra-thin material + colored overlay)
///   - Spring bounce entrance on appear
///   - Auto-dismiss after 6 s with a shrinking progress bar
///   - Optional "Follow them first" CTA for the mutual-follow gate case (strike 1)
struct StrikeNoticeView: View {
    let strikeCount: Int
    let reason: String
    let onDismiss: () -> Void
    /// Pass this closure when the block reason is a mutual-follow gate so the
    /// user can send a follow request directly from the notice.
    var onFollowThem: (() -> Void)? = nil
    /// Bind to the parent's loading state so the button shows a spinner while the follow is in-flight.
    var isFollowLoading: Bool = false

    // ── Auto-dismiss ─────────────────────────────────────────────────────────
    private let autoDismissAfter: Double = 6.0
    @State private var progress: Double = 1.0   // 1 → 0 over autoDismissAfter seconds
    @State private var dismissTask: Task<Void, Never>? = nil

    // ── Entrance animation ───────────────────────────────────────────────────
    @State private var appeared = false

    private var severity: Color {
        switch strikeCount {
        case 1: return .orange
        case 2: return Color(red: 0.9, green: 0.4, blue: 0.0)
        default: return .red
        }
    }

    private var icon: String {
        strikeCount >= 3 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
    }

    private var title: String {
        switch strikeCount {
        case 1: return "Message not sent"
        case 2: return "Second warning"
        default: return "Account restricted"
        }
    }

    private var detail: String {
        switch strikeCount {
        case 1:
            return "\(reason). This is your first warning. Further violations may restrict your account."
        case 2:
            return "\(reason). Your messaging is temporarily limited for 24 hours."
        default:
            return "Your account has been temporarily restricted due to repeated safety violations. Contact support to appeal."
        }
    }

    /// Show the follow CTA only on strike 1 when a follow-action handler is provided.
    private var showFollowCTA: Bool { strikeCount == 1 && onFollowThem != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Main row ─────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(severity)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(severity)

                    Text(detail)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // ── Follow CTA ────────────────────────────────────────────
                    if showFollowCTA {
                        Button(action: {
                            guard !isFollowLoading else { return }
                            cancelAutoDismiss()
                            onFollowThem?()
                            // Dismiss is handled by the parent after async follow completes
                        }) {
                            Group {
                                if isFollowLoading {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                            .scaleEffect(0.75)
                                        Text("Following…")
                                            .font(.custom("OpenSans-SemiBold", size: 12))
                                            .foregroundStyle(.white)
                                    }
                                } else {
                                    Label("Follow them first", systemImage: "person.badge.plus")
                                        .font(.custom("OpenSans-SemiBold", size: 12))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isFollowLoading ? severity.opacity(0.6) : severity)
                            )
                        }
                        .disabled(isFollowLoading)
                        .padding(.top, 6)
                    }
                }

                Spacer()

                Button(action: {
                    cancelAutoDismiss()
                    withAnimation(.spring(response: 0.3)) { onDismiss() }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
            .padding(12)

            // ── Auto-dismiss progress bar ─────────────────────────────────────
            GeometryReader { geo in
                severity
                    .opacity(0.55)
                    .frame(width: geo.size.width * progress, height: 2)
                    .animation(.linear(duration: autoDismissAfter), value: progress)
            }
            .frame(height: 2)
        }
        // Liquid Glass background: ultra-thin material + faint severity tint + border
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14)
                    .fill(severity.opacity(0.06))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(severity.opacity(0.25), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 4)
        // Spring entrance: slide up + fade in
        .offset(y: appeared ? 0 : 20)
        .opacity(appeared ? 1 : 0)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                appeared = true
            }
            startAutoDismiss()
        }
        .onDisappear {
            cancelAutoDismiss()
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func startAutoDismiss() {
        // Kick off the shrinking bar immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            progress = 0.0
        }
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.3)) { onDismiss() }
            }
        }
    }

    private func cancelAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}

// MARK: - Account Frozen Notice

/// Full-screen-adjacent banner shown when account is frozen and user tries to send.
struct AccountFrozenNoticeView: View {
    let reason: String
    let onContactSupport: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Messaging restricted")
                .font(.custom("OpenSans-Bold", size: 17))
                .foregroundStyle(.primary)

            Text(reason)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onContactSupport) {
                Text("Contact Support")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .padding()
    }
}

// MARK: - Self-Harm Crisis Interstitial

/// Shown when a self-harm signal is detected — shown to SENDER before message is sent.
/// Crisis resources are surfaced before blocking the message.
struct SelfHarmCrisisInterstitial: View {
    let onSendAnyway: () -> Void   // Allow send after showing resources
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.clipboard.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("We're here for you")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)

            Text("It looks like you may be going through something difficult. You're not alone.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 10) {
                CrisisResourceButton(
                    icon: "phone.fill",
                    label: "988 Suicide & Crisis Lifeline",
                    detail: "Call or text 988",
                    color: .green
                )

                CrisisResourceButton(
                    icon: "message.fill",
                    label: "Crisis Text Line",
                    detail: "Text HOME to 741741",
                    color: .blue
                )

                CrisisResourceButton(
                    icon: "hands.sparkles.fill",
                    label: "Prayer & Support",
                    detail: "Connect with your community",
                    color: Color.accentColor
                )
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal, 24)

            HStack(spacing: 16) {
                Button(action: onClose) {
                    Text("Close")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }

                Button(action: onSendAnyway) {
                    Text("Send message")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray5))
                        )
                }
            }
        }
        .padding(24)
    }
}

private struct CrisisResourceButton: View {
    let icon: String
    let label: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(color.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}
