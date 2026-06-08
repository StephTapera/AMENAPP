// AmenMyStudyPlansView.swift
// AMENAPP
//
// Displays the user's active and completed study plans with progress tracking.
// Liquid Glass card style, empty state, loading-aware.

import SwiftUI

// MARK: - Main View

struct AmenMyStudyPlansView: View {

    @ObservedObject private var builder = AmenStudyPlanBuilder.shared
    @Environment(\.dismiss) private var dismiss

    private var activePlans: [AmenStudyPlan] {
        builder.activePlans.filter { !$0.isCompleted }
    }

    private var completedPlans: [AmenStudyPlan] {
        builder.activePlans.filter { $0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            Group {
                if builder.isBuilding {
                    loadingState
                } else if builder.activePlans.isEmpty {
                    emptyState
                } else {
                    plansList
                }
            }
            .navigationTitle("My Study Plans")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { builder.loadPlans() }
        }
    }

    // MARK: - Lists

    private var plansList: some View {
        ScrollView {
            VStack(spacing: 28) {
                if !activePlans.isEmpty {
                    plansSection(title: "In Progress", icon: "book.pages", plans: activePlans)
                }
                if !completedPlans.isEmpty {
                    plansSection(title: "Completed", icon: "checkmark.seal.fill", plans: completedPlans)
                }
                Spacer().frame(height: 40)
            }
            .padding(.top, 8)
        }
    }

    private func plansSection(title: String, icon: String, plans: [AmenStudyPlan]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal, 20)

            ForEach(plans) { plan in
                AMSPlanCard(plan: plan)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.systemScaled(56, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No Study Plans Yet")
                .font(.title3.weight(.semibold))
            Text("Start a study plan from any book in the library to begin your journey.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Loading your plans…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Plan Card

private struct AMSPlanCard: View {

    let plan: AmenStudyPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(plan.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(plan.isCompleted ? Color.green : Color.accentColor)
                            .frame(width: geo.size.width * plan.progress, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(Int(plan.progress * 100))% complete")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !plan.isCompleted, let today = plan.currentDay {
                        Text("Day \(today.dayNumber): \(today.title)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            // Source row
            HStack(spacing: 4) {
                Image(systemName: plan.source.cardIcon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(plan.sourceTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Text(plan.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.title). \(Int(plan.progress * 100))% complete.")
    }

    @ViewBuilder
    private var statusBadge: some View {
        if plan.isCompleted {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.title3)
        } else {
            Text("\(plan.days.filter(\.isCompleted).count)/\(plan.days.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
    }
}

// MARK: - Source Icon

private extension AmenStudyPlanSource {
    var cardIcon: String {
        switch self {
        case .book:          return "book"
        case .topic:         return "tag"
        case .sermon:        return "mic"
        case .devotional:    return "heart"
        case .scripture:     return "text.book.closed"
        case .bereanAnswer:  return "sparkles"
        }
    }
}

// MARK: - Preview

#Preview {
    let days = (1...7).map { i in
        AmenStudyDay(dayNumber: i, title: "Day \(i)", readingExcerpt: nil,
                     scriptureFocus: "John \(i):1", reflectionPrompt: "Reflect", prayerPrompt: "Pray")
    }
    var plan = AmenStudyPlan(
        id: "preview", title: "The Cost of Discipleship", subtitle: "7-day study",
        source: .book, sourceTitle: "Dietrich Bonhoeffer",
        createdAt: Date(), days: days, currentDayIndex: 2, isCompleted: false
    )
    plan.days[0].isCompleted = true
    plan.days[1].isCompleted = true

    return AmenMyStudyPlansView()
}
