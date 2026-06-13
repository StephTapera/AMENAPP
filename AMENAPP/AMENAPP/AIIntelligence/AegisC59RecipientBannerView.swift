// AegisC59RecipientBannerView.swift
// AMEN — Aegis C59 Recipient-Facing Banner
//
// Shown ONLY to the message recipient when spiritual abuse patterns are detected.
// Sender NEVER sees this — from the sender's perspective, nothing unusual occurs.
//
// Design:
//   - Amber (#FFF3CD) background — warm, not alarming. Not red.
//   - Informational, not accusatory. Preserves recipient agency.
//   - Dismissible with a single tap. No confirmation required.
//   - Resource links: DV Hotline, Focus on the Family, church counseling.
//
// Flag gate: AMENFeatureFlags.shared.aegisC59

import SwiftUI

// MARK: - Banner View

struct AegisC59RecipientBannerView: View {

    let signal: AegisC59Signal
    var onDismiss: () -> Void

    @State private var appearedScale: Double = 0.96
    @State private var appearedOpacity: Double = 0

    var body: some View {
        guard AMENFeatureFlags.shared.aegisC59 else { return AnyView(EmptyView()) }
        return AnyView(banner)
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            messageText
            resourceLinks
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "FFF3CD"))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "FFCA28").opacity(0.5), lineWidth: 1)
        )
        .scaleEffect(appearedScale)
        .opacity(appearedOpacity)
        .onAppear {
            withAnimation(
                .spring(response: 0.45, dampingFraction: 0.72)
                .delay(0.05)
            ) {
                appearedScale = 1.0
                appearedOpacity = 1.0
            }
            // Gentle pulse on the shield icon is handled inside headerRow.
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Safety information banner")
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ShieldPulseIcon()
                .accessibilityHidden(true)

            Text("This message contains language that sometimes appears in unhealthy relationships. You're not alone — here are some resources.")
                .font(.subheadline)
                .foregroundStyle(Color(hex: "7B5200"))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            dismissButton
        }
    }

    // MARK: Message Body

    private var messageText: some View {
        EmptyView() // Copy already in header; no duplicate needed.
    }

    // MARK: Resource Links

    private var resourceLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            resourceLink(
                title: "National DV Hotline",
                subtitle: "1-800-799-7233",
                url: "tel:18007997233",
                icon: "phone.fill"
            )
            resourceLink(
                title: "Focus on the Family",
                subtitle: "focusonthefamily.com",
                url: "https://www.focusonthefamily.com",
                icon: "heart.fill"
            )
            resourceLink(
                title: "Find a Counselor",
                subtitle: "Church counseling resources",
                url: "https://www.aacc.net",
                icon: "person.fill.questionmark"
            )
        }
    }

    private func resourceLink(
        title: String,
        subtitle: String,
        url: String,
        icon: String
    ) -> some View {
        if let linkURL = URL(string: url) {
            return AnyView(
                Link(destination: linkURL) {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(Color(hex: "7B5200").opacity(0.8))
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color(hex: "7B5200"))
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "7B5200").opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "7B5200").opacity(0.5))
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("\(title): \(subtitle)")
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    // MARK: Dismiss

    private var dismissButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                appearedOpacity = 0
                appearedScale = 0.94
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onDismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: "7B5200").opacity(0.7))
                .padding(6)
                .background(Circle().fill(Color(hex: "7B5200").opacity(0.12)))
        }
        .accessibilityLabel("Dismiss safety information")
    }
}

// MARK: - Shield Pulse Icon

private struct ShieldPulseIcon: View {

    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "FFCA28").opacity(isPulsing ? 0.0 : 0.25))
                .frame(width: 32, height: 32)
                .scaleEffect(isPulsing ? 1.35 : 1.0)
                .animation(
                    .easeInOut(duration: 1.6)
                    .repeatForever(autoreverses: true),
                    value: isPulsing
                )
            Image(systemName: "shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "F59E0B"))
        }
        .onAppear { isPulsing = true }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AegisC59RecipientBannerView(
        signal: AegisC59Signal(
            patternKind: .manipulationFraming,
            confidence: 0.88,
            recipientResources: ["1-800-799-7233", "focusonthefamily.com"],
            internalSignal: "C59.ManipulationFraming:preview"
        ),
        onDismiss: {}
    )
    .padding()
}
#endif
