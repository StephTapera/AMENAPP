// MentorshipPlanSheet.swift
// AMENAPP
// Plan picker + Stripe native PaymentSheet.
// StripePaymentSheet is linked via SPM (stripe-ios ≥ 25.8.0).
// When the Stripe package isn't available yet, paid plans show a
// placeholder message instead of crashing at compile time.

import SwiftUI
#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif

struct MentorshipPlanSheet: View {
    let mentor: Mentor
    @ObservedObject var vm: MentorshipViewModel
    let onDismiss: () -> Void

    @State private var selectedPlan: MentorshipPlan?
    @State private var isProcessing = false
    #if canImport(StripePaymentSheet)
    @State private var paymentSheet: PaymentSheet?
    @State private var paymentSheetPresented = false
    #endif
    @State private var pendingSubscriptionId: String?
    @State private var pendingPlan: MentorshipPlan?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var plans: [MentorshipPlan] {
        mentor.plans.isEmpty ? MentorshipPlan.defaultPlans() : mentor.plans
    }

    var body: some View {
        NavigationStack {
            planScrollContent
                .navigationTitle("Choose a Plan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        #if canImport(StripePaymentSheet)
        .modifier(
            OptionalPaymentSheetModifier(
                isPresented: $paymentSheetPresented,
                paymentSheet: paymentSheet,
                onCompletion: { result in
                    Task { await handlePaymentResult(result) }
                }
            )
        )
        #endif
        .onAppear { selectedPlan = plans.first }
    }

    @ViewBuilder
    private var planScrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                mentorHeader
                planCardsList

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
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

    @ViewBuilder
    private var planCardsList: some View {
        VStack(spacing: 12) {
            ForEach(plans) { plan in
                let selected = selectedPlan?.id == plan.id
                PlanCard(plan: plan, isSelected: selected)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            selectedPlan = plan
                        }
                    }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var mentorHeader: some View {
        HStack(spacing: 12) {
            MentorAvatarView(name: mentor.name, photoURL: mentor.photoURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mentorship with \(mentor.name)")
                    .font(.system(size: 15, weight: .semibold))
                Text(mentor.role)
                    .font(.system(size: 11))
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
                Text(plan.isFree ? "Start Free — \(plan.name)" : "Continue — \(plan.priceLabel)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.49, green: 0.23, blue: 0.93))
            )
        }
        .disabled(isProcessing)
        .padding(.horizontal, 18)
    }

    // MARK: - Logic

    private func handlePlanSelection(_ plan: MentorshipPlan) async {
        isProcessing = true
        errorMessage = nil
        do {
            if plan.isFree {
                _ = try await MentorshipService.shared.createFreeRelationship(
                    mentorId: mentor.id, planId: plan.id, planName: plan.name,
                    mentorName: mentor.name, mentorPhotoURL: mentor.photoURL
                )
                await vm.loadAll()
                dismiss()
            } else {
                #if canImport(StripePaymentSheet)
                // Get PaymentIntent client secret from Cloud Function
                let (clientSecret, subscriptionId) = try await MentorshipService.shared.createPaidRelationship(
                    mentorId: mentor.id, planId: plan.id, planName: plan.name,
                    stripePriceId: plan.stripePriceId,
                    mentorName: mentor.name, mentorPhotoURL: mentor.photoURL
                )
                // Stash for use in completion handler
                pendingPlan = plan
                pendingSubscriptionId = subscriptionId

                // Configure PaymentSheet
                var config = PaymentSheet.Configuration()
                config.merchantDisplayName = "AMEN"
                config.applePay = .init(
                    merchantId: "merchant.com.amen.app",
                    merchantCountryCode: "US"
                )
                config.defaultBillingDetails.address.country = "US"
                config.allowsDelayedPaymentMethods = false

                paymentSheet = PaymentSheet(
                    paymentIntentClientSecret: clientSecret,
                    configuration: config
                )
                isProcessing = false
                paymentSheetPresented = true
                return
                #else
                errorMessage = "Payments are not available yet. Please update the app."
                dlog("⚠️ MentorshipPlanSheet: StripePaymentSheet not linked")
                #endif
            }
        } catch {
            errorMessage = "Something went wrong. Please try again."
            dlog("⚠️ MentorshipPlanSheet: \(error)")
        }
        isProcessing = false
    }

    #if canImport(StripePaymentSheet)
    private func handlePaymentResult(_ result: PaymentSheetResult) async {
        switch result {
        case .completed:
            guard let plan = pendingPlan, let subscriptionId = pendingSubscriptionId else { return }
            isProcessing = true
            do {
                try await MentorshipService.shared.finalizeRelationship(
                    mentorId: mentor.id, planId: plan.id, planName: plan.name,
                    subscriptionId: subscriptionId,
                    mentorName: mentor.name, mentorPhotoURL: mentor.photoURL
                )
                await vm.loadAll()
                dismiss()
            } catch {
                errorMessage = "Payment succeeded but setup failed. Please contact support."
                dlog("⚠️ MentorshipPlanSheet finalize: \(error)")
            }
            isProcessing = false

        case .canceled:
            break // user dismissed sheet — no error shown

        case .failed(let error):
            errorMessage = error.localizedDescription
            dlog("⚠️ MentorshipPlanSheet payment failed: \(error)")
        }
        pendingPlan = nil
        pendingSubscriptionId = nil
    }
    #endif
}

// MARK: - Plan Card

private struct PlanCard: View {
    let plan: MentorshipPlan
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Text(plan.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            featuresList
        }
        .padding(16)
        .background(isSelected ? accentPurple.opacity(0.05) : Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? accentPurple : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .cornerRadius(14)
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack {
            Text(plan.name).font(.system(size: 15, weight: .bold))
            if let badge = plan.badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeColor.opacity(0.10)))
            }
            Spacer()
            Text(plan.priceLabel).font(.system(size: 17, weight: .bold))
        }
    }

    @ViewBuilder
    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlanFeatureRow(text: sessionLabel, included: true)
            PlanFeatureRow(text: "1:1 Chat", included: plan.includesChat)
            PlanFeatureRow(text: "Weekly Check-ins", included: plan.includesCheckIns)
            PlanFeatureRow(text: "Custom Growth Plan", included: plan.includesCustomPlan)
        }
    }
}

#if canImport(StripePaymentSheet)
/// Applies the Stripe `.paymentSheet` modifier only when a non-nil PaymentSheet is available.
/// This avoids the type mismatch when the sheet hasn't been created yet.
private struct OptionalPaymentSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let paymentSheet: PaymentSheet?
    let onCompletion: @MainActor (PaymentSheetResult) -> Void

    func body(content: Content) -> some View {
        if let sheet = paymentSheet {
            content.paymentSheet(
                isPresented: $isPresented,
                paymentSheet: sheet,
                onCompletion: onCompletion
            )
        } else {
            content
        }
    }
}
#endif

private struct PlanFeatureRow: View {
    let text: String
    let included: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: included ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(included ? Color(red: 0.09, green: 0.64, blue: 0.29) : Color(.systemGray3))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(included ? .primary : .secondary)
        }
    }
}
