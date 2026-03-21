// MentorProfileView.swift
// AMENAPP
// Full mentor profile sheet

import SwiftUI

struct MentorProfileView: View {
    let mentor: Mentor
    let relationship: MentorshipRelationship?
    let onRequestPlan: (MentorshipPlan) -> Void

    @State private var selectedPlanId: String? = nil
    @State private var bioExpanded = false
    @Environment(\.dismiss) private var dismiss

    private var plans: [MentorshipPlan] {
        mentor.plans.isEmpty ? MentorshipPlan.defaultPlans() : mentor.plans
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    profileHeader

                    // Availability badge
                    availabilityBadge

                    // Bio
                    bioSection

                    // Specialties cloud
                    specialtiesSection

                    // Plans
                    plansSection

                    // CTA
                    if let planId = selectedPlanId,
                       let plan = plans.first(where: { $0.id == planId }) {
                        Button {
                            onRequestPlan(plan)
                            dismiss()
                        } label: {
                            Text("Continue with \(plan.name)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(red: 0.49, green: 0.23, blue: 0.93))
                                )
                        }
                        .padding(.horizontal, 18)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 20)
            }
            .navigationTitle(mentor.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { selectedPlanId = plans.first?.id }
    }

    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 10) {
            MentorAvatarView(name: mentor.name, photoURL: mentor.photoURL, size: 72)

            HStack(spacing: 6) {
                Text(mentor.name)
                    .font(.system(size: 20, weight: .bold))
                if mentor.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.82))
                }
            }

            Text("\(mentor.role) · \(mentor.church)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                    Text(String(format: "%.1f", mentor.rating))
                        .font(.system(size: 13, weight: .semibold))
                }
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    Text("\(mentor.sessionCount) sessions")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Availability Badge
    private var availabilityBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mentor.availabilityStatus.dotColor)
                .frame(width: 8, height: 8)
            Text(mentor.availabilityStatus.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mentor.availabilityStatus.color)
            if mentor.spotsAvailable > 0 {
                Text("· \(mentor.spotsAvailable) spots available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(mentor.availabilityStatus.color.opacity(0.10))
        )
    }

    // MARK: - Bio Section
    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 8) {
                Text(mentor.bio)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(bioExpanded ? nil : 3)
                    .animation(.easeInOut(duration: 0.25), value: bioExpanded)

                if mentor.bio.count > 120 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { bioExpanded.toggle() }
                    } label: {
                        Text(bioExpanded ? "Show less" : "Read more")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.49, green: 0.23, blue: 0.93))
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Specialties Section
    private var specialtiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Specialties")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)

            FlowLayout(spacing: 8) {
                ForEach(mentor.specialties, id: \.self) { spec in
                    Text(spec)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.49, green: 0.23, blue: 0.93))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.10))
                        )
                }
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Plans Section
    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mentorship Plans")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)

            VStack(spacing: 10) {
                ForEach(plans) { plan in
                    MentorProfilePlanCard(plan: plan, isSelected: selectedPlanId == plan.id)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                selectedPlanId = plan.id
                            }
                        }
                }
            }
            .padding(.horizontal, 18)
        }
    }
}

// MARK: - Plan Card for Profile View
private struct MentorProfilePlanCard: View {
    let plan: MentorshipPlan
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plan.name).font(.system(size: 14, weight: .bold))
                if let badge = plan.badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(plan.isFree ? Color(red: 0.09, green: 0.64, blue: 0.29) : Color(red: 0.49, green: 0.23, blue: 0.93))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(
                            Capsule().fill((plan.isFree ? Color(red: 0.09, green: 0.64, blue: 0.29) : Color(red: 0.49, green: 0.23, blue: 0.93)).opacity(0.10))
                        )
                }
                Spacer()
                Text(plan.priceLabel).font(.system(size: 16, weight: .bold))
            }
            Text(plan.description).font(.system(size: 12)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                MentorPlanFeatureRow(text: "\(plan.sessionsPerMonth) session\(plan.sessionsPerMonth == 1 ? "" : "s") per month", included: true)
                MentorPlanFeatureRow(text: "1:1 Chat", included: plan.includesChat)
                MentorPlanFeatureRow(text: "Weekly Check-ins", included: plan.includesCheckIns)
                MentorPlanFeatureRow(text: "Custom Growth Plan", included: plan.includesCustomPlan)
            }
        }
        .padding(14)
        .background(isSelected ? Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.05) : Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color(red: 0.49, green: 0.23, blue: 0.93) : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .cornerRadius(14)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

private struct MentorPlanFeatureRow: View {
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
