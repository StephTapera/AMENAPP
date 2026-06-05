// AmenSpaceLegalGateView.swift
// AMEN ConnectSpaces — Legal
//
// Gate sheet presented before a user joins a paid Space.
// All 3 legal checkboxes must be acknowledged before membership activates.
// Glass rule: header card uses thinMaterial chrome; checklist rows are matte.
// Written: 2026-06-03

import SwiftUI
import FirebaseFunctions

// MARK: - Main Gate View

struct AmenSpaceLegalGateView: View {
    let spaceId: String
    let spaceName: String
    let hostDisplayName: String
    let tierName: String
    let monthlyPriceCents: Int
    let userId: String
    let onAccepted: () -> Void
    let onDeclined: () -> Void

    @State private var termsAcknowledged: Bool = false
    @State private var standardsAcknowledged: Bool = false
    @State private var spaceRulesAcknowledged: Bool = false

    @State private var activeSubSheet: LegalSubSheet? = nil
    @State private var isConfirming: Bool = false
    @State private var confirmationError: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private var allAcknowledged: Bool {
        termsAcknowledged && standardsAcknowledged && spaceRulesAcknowledged
    }

    private var formattedPrice: String {
        guard monthlyPriceCents > 0 else { return "Free" }
        let dollars = Double(monthlyPriceCents) / 100.0
        if dollars.truncatingRemainder(dividingBy: 1) == 0 {
            return "$\(Int(dollars))/mo"
        }
        return String(format: "$%.2f/mo", dollars)
    }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                dragIndicator
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        spaceHeaderCard
                        checklistSection
                        billingNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
                footerButtons
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)   // we render our own for styling
        .sheet(item: $activeSubSheet) { sheet in
            subSheetContent(for: sheet)
        }
    }

    // MARK: - Drag Indicator

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.white.opacity(0.25))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }

    // MARK: - Space Header Card (chrome)

    private var spaceHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "D9A441").opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(spaceName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(tierName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedPrice)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(Color.white)
                }
            }

            Divider()
                .opacity(0.18)

            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .accessibilityHidden(true)
                Text("Hosted by \(hostDisplayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spaceName), \(tierName) tier, \(formattedPrice). Hosted by \(hostDisplayName).")
    }

    // MARK: - Checklist Section (matte rows)

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Please review and acknowledge the following")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
                .kerning(0.5)
                .padding(.bottom, 4)

            LegalCheckRow(
                label: "AMEN Terms of Service",
                isAcknowledged: $termsAcknowledged,
                reduceMotion: reduceMotion,
                onReadTap: { activeSubSheet = .termsOfService }
            )

            LegalCheckRow(
                label: "AMEN Community Standards",
                isAcknowledged: $standardsAcknowledged,
                reduceMotion: reduceMotion,
                onReadTap: { activeSubSheet = .communityStandards }
            )

            LegalCheckRow(
                label: "Creator's Space Rules",
                isAcknowledged: $spaceRulesAcknowledged,
                reduceMotion: reduceMotion,
                onReadTap: { activeSubSheet = .spaceRules }
            )
        }
    }

    // MARK: - Billing Note

    private var billingNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.35))
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text("By confirming, you authorize AMEN to charge your selected payment method on a recurring basis. Cancel anytime in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.40))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("By confirming, you authorize AMEN to charge your selected payment method on a recurring basis. Cancel anytime in Settings.")
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.18)

            VStack(spacing: 12) {
                if let error = confirmationError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                confirmButton
                declineButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }

    private var confirmButton: some View {
        let isEnabled = allAcknowledged && !isConfirming

        return Button(action: activateMembership) {
            Group {
                if isConfirming {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color(hex: "070607"))
                } else {
                    Text("Confirm Membership")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "070607"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isEnabled ? Color(hex: "D9A441") : Color(hex: "D9A441").opacity(0.30))
        )
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast), value: isEnabled)
        .accessibilityLabel("Confirm Membership")
        .accessibilityHint(isEnabled ? "" : "Acknowledge all three items above to continue")
    }

    private var declineButton: some View {
        Button(action: onDeclined) {
            Text("Decline")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.50))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Decline and dismiss")
    }

    // MARK: - Sub-Sheet Content

    @ViewBuilder
    private func subSheetContent(for sheet: LegalSubSheet) -> some View {
        switch sheet {
        case .termsOfService:
            NavigationStack {
                AmenCreatorLegalOS(
                    documentType: .termsOfService,
                    userId: userId,
                    requiresAcceptance: false,
                    onAccepted: nil,
                    onDismiss: {
                        activeSubSheet = nil
                        termsAcknowledged = true
                    }
                )
            }
        case .communityStandards:
            NavigationStack {
                AmenCreatorLegalOS(
                    documentType: .communityStandards,
                    userId: userId,
                    requiresAcceptance: false,
                    onAccepted: nil,
                    onDismiss: {
                        activeSubSheet = nil
                        standardsAcknowledged = true
                    }
                )
            }
        case .spaceRules:
            SpaceRulesSheet(spaceName: spaceName) {
                activeSubSheet = nil
                spaceRulesAcknowledged = true
            }
        }
    }

    // MARK: - Activate Membership CF Call

    private func activateMembership() {
        guard allAcknowledged, !isConfirming else { return }
        isConfirming = true
        confirmationError = nil

        Task {
            do {
                let callable = Functions.functions().httpsCallable("activateSpaceMembership")
                let payload: [String: Any] = [
                    "spaceId": spaceId,
                    "tierId": tierName,    // TODO: pass actual tierId from the call site
                    "userId": userId
                ]
                _ = try await callable.call(payload)
                await MainActor.run {
                    isConfirming = false
                    onAccepted()
                }
            } catch {
                await MainActor.run {
                    isConfirming = false
                    confirmationError = "Membership activation failed. Please try again."
                }
            }
        }
    }
}

// MARK: - Sub-Sheet Enum

private enum LegalSubSheet: String, Identifiable {
    case termsOfService
    case communityStandards
    case spaceRules

    var id: String { rawValue }
}

// MARK: - Legal Check Row

private struct LegalCheckRow: View {
    let label: String
    @Binding var isAcknowledged: Bool
    let reduceMotion: Bool
    let onReadTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Checkbox (matte)
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast)) {
                    isAcknowledged.toggle()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isAcknowledged ? Color(hex: "D9A441") : Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isAcknowledged ? Color(hex: "D9A441") : Color.white.opacity(0.22),
                                    lineWidth: 1.5
                                )
                        )
                        .frame(width: 22, height: 22)

                    if isAcknowledged {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Color(hex: "070607"))
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label) \(isAcknowledged ? "acknowledged" : "not acknowledged")")
            .accessibilityAddTraits(isAcknowledged ? [.isSelected] : [])

            // Label (matte)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Read button
            Button(action: onReadTap) {
                Text("Read")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(hex: "D9A441").opacity(0.12))
                            .overlay(Capsule().strokeBorder(Color(hex: "D9A441").opacity(0.30), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read \(label)")
            .accessibilityHint("Opens document in a sub-sheet and marks it as read")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isAcknowledged ? 0.05 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isAcknowledged ? Color(hex: "D9A441").opacity(0.30) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
        .animation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast), value: isAcknowledged)
    }
}

// MARK: - Space Rules Sub-Sheet

private struct SpaceRulesSheet: View {
    let spaceName: String
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                // Minimal header (matte)
                HStack {
                    Text("Creator's Space Rules")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.70))
                            .padding(9)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                            )
                    }
                    .accessibilityLabel("Done reading Space Rules")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(alignment: .bottom) { Divider().opacity(0.20) }
                )

                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        spaceRulesBody
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }

                // Done button
                VStack(spacing: 0) {
                    Divider().opacity(0.18)
                    Button(action: onDone) {
                        Text("I've Read the Space Rules")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: "070607"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "D9A441"))
                    )
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                    .accessibilityLabel("Confirm you have read the Space Rules")
                }
                .background(
                    Rectangle().fill(.ultraThinMaterial)
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var spaceRulesBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityHidden(true)
                Text("Community Standards Commitment")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
            }

            Text("This creator has agreed to uphold AMEN's Community Standards. Additional space-specific rules may be posted in the Space.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.18)

            Text("What this means for you")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))

            let points = [
                "The host is committed to respectful, faith-building content.",
                "Zero tolerance for hate speech, exploitation, or harassment.",
                "AMEN's moderation team oversees all Spaces.",
                "You can report any content or behavior through the in-app report tool."
            ]

            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .frame(width: 14)
                        .offset(y: 3)
                        .accessibilityHidden(true)
                    Text(point)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenSpaceLegalGateView(
        spaceId: "space-preview-1",
        spaceName: "Grace & Truth Church",
        hostDisplayName: "Pastor Marcus Webb",
        tierName: "Member",
        monthlyPriceCents: 999,
        userId: "preview-user-1",
        onAccepted: {},
        onDeclined: {}
    )
    .preferredColorScheme(.dark)
}
#endif
