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
//   - Resource links: Locale-appropriate DV Hotline, Focus on the Family, church counseling.
//
// Flag gate: AMENFeatureFlags.shared.aegisC59
// A-010: Safety resources are locale-aware — hotline name, phone, and URL change by region.

import SwiftUI

// MARK: - Banner View

struct AegisC59RecipientBannerView: View {

    let signal: AegisC59Signal
    var onDismiss: () -> Void

    // MARK: - A-010 Locale-aware safety resource

    /// Returns the most appropriate domestic-violence / safety hotline for the
    /// user's current device region. Falls back to the US National DV Hotline.
    /// NOTE: phone numbers are formatted for display only; tel: URLs strip spaces.
    private var localeSafetyResource: (name: String, phone: String, url: String) {
        let region = Locale.current.region?.identifier ?? "US"
        switch region {
        case "GB": return ("National Domestic Abuse Helpline", "0808 2000 247", "https://nationaldahelpline.org.uk")
        case "AU": return ("1800RESPECT", "1800 737 732", "https://www.1800respect.org.au")
        case "CA": return ("ShelterSafe", "1-800-799-7233", "https://www.sheltersafe.ca")
        case "IN": return ("iCall", "9152987821", "https://icallhelpline.org")
        case "ZA": return ("GBV Command Centre", "0800 428 428", "https://www.gbv.org.za")
        case "NG": return ("Project Alert", "+234-1-8933831", "https://projectalertnig.org")
        case "KE": return ("GBV Support", "+254 719 638 006", "https://www.health.go.ke")
        case "NZ": return ("Are You OK?", "0800 456 450", "https://www.areyouok.org.nz")
        case "DE": return ("Hilfetelefon", "08000 116 016", "https://www.hilfetelefon.de")
        case "FR": return ("Violences Femmes Info", "3919", "https://stop-violences-femmes.gouv.fr")
        default:   return ("National DV Hotline", "1-800-799-7233", "https://www.thehotline.org")
        }
    }

    /// Returns a tel: URL string that strips spaces/hyphens for phone dialing.
    private var localeSafetyTelURL: String {
        let digits = localeSafetyResource.phone
            .filter { $0.isNumber || $0 == "+" }
        return "tel:\(digits)"
    }

    @State private var appearedScale: Double = 0.96
    @State private var appearedOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            let entranceAnimation: Animation = reduceMotion
                ? .easeOut(duration: 0.15).delay(0.05)
                : .spring(response: 0.45, dampingFraction: 0.72).delay(0.05)
            withAnimation(entranceAnimation) {
                appearedScale = 1.0
                appearedOpacity = 1.0
            }
            // Gentle pulse on the shield icon is handled inside headerRow.
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Safety information banner") // TODO: Localize per A-010
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ShieldPulseIcon()
                .accessibilityHidden(true)

            // TODO: Localize per A-010 — safety banner text must be in user's language
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
            // A-010: hotline name, phone, and URL adapt to the device's region.
            resourceLink(
                title: localeSafetyResource.name,
                subtitle: localeSafetyResource.phone,
                url: localeSafetyTelURL,
                icon: "phone.fill"
            )
            // TODO: Localize per A-010 — safety banner text must be in user's language
            resourceLink(
                title: "Focus on the Family",
                subtitle: "focusonthefamily.com",
                url: "https://www.focusonthefamily.com",
                icon: "heart.fill"
            )
            // TODO: Localize per A-010 — safety banner text must be in user's language
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
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.2)) {
                appearedOpacity = 0
                appearedScale = reduceMotion ? 1.0 : 0.94
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.1 : 0.2)) {
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
        .accessibilityLabel("Dismiss safety information") // TODO: Localize per A-010
    }
}

// MARK: - Shield Pulse Icon

private struct ShieldPulseIcon: View {

    @State private var isPulsing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "FFCA28").opacity(reduceMotion ? 0.25 : (isPulsing ? 0.0 : 0.25)))
                .frame(width: 32, height: 32)
                .scaleEffect(reduceMotion ? 1.0 : (isPulsing ? 1.35 : 1.0))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: isPulsing
                )
            Image(systemName: "shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "F59E0B"))
        }
        .onAppear {
            if !reduceMotion { isPulsing = true }
        }
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
