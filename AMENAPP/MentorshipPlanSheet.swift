// MentorshipPlanSheet.swift
// AMENAPP
// StoreKit-backed mentorship plan picker.

import SwiftUI
import StoreKit

struct MentorshipPlanSheet: View {
    let mentor: Mentor
    @ObservedObject var vm: MentorshipViewModel
    let onDismiss: () -> Void

    @State private var selectedPlan: MentorshipPlan?
    @State private var productsById: [String: Product] = [:]
    @State private var isLoadingProducts = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var plans: [MentorshipPlan] {
        mentor.plans.isEmpty ? MentorshipPlan.defaultPlans() : mentor.plans
    }

    var body: some View {
        NavigationStack {
            Group {
                if AMENFeatureFlags.shared.mentorshipEnabled {
                    planScrollContent
                } else {
                    mentorshipPlanUnavailableView
                }
            }
            .navigationTitle("Choose a Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Restore Purchases") {
                        Task { await restorePurchases() }
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .task {
            if selectedPlan == nil { selectedPlan = plans.first }
            await loadPaidProducts()
        }
    }

    private var mentorshipPlanUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Mentorship plans are disabled")
                .font(.systemScaled(18, weight: .bold))
                .multilineTextAlignment(.center)
            Text("This community has mentorship enrollment turned off right now.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var planScrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                mentorHeader
                planCardsList

                if isLoadingProducts {
                    Label("Loading App Store products", systemImage: "cart")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.systemScaled(13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }

                if let successMessage {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 18)
                }

                if let plan = selectedPlan {
                    ctaButton(for: plan)
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 16)
        }
    }

    private var planCardsList: some View {
        VStack(spacing: 12) {
            ForEach(plans) { plan in
                let selected = selectedPlan?.id == plan.id
                PlanCard(plan: plan, product: productsById[plan.stripePriceId], isSelected: selected)
                    .onTapGesture {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                            selectedPlan = plan
                            errorMessage = nil
                        }
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
    }

    private var mentorHeader: some View {
        HStack(spacing: 12) {
            MentorAvatarView(name: mentor.name, photoURL: mentor.photoURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mentorship with \(mentor.name)")
                    .font(.systemScaled(15, weight: .semibold))
                Text(mentor.role)
                    .font(.systemScaled(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private func ctaButton(for plan: MentorshipPlan) -> some View {
        Button {
            Task { await handlePlanSelection(plan) }
        } label: {
            HStack {
                if isProcessing {
                    ProgressView().tint(.white).padding(.trailing, 4)
                }
                Text(primaryButtonTitle(for: plan))
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.49, green: 0.23, blue: 0.93)))
        }
        .disabled(isProcessing || (!plan.isFree && productsById[plan.stripePriceId] == nil))
        .padding(.horizontal, 18)

        if !plan.isFree && productsById[plan.stripePriceId] == nil {
            Text("The App Store product \(plan.stripePriceId) is not configured for this build.")
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
    }

    private func primaryButtonTitle(for plan: MentorshipPlan) -> String {
        if plan.isFree { return "Start Free - \(plan.name)" }
        if let product = productsById[plan.stripePriceId] {
            return "Start \(plan.name) - \(product.displayPrice)"
        }
        return "Plan unavailable"
    }

    private func loadPaidProducts() async {
        let ids = Array(Set(plans.filter { !$0.isFree }.map(\.stripePriceId)))
        guard !ids.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: ids)
            productsById = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            if products.count < ids.count {
                errorMessage = "Some mentorship products are missing from StoreKit configuration."
            }
        } catch {
            errorMessage = "App Store products could not be loaded. Check your connection and StoreKit configuration."
        }
    }

    private func handlePlanSelection(_ plan: MentorshipPlan) async {
        isProcessing = true
        errorMessage = nil
        successMessage = nil
        defer { isProcessing = false }

        do {
            if plan.isFree {
                _ = try await MentorshipService.shared.createFreeRelationship(
                    mentorId: mentor.id,
                    planId: plan.id,
                    planName: plan.name,
                    mentorName: mentor.name,
                    mentorPhotoURL: mentor.photoURL
                )
                await vm.loadAll()
                onDismiss()
                dismiss()
            } else {
                try await purchasePaidPlan(plan)
            }
        } catch {
            errorMessage = error.localizedDescription.isEmpty ? "Something went wrong. Please try again." : error.localizedDescription
        }
    }

    private func purchasePaidPlan(_ plan: MentorshipPlan) async throws {
        guard let product = productsById[plan.stripePriceId] else {
            errorMessage = "This plan is not available for purchase on this device."
            return
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            try await MentorshipService.shared.finalizeRelationship(
                mentorId: mentor.id,
                planId: plan.id,
                planName: plan.name,
                subscriptionId: String(transaction.id),
                mentorName: mentor.name,
                mentorPhotoURL: mentor.photoURL
            )
            await transaction.finish()
            await vm.loadAll()
            successMessage = "Purchase complete."
            onDismiss()
            dismiss()
        case .userCancelled:
            errorMessage = "Purchase cancelled."
        case .pending:
            errorMessage = "Purchase pending approval."
        @unknown default:
            errorMessage = "The App Store returned an unknown purchase state."
        }
    }

    private func restorePurchases() async {
        isProcessing = true
        errorMessage = nil
        successMessage = nil
        defer { isProcessing = false }
        do {
            try await AppStore.sync()
            successMessage = "Purchases restored."
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "MentorshipStoreKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transaction could not be verified."])
        case .verified(let safe):
            return safe
        }
    }
}

private struct PlanCard: View {
    let plan: MentorshipPlan
    let product: Product?
    let isSelected: Bool

    private let accentPurple = Color(red: 0.49, green: 0.23, blue: 0.93)
    private let accentGreen = Color(red: 0.09, green: 0.64, blue: 0.29)

    private var badgeColor: Color {
        plan.isFree ? accentGreen : accentPurple
    }

    private var sessionLabel: String {
        let count = plan.sessionsPerMonth
        return "\(count) session\(count == 1 ? "" : "s") per month"
    }

    private var priceLabel: String {
        product?.displayPrice ?? plan.priceLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Text(plan.description)
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
            featuresList
        }
        .padding(16)
        .background(isSelected ? accentPurple.opacity(0.05) : Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? accentPurple : Color.primary.opacity(0.07), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .cornerRadius(14)
    }

    private var headerRow: some View {
        HStack {
            Text(plan.name).font(.systemScaled(15, weight: .bold))
            if let badge = plan.badge {
                Text(badge)
                    .font(.systemScaled(9, weight: .bold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeColor.opacity(0.10)))
            }
            Spacer()
            Text(priceLabel).font(.systemScaled(17, weight: .bold))
        }
    }

    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlanFeatureRow(text: sessionLabel, included: true)
            PlanFeatureRow(text: "1:1 Chat", included: plan.includesChat)
            PlanFeatureRow(text: "Weekly Check-ins", included: plan.includesCheckIns)
            PlanFeatureRow(text: "Custom Growth Plan", included: plan.includesCustomPlan)
        }
    }
}

private struct PlanFeatureRow: View {
    let text: String
    let included: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: included ? "checkmark" : "xmark")
                .font(.systemScaled(10, weight: .semibold))
                .foregroundStyle(included ? Color(red: 0.09, green: 0.64, blue: 0.29) : Color(.systemGray3))
            Text(text)
                .font(.systemScaled(12))
                .foregroundStyle(included ? .primary : .secondary)
        }
    }
}
