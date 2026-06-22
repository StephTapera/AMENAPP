// CrisisResourceOverlayView.swift
// AMEN — CRISIS-001 fix.
//
// Full-screen overlay shown when BereanConstitutionalPipeline.shared.isCrisisEscalated
// fires (invariant I-4). Displayed via .fullScreenCover in BereanChatView so it cannot
// be silently dismissed by scrolling or background taps.
//
// Design rules:
//   - 988 is the primary action — large, immediately visible, top of card.
//   - Crisis Text Line (text HOME to 741741) is secondary.
//   - Emergency call (911 or local equivalent via InternationalCrisisLineService) is tertiary.
//   - Dismiss requires a deliberate button tap — not a swipe.
//   - NO Berean content is shown while this overlay is active.
//   - No flag gate — CRISIS-001 safety overlay ships always-on.

import SwiftUI

struct CrisisResourceOverlayView: View {

    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cardScale: Double = 0.94
    @State private var cardOpacity: Double = 0

    var body: some View {
        ZStack {
            // Scrim — blocks all content behind the overlay
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    crisisCard
                        .padding(.horizontal, 20)
                        .padding(.top, 48)
                        .padding(.bottom, 36)
                }
            }
        }
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
        .onAppear {
            let animation: Animation = reduceMotion
                ? .easeOut(duration: 0.15)
                : .spring(response: 0.42, dampingFraction: 0.78)
            withAnimation(animation) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
            // Announce to VoiceOver immediately on appear
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "Crisis support resources. 988 Suicide and Crisis Lifeline. Call or text 988 now."
            )
        }
    }

    // MARK: - Main Card

    private var crisisCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection
                .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 2)
                .padding(.bottom, 20)

            // Primary: 988
            primaryHotlineRow(
                title: "988 Suicide & Crisis Lifeline",
                detail: "Call or text 988 — free, confidential, 24/7",
                dialTarget: "988",
                accentColor: Color(red: 0.85, green: 0.25, blue: 0.25)
            )
            .padding(.bottom, 14)

            // Secondary: Crisis Text Line
            secondaryHotlineRow(
                icon: "message.fill",
                title: "Crisis Text Line",
                detail: "Text HOME to 741741",
                url: "sms:741741&body=HOME"
            )
            .padding(.bottom, 10)

            // Tertiary: local emergency
            secondaryHotlineRow(
                icon: "phone.fill",
                title: "Emergency Services",
                detail: localEmergencyDetail,
                url: "tel:\(localEmergencyNumber)"
            )
            .padding(.bottom, 28)

            Divider()
                .padding(.horizontal, 2)
                .padding(.bottom, 20)

            // Pastoral note
            pastoralNote
                .padding(.bottom, 28)

            // Dismiss
            dismissButton
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.22), radius: 32, y: 12)
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            // Red pulse icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "heart.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.red)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("You're Not Alone")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Berean paused because it detected you may be going through something difficult. Real support is here.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Primary 988 Row

    private func primaryHotlineRow(
        title: String,
        detail: String,
        dialTarget: String,
        accentColor: Color
    ) -> some View {
        Button {
            if let url = URL(string: "tel:\(dialTarget)") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 50, height: 50)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Call 988")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(accentColor)
                    )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call 988 Suicide and Crisis Lifeline. Free, confidential, 24/7.")
        .accessibilityHint("Opens phone dialer.")
    }

    // MARK: - Secondary Row

    private func secondaryHotlineRow(
        icon: String,
        title: String,
        detail: String,
        url urlString: String
    ) -> some View {
        Button {
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail).")
    }

    // MARK: - Pastoral Note

    private var pastoralNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(.top, 2)
                .accessibilityHidden(true)

            Text("Talking to a pastor, counselor, or trusted friend can help — and so can these trained crisis counselors. You do not have to face this alone.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button {
            withAnimation(reduceMotion
                ? .easeOut(duration: 0.12)
                : .easeInOut(duration: 0.22)) {
                cardOpacity = 0
                cardScale = reduceMotion ? 1.0 : 0.94
            }
            // Small delay so the fade completes before the sheet disappears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                // Reset pipeline flag before dismissing so re-entry is possible
                BereanConstitutionalPipeline.shared.isCrisisEscalated = false
                isPresented = false
            }
        } label: {
            HStack {
                Spacer()
                Text("I'm safe — close this")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I am safe. Close crisis resources.")
    }

    // MARK: - Local Emergency

    /// Returns the local emergency services number based on device locale.
    /// Defaults to "911" for US/CA; uses "999" for UK; "000" for AU; "112" for EU.
    private var localEmergencyNumber: String {
        let region = Locale.current.region?.identifier ?? "US"
        switch region {
        case "US", "CA", "MX", "PH": return "911"
        case "GB", "IE", "IN", "SG", "MY", "HK": return "999"
        case "AU": return "000"
        case "NZ": return "111"
        case "JP": return "110"
        case "CN": return "110"
        case "BR": return "190"
        case "ZA": return "10111"
        case "NG": return "199"
        case "KE": return "999"
        case "GH": return "191"
        // EU + most of Europe
        case "DE", "FR", "IT", "ES", "PT", "NL", "BE", "AT", "CH",
             "SE", "NO", "DK", "FI", "PL", "CZ", "HU", "RO", "BG",
             "HR", "SK", "SI", "EE", "LV", "LT", "CY", "LU", "MT":
            return "112"
        default: return "112"  // International standard
        }
    }

    private var localEmergencyDetail: String {
        let number = localEmergencyNumber
        return "Call \(number) for immediate danger"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Crisis Overlay") {
    CrisisResourceOverlayView(isPresented: .constant(true))
}
#endif
