// MentorshipPlanSheet.swift
// AMENAPP
// Stripe-backed mentorship plan picker.

import SwiftUI

struct MentorshipPlanSheet: View {
    let mentor: Mentor
    @ObservedObject var vm: MentorshipViewModel
    let onDismiss: () -> Void

    @State private var selectedPlan: MentorshipPlan?
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
                    Button("Refresh Status") {
                        Task { await vm.loadAll() }
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .task {
            if selectedPlan == nil { selectedPlan = plans.first }
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
                PlanCard(plan: plan, isSelected: selected)
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
        .disabled(isProcessing || (!plan.isFree && plan.stripePriceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        .padding(.horizontal, 18)

        if !plan.isFree && plan.stripePriceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("This paid plan is missing its Stripe price configuration.")
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
    }

    private func primaryButtonTitle(for plan: MentorshipPlan) -> String {
        if plan.isFree { return "Start Free - \(plan.name)" }
        return "Start \(plan.name) - \(plan.priceLabel)"
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
                _ = try await MentorshipService.shared.createPaidRelationship(
                    mentorId: mentor.id,
                    planId: plan.id,
                    planName: plan.name,
                    stripePriceId: plan.stripePriceId,
                    mentorName: mentor.name,
                    mentorPhotoURL: mentor.photoURL
                )
                await vm.loadAll()
                successMessage = "Subscription started."
                onDismiss()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription.isEmpty ? "Something went wrong. Please try again." : error.localizedDescription
        }
    }
}

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

    private var priceLabel: String {
        plan.priceLabel
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
