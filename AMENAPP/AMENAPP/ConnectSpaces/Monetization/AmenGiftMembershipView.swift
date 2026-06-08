// AmenGiftMembershipView.swift
// AMEN Spaces — Monetization: Gift a paid space membership to another person.
//
// Glass rule: sheet chrome uses .ultraThinMaterial header strip;
//             tier cards and summary card are matte.
// Presented as a .sheet — consumer wraps in sheet(isPresented:).
// Written: 2026-06-03

import SwiftUI
import FirebaseFunctions

// MARK: - Gift Duration

enum GiftDuration: CaseIterable, Hashable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case lifetime

    /// nil = lifetime (no expiry)
    var months: Int? {
        switch self {
        case .oneMonth:     return 1
        case .threeMonths:  return 3
        case .sixMonths:    return 6
        case .oneYear:      return 12
        case .lifetime:     return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .oneMonth:     return "1 Month"
        case .threeMonths:  return "3 Months"
        case .sixMonths:    return "6 Months"
        case .oneYear:      return "1 Year"
        case .lifetime:     return "Lifetime"
        }
    }
}

// MARK: - View

struct AmenGiftMembershipView: View {
    let spaceId: String
    let spaceName: String
    let availableTiers: [AmenSpaceSubscriptionTier]
    let onDismiss: () -> Void

    @State private var recipient: String = ""
    @State private var selectedTier: AmenSpaceSubscriptionTier? = nil
    @State private var selectedDuration: GiftDuration = .oneMonth
    @State private var personalMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var didSucceed: Bool = false
    @State private var errorMessage: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var paidTiers: [AmenSpaceSubscriptionTier] {
        availableTiers.filter { $0.isActive && !$0.isFreeTier }.sorted { $0.order < $1.order }
    }

    private var canGift: Bool {
        !recipient.trimmingCharacters(in: .whitespaces).isEmpty && selectedTier != nil
    }

    private var giftPriceCents: Int {
        guard let tier = selectedTier else { return 0 }
        switch selectedDuration {
        case .lifetime:
            // Use annual * 5 as a proxy; real price comes from the CF
            return (tier.annualPriceCents ?? tier.monthlyPriceCents * 12) * 5
        case .oneYear:
            return tier.annualPriceCents ?? tier.monthlyPriceCents * 12
        default:
            return tier.monthlyPriceCents * (selectedDuration.months ?? 1)
        }
    }

    private var giftPriceString: String {
        let dollars = Double(giftPriceCents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            if didSucceed {
                successOverlay
            } else {
                mainContent
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            sheetHeader
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    recipientSection
                    tierPickerSection
                    durationSection
                    messageSection
                    priceSummaryCard
                    giftButton
                    disclaimerText
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Spacer().frame(height: 24)
                Image(systemName: "gift.fill")
                    .font(.systemScaled(24, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityHidden(true)
                Text("Gift a Membership to \(spaceName)")
                    .font(.systemScaled(20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.25)
                    }
            )

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .padding(9)
                    .background(
                        Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    )
            }
            .accessibilityLabel("Dismiss gift membership sheet")
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
    }

    // MARK: - Recipient

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Recipient")
            TextField("Recipient's email or AMEN username", text: $recipient)
                .font(.systemScaled(14))
                .foregroundStyle(Color.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    recipient.isEmpty
                                        ? Color.white.opacity(0.12)
                                        : Color(hex: "D9A441").opacity(0.55),
                                    lineWidth: 1
                                )
                        )
                )
                .accessibilityLabel("Recipient email or AMEN username")
        }
    }

    // MARK: - Tier Picker

    private var tierPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Membership Tier")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(paidTiers) { tier in
                        GiftTierCard(
                            tier: tier,
                            isSelected: selectedTier?.id == tier.id,
                            reduceMotion: reduceMotion,
                            onSelect: {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                                    selectedTier = tier
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Duration")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GiftDuration.allCases, id: \.self) { duration in
                        DurationChip(
                            label: duration.displayLabel,
                            isSelected: selectedDuration == duration,
                            reduceMotion: reduceMotion,
                            onSelect: {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                                    selectedDuration = duration
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Personal Message

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Personal Note")
                Spacer()
                Text("\(personalMessage.count)/200")
                    .font(.systemScaled(11))
                    .foregroundStyle(
                        personalMessage.count >= 200
                            ? Color.red.opacity(0.80)
                            : Color.white.opacity(0.35)
                    )
                    .accessibilityLabel("\(personalMessage.count) of 200 characters used")
            }
            TextField("Add a personal note... (optional)", text: $personalMessage, axis: .vertical)
                .font(.systemScaled(14))
                .foregroundStyle(Color.white)
                .lineLimit(3...5)
                .onChange(of: personalMessage) { _, newValue in
                    if newValue.count > 200 {
                        personalMessage = String(newValue.prefix(200))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .accessibilityLabel("Personal note, optional, maximum 200 characters")
        }
    }

    // MARK: - Price Summary

    private var priceSummaryCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You pay")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .textCase(.uppercase)
                        .kerning(0.6)
                    Text(selectedTier != nil ? giftPriceString : "—")
                        .font(.systemScaled(28, weight: .black))
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                Spacer()
                if let tier = selectedTier {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("They receive")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .textCase(.uppercase)
                            .kerning(0.6)
                        Text(tier.name)
                            .font(.systemScaled(15, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("for \(selectedDuration.displayLabel)")
                            .font(.systemScaled(13))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            selectedTier != nil
                                ? Color(hex: "D9A441").opacity(0.35)
                                : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            selectedTier != nil
                ? "Price summary: You pay \(giftPriceString). They receive \(selectedTier!.name) for \(selectedDuration.displayLabel)."
                : "Select a tier to see price summary"
        )
    }

    // MARK: - Gift Button

    private var giftButton: some View {
        Button(action: sendGift) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color(hex: "070607"))
                } else {
                    Text(canGift ? "Gift Membership — \(giftPriceString)" : "Gift Membership")
                        .font(.systemScaled(16, weight: .bold))
                        .foregroundStyle(Color(hex: "070607"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(canGift ? Color(hex: "D9A441") : Color(hex: "D9A441").opacity(0.30))
        )
        .buttonStyle(.plain)
        .disabled(!canGift || isLoading)
        .accessibilityLabel(
            canGift
                ? "Gift \(selectedTier?.name ?? "membership") for \(giftPriceString)"
                : "Gift Membership — select a tier and enter a recipient first"
        )

        // Inline error beneath button
        .overlay(alignment: .bottom) {
            if let message = errorMessage {
                Text(message)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 52)
                    .accessibilityLabel("Error: \(message)")
            }
        }
    }

    // MARK: - Disclaimer

    private var disclaimerText: some View {
        Text("Gift purchases are non-refundable. Recipient will be notified by email.")
            .font(.systemScaled(12))
            .foregroundStyle(Color.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.top, errorMessage != nil ? 20 : 0)
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .font(.systemScaled(52, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
                .accessibilityHidden(true)
            Text("Gift sent!")
                .font(.systemScaled(26, weight: .bold))
                .foregroundStyle(Color.white)
            Text("Your gift has been sent to \(recipient.trimmingCharacters(in: .whitespaces)).")
                .font(.systemScaled(15))
                .foregroundStyle(Color.white.opacity(0.60))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gift sent to \(recipient.trimmingCharacters(in: .whitespaces))")
    }

    // MARK: - Action

    private func sendGift() {
        guard let tier = selectedTier else { return }
        let recipientTrimmed = recipient.trimmingCharacters(in: .whitespaces)
        guard !recipientTrimmed.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        var payload: [String: Any] = [
            "spaceId": spaceId,
            "tierId": tier.id,
            "recipientIdentifier": recipientTrimmed,
        ]
        if let months = selectedDuration.months {
            payload["durationMonths"] = months
        } else {
            payload["lifetime"] = true
        }
        let trimmedMessage = personalMessage.trimmingCharacters(in: .whitespaces)
        if !trimmedMessage.isEmpty {
            payload["message"] = trimmedMessage
        }

        Task {
            do {
                let callable = Functions.functions().httpsCallable("createSpaceGiftMembership")
                _ = try await callable.call(payload)
                await MainActor.run {
                    isLoading = false
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.72)) {
                        didSucceed = true
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run { onDismiss() }
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Could not send gift. Please check your connection and try again."
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.systemScaled(12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.50))
            .textCase(.uppercase)
            .kerning(0.6)
    }
}

// MARK: - Gift Tier Card (matte)

private struct GiftTierCard: View {
    let tier: AmenSpaceSubscriptionTier
    let isSelected: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    private var monthlyPriceString: String {
        guard tier.monthlyPriceCents > 0 else { return "Free" }
        let dollars = Double(tier.monthlyPriceCents) / 100.0
        if dollars.truncatingRemainder(dividingBy: 1) == 0 {
            return "$\(Int(dollars))/mo"
        }
        return String(format: "$%.2f/mo", dollars)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tier.name)
                        .font(.systemScaled(15, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(16))
                            .foregroundStyle(Color(hex: "D9A441"))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(monthlyPriceString)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: "D9A441") : Color.white.opacity(0.55))

                if !tier.features.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tier.features.prefix(3), id: \.self) { feature in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.systemScaled(9, weight: .bold))
                                    .foregroundStyle(Color(hex: "D9A441"))
                                    .frame(width: 12)
                                Text(feature)
                                    .font(.systemScaled(11))
                                    .foregroundStyle(Color.white.opacity(0.60))
                            }
                        }
                        if tier.features.count > 3 {
                            Text("+\(tier.features.count - 3) more")
                                .font(.systemScaled(10))
                                .foregroundStyle(Color.white.opacity(0.35))
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color(hex: "D9A441").opacity(0.10) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color(hex: "D9A441") : Color.white.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(tier.name), \(monthlyPriceString). \(tier.features.joined(separator: ". ")). \(isSelected ? "Selected" : "Tap to select")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Duration Chip

private struct DurationChip: View {
    let label: String
    let isSelected: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(label)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: "070607") : Color.white.opacity(0.70))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(hex: "D9A441") : Color.white.opacity(0.09))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.clear : Color.white.opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenGiftMembershipView(
        spaceId: "s1",
        spaceName: "Reformation Church",
        availableTiers: [
            AmenSpaceSubscriptionTier(
                id: "t1",
                spaceId: "s1",
                name: "Member",
                description: "Full access to live services, replays, and chat.",
                monthlyPriceCents: 999,
                annualPriceCents: 9588,
                features: ["Live room access", "Replay library", "Chat channels", "AI recap"],
                order: 1,
                isActive: true,
                isFreeTier: false,
                storeKitProductId: "com.amen.spaces.member.monthly",
                introMonths: nil,
                introPriceCents: nil,
                createdAt: Date()
            ),
            AmenSpaceSubscriptionTier(
                id: "t2",
                spaceId: "s1",
                name: "Founding Member",
                description: "All Member benefits plus direct access to the pastor.",
                monthlyPriceCents: 2499,
                annualPriceCents: 23988,
                features: ["Everything in Member", "Study companion", "AI transcript search", "Direct messaging"],
                order: 2,
                isActive: true,
                isFreeTier: false,
                storeKitProductId: "com.amen.spaces.founding.monthly",
                introMonths: nil,
                introPriceCents: nil,
                createdAt: Date()
            ),
        ],
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
#endif
