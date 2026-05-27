// AmenMessageSafetyWarningSheet.swift
// AMENAPP
//
// Pre-send safety warning flow. Presented when safeMessagingGateway detects risk.
// Risk is always server-evaluated — this view only presents the result.
//
// Severity levels:
//   .low    — soft inline nudge (banner above composer, no blocking)
//   .medium — bottom sheet with actions (send anyway / edit / block / report)
//   .high   — full-screen modal (sextortion, grooming, exploitation)
//
// Rules:
//   - Does NOT diagnose the sender
//   - Does NOT diagnose the recipient
//   - Does NOT expose private inference publicly
//   - Offers "Get Help" for crisis-level content, routing to SafetyTrustLayer
//   - "Send Anyway" always available for .low and .medium
//   - Gated by messagingRiskDetectionEnabled feature flag

import SwiftUI

// MARK: - Risk Models

struct MessagingRiskResult: Identifiable {
    let id = UUID()
    let severity: RiskSeverity
    let category: RiskCategory
    let messagePreview: String
    let suggestions: [String]
    let showGetHelp: Bool

    enum RiskSeverity {
        case low, medium, high
    }

    enum RiskCategory: String {
        case spam             = "spam"
        case scam             = "scam"
        case harassment       = "harassment"
        case manipulation     = "manipulation"
        case spiritualAbuse   = "spiritual_abuse"
        case groomingSignal   = "grooming_signal"
        case unknown          = "unknown"

        var displayTitle: String {
            switch self {
            case .spam:           return "This might look like spam"
            case .scam:           return "This message has scam-like patterns"
            case .harassment:     return "This message may come across as harsh"
            case .manipulation:   return "This message has manipulative patterns"
            case .spiritualAbuse: return "This could be hurtful in a spiritual context"
            case .groomingSignal: return "This message has concerning patterns"
            case .unknown:        return "Something seems off about this message"
            }
        }

        var displayBody: String {
            switch self {
            case .spam:
                return "Your message looks like a bulk or repeated send. Would you like to edit it first?"
            case .scam:
                return "Amen detected patterns similar to financial scams (urgent requests, unusual links, or prize claims). Recipients may feel uncomfortable."
            case .harassment:
                return "Your message may come across as threatening or unkind. Consider a calmer approach — relationships matter here."
            case .manipulation:
                return "Your message contains patterns that could feel controlling or coercive. Amen encourages honest, respectful communication."
            case .spiritualAbuse:
                return "Using faith or scripture to pressure or control someone can cause lasting harm. Please reconsider the framing."
            case .groomingSignal:
                return "This message has patterns that raise serious concerns. Please review before sending."
            case .unknown:
                return "Amen flagged this message. Review it before sending."
            }
        }

        var icon: String {
            switch self {
            case .spam:           return "envelope.badge.fill"
            case .scam:           return "exclamationmark.triangle.fill"
            case .harassment:     return "hand.raised.fill"
            case .manipulation:   return "person.fill.questionmark"
            case .spiritualAbuse: return "cross.circle.fill"
            case .groomingSignal: return "shield.lefthalf.filled.slash"
            case .unknown:        return "questionmark.circle.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .spam:                     return .orange
            case .scam, .manipulation:      return .red
            case .harassment:               return .orange
            case .spiritualAbuse:           return .purple
            case .groomingSignal:           return .red
            case .unknown:                  return .yellow
            }
        }
    }
}

// MARK: - Low Severity: Inline Nudge

struct MessagingRiskNudgeBanner: View {
    let risk: MessagingRiskResult
    let onDismiss: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: risk.category.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(risk.category.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(risk.category.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let suggestion = risk.suggestions.first {
                    Text(suggestion)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Button("Edit message", action: onEdit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(risk.category.accentColor)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss warning")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(risk.category.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(risk.category.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(risk.category.displayTitle). \(risk.suggestions.first ?? "")")
    }
}

// MARK: - Medium Severity: Bottom Sheet

struct MessagingRiskWarningSheet: View {
    let risk: MessagingRiskResult
    let onSendAnyway: () -> Void
    let onEdit: () -> Void
    let onBlockAndReport: () -> Void
    let onGetHelp: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.separator))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Icon + title
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(risk.category.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: risk.category.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(risk.category.accentColor)
                }
                .accessibilityHidden(true)

                Text(risk.category.displayTitle)
                    .font(.system(size: 18, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(risk.category.displayBody)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            // Suggestions
            if !risk.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    ForEach(risk.suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(risk.category.accentColor)
                                .padding(.top, 2)
                                .accessibilityHidden(true)
                            Text(suggestion)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 4)
            }

            Spacer(minLength: 24)

            // Actions
            VStack(spacing: 10) {
                Button(action: onEdit) {
                    Text("Edit Message")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.black))
                }
                .accessibilityLabel("Edit your message before sending")

                Button(action: onSendAnyway) {
                    Text("Send Anyway")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Send message despite warning")

                if risk.showGetHelp {
                    Button(action: onGetHelp) {
                        Label("Get Help", systemImage: "heart.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.purple)
                    }
                    .accessibilityLabel("Get help or learn about safe messaging")
                }

                Button(action: onBlockAndReport) {
                    Text("Block & Report")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Block this person and report the message")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - High Severity: Blocking Modal

struct MessagingRiskBlockingAlert: View {
    let risk: MessagingRiskResult
    let onBlockAndReport: () -> Void
    let onGetHelp: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "shield.slash.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Amen has detected a serious concern")
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(risk.category.displayBody)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: onBlockAndReport) {
                        Text("Block & Report")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.red))
                    }

                    Button(action: onGetHelp) {
                        Label("Get Help", systemImage: "heart.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.purple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.purple.opacity(0.1)))
                    }

                    Button(action: onDismiss) {
                        Text("Go Back")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Presenter Modifier

/// Attaches the correct risk warning UI based on severity.
/// Usage: `.messagingRiskWarning(risk: $riskResult, onSend: { ... }, onEdit: { ... })`
struct MessagingRiskWarningModifier: ViewModifier {
    @Binding var risk: MessagingRiskResult?
    let onSendAnyway: () -> Void
    let onEdit: () -> Void
    let onBlockAndReport: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: {
                        guard let r = risk else { return false }
                        return r.severity == .medium
                    },
                    set: { if !$0 { risk = nil } }
                )
            ) {
                if let r = risk {
                    MessagingRiskWarningSheet(
                        risk: r,
                        onSendAnyway: {
                            risk = nil
                            onSendAnyway()
                        },
                        onEdit: {
                            risk = nil
                            onEdit()
                        },
                        onBlockAndReport: {
                            risk = nil
                            onBlockAndReport()
                        },
                        onGetHelp: { risk = nil }
                    )
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: {
                        guard let r = risk else { return false }
                        return r.severity == .high
                    },
                    set: { if !$0 { risk = nil } }
                )
            ) {
                if let r = risk {
                    MessagingRiskBlockingAlert(
                        risk: r,
                        onBlockAndReport: {
                            risk = nil
                            onBlockAndReport()
                        },
                        onGetHelp: { risk = nil },
                        onDismiss: { risk = nil }
                    )
                }
            }
    }
}

extension View {
    func messagingRiskWarning(
        risk: Binding<MessagingRiskResult?>,
        onSendAnyway: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onBlockAndReport: @escaping () -> Void
    ) -> some View {
        modifier(MessagingRiskWarningModifier(
            risk: risk,
            onSendAnyway: onSendAnyway,
            onEdit: onEdit,
            onBlockAndReport: onBlockAndReport
        ))
    }
}
