// AmenSpaceTierSelectionView.swift
// AMEN Spaces — Monetization: Host tier management view
//
// Glass rule: card chrome uses thinMaterial; form inputs are matte.
// Shown in Space management settings for the space host.
// Written: 2026-06-02

import SwiftUI
import FirebaseFunctions

// MARK: - View

struct AmenSpaceTierSelectionView: View {
    let spaceId: String
    let existingTiers: [AmenSpaceSubscriptionTier]
    let onSaveTier: (AmenSpaceSubscriptionTier) -> Void
    let onDeleteTier: (String) -> Void

    @State private var showingAddForm: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sortedTiers: [AmenSpaceSubscriptionTier] {
        existingTiers.sorted { $0.order < $1.order }
    }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    pageHeader
                    tierList
                    if showingAddForm {
                        AddTierFormCard(
                            spaceId: spaceId,
                            isSaving: $isSaving,
                            saveError: $saveError,
                            reduceMotion: reduceMotion,
                            onSave: { tier in
                                onSaveTier(tier)
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                                    showingAddForm = false
                                }
                            },
                            onCancel: {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                    showingAddForm = false
                                }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    if !showingAddForm {
                        addTierButton
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                    if let error = saveError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                    Spacer(minLength: 32)
                }
            }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Membership Tiers")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white)
            Text("Manage the tiers available to your community members.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Tier List

    private var tierList: some View {
        VStack(spacing: 10) {
            ForEach(sortedTiers) { tier in
                TierManagementCard(
                    tier: tier,
                    onToggleActive: { updated in onSaveTier(updated) },
                    onDelete: { onDeleteTier(tier.id) }
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Add Tier Button

    private var addTierButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                showingAddForm = true
                saveError = nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Add tier")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(hex: "D9A441"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "D9A441").opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a new membership tier")
    }
}

// MARK: - Tier Management Card (matte with glass top strip)

private struct TierManagementCard: View {
    let tier: AmenSpaceSubscriptionTier
    let onToggleActive: (AmenSpaceSubscriptionTier) -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation: Bool = false

    private var priceLabel: String {
        guard !tier.isFreeTier, tier.monthlyPriceCents > 0 else { return "Free" }
        let dollars = Double(tier.monthlyPriceCents) / 100.0
        if dollars.truncatingRemainder(dividingBy: 1) == 0 {
            return "$\(Int(dollars))/mo"
        }
        return String(format: "$%.2f/mo", dollars)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text(priceLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { tier.isActive },
                    set: { newValue in
                        var updated = tier
                        updated.isActive = newValue
                        onToggleActive(updated)
                    }
                ))
                .labelsHidden()
                .tint(Color(hex: "D9A441"))
                .accessibilityLabel(tier.isActive ? "Deactivate \(tier.name) tier" : "Activate \(tier.name) tier")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            if !tier.isFreeTier {
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Delete tier")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.red.opacity(0.70))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(tier.name) tier")
                    .padding(.trailing, 4)
                    .padding(.top, 6)
                }
                .confirmationDialog(
                    "Delete \(tier.name)?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) { onDelete() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Members on this tier will lose access. This cannot be undone.")
                }
            }
        }
    }
}

// MARK: - Add Tier Form Card (matte)

private struct AddTierFormCard: View {
    let spaceId: String
    @Binding var isSaving: Bool
    @Binding var saveError: String?
    let reduceMotion: Bool
    let onSave: (AmenSpaceSubscriptionTier) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var tierDescription: String = ""
    @State private var monthlyPriceDollars: Double = 9.99
    @State private var hasAnnualPrice: Bool = false
    @State private var annualPriceDollars: Double = 99.0
    @State private var isFreeTier: Bool = false
    @State private var hasIntro: Bool = false
    @State private var introMonths: Int = 1
    @State private var introPriceDollars: Double = 4.99
    @State private var features: String = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Tier")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)

            formField(label: "Tier name", placeholder: "e.g. Member") {
                TextField("", text: $name)
                    .formTextFieldStyle()
            }

            formField(label: "Description", placeholder: nil) {
                TextField("Brief description of this tier", text: $tierDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .formTextFieldStyle()
            }

            formField(label: "Features (one per line)", placeholder: nil) {
                TextField("e.g. Live room access\nReplay library", text: $features, axis: .vertical)
                    .lineLimit(3...6)
                    .formTextFieldStyle()
            }

            Toggle("Free tier (no charge)", isOn: $isFreeTier)
                .tint(Color(hex: "D9A441"))
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.85))

            if !isFreeTier {
                monthlyPriceField
                annualPriceSection
                introSection
            }

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Button(action: saveTier) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color(hex: "070607"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Text("Save tier")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "070607"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(canSave ? Color(hex: "D9A441") : Color(hex: "D9A441").opacity(0.35))
                )
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving)
                .accessibilityLabel("Save tier")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Sub-sections

    private var monthlyPriceField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Monthly price (USD)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            HStack {
                Text("$")
                    .foregroundStyle(Color.white.opacity(0.55))
                TextField("9.99", value: $monthlyPriceDollars, format: .number)
                    .keyboardType(.decimalPad)
                    .formTextFieldStyle()
            }
        }
    }

    private var annualPriceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Offer annual pricing", isOn: $hasAnnualPrice)
                .tint(Color(hex: "D9A441"))
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.85))

            if hasAnnualPrice {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Annual price (USD)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                    HStack {
                        Text("$")
                            .foregroundStyle(Color.white.opacity(0.55))
                        TextField("99.00", value: $annualPriceDollars, format: .number)
                            .keyboardType(.decimalPad)
                            .formTextFieldStyle()
                    }
                }
            }
        }
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Intro pricing", isOn: $hasIntro)
                .tint(Color(hex: "D9A441"))
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.85))

            if hasIntro {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duration (months)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Stepper("\(introMonths)", value: $introMonths, in: 1...12)
                            .foregroundStyle(Color.white)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Intro price (USD/mo)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                        HStack {
                            Text("$")
                                .foregroundStyle(Color.white.opacity(0.55))
                            TextField("4.99", value: $introPriceDollars, format: .number)
                                .keyboardType(.decimalPad)
                                .formTextFieldStyle()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Form Helper

    @ViewBuilder
    private func formField<Content: View>(
        label: String,
        placeholder: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            content()
        }
    }

    // MARK: - Save

    private func saveTier() {
        guard canSave else { return }
        isSaving = true
        saveError = nil

        let featureList = features
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let tier = AmenSpaceSubscriptionTier(
            id: UUID().uuidString,
            spaceId: spaceId,
            name: name.trimmingCharacters(in: .whitespaces),
            description: tierDescription.trimmingCharacters(in: .whitespaces),
            monthlyPriceCents: isFreeTier ? 0 : Int((monthlyPriceDollars * 100).rounded()),
            annualPriceCents: (!isFreeTier && hasAnnualPrice) ? Int((annualPriceDollars * 100).rounded()) : nil,
            features: featureList,
            order: 1,
            isActive: true,
            isFreeTier: isFreeTier,
            storeKitProductId: nil,
            introMonths: (!isFreeTier && hasIntro) ? introMonths : nil,
            introPriceCents: (!isFreeTier && hasIntro) ? Int((introPriceDollars * 100).rounded()) : nil,
            createdAt: Date()
        )

        Task {
            do {
                let callable = Functions.functions().httpsCallable(AmenSpacesPhase1Callable.createSpaceTier.rawValue)
                _ = try await callable.call([
                    "spaceId": spaceId,
                    "name": tier.name,
                    "description": tier.description,
                    "monthlyPriceCents": tier.monthlyPriceCents,
                    "annualPriceCents": tier.annualPriceCents as Any,
                    "features": tier.features,
                    "isFreeTier": tier.isFreeTier,
                    "introMonths": tier.introMonths as Any,
                    "introPriceCents": tier.introPriceCents as Any,
                ])
                await MainActor.run {
                    isSaving = false
                    onSave(tier)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = "Could not save tier. Please try again."
                }
            }
        }
    }
}

// MARK: - Text Field Style Helper

private extension View {
    func formTextFieldStyle() -> some View {
        self
            .font(.system(size: 14))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenSpaceTierSelectionView(
        spaceId: "s1",
        existingTiers: [
            AmenSpaceSubscriptionTier(
                id: "t0",
                spaceId: "s1",
                name: "Community",
                description: "Free access to the feed.",
                monthlyPriceCents: 0,
                annualPriceCents: nil,
                features: ["Feed access"],
                order: 0,
                isActive: true,
                isFreeTier: true,
                storeKitProductId: nil,
                introMonths: nil,
                introPriceCents: nil,
                createdAt: Date()
            ),
            AmenSpaceSubscriptionTier(
                id: "t1",
                spaceId: "s1",
                name: "Member",
                description: "Full access.",
                monthlyPriceCents: 999,
                annualPriceCents: 9588,
                features: ["Live room", "Replay library"],
                order: 1,
                isActive: true,
                isFreeTier: false,
                storeKitProductId: "com.amen.spaces.member",
                introMonths: 2,
                introPriceCents: 499,
                createdAt: Date()
            ),
        ],
        onSaveTier: { _ in },
        onDeleteTier: { _ in }
    )
}
#endif
