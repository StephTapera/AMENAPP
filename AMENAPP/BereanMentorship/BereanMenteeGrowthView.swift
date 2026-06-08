// BereanMenteeGrowthView.swift
// AMENAPP — Berean Mentorship OS — Mentee Growth Plan view
// Shown when isMentor == false. No public metrics.
// Swift 6, iOS 18+, SwiftUI.

import SwiftUI

// MARK: - Root view

struct BereanMenteeGrowthView: View {
    @StateObject private var service = BereanMentorshipService.shared
    @AppStorage("bereanMentorshipOS_enabled") private var isEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("berean_plus_enabled") private var isPlusEnabled: Bool = true
    @State private var showMeetingPrep: Bool = false
    @State private var checkedGoals: Set<String> = []
    @State private var aiInsightText: String = ""

    var body: some View {
        Group {
            if !isEnabled {
                BereanMentorshipFeaturePlaceholder(
                    icon: "person.badge.shield.checkmark",
                    message: "Mentorship OS is not enabled.",
                    detail: "Turn on Berean Mentorship in Settings to grow with a mentor."
                )
            } else if service.myMentorships.isEmpty && !service.isLoading {
                findMentorPrompt
            } else {
                growthContent
            }
        }
        .navigationTitle("Growth Plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMeetingPrep) {
            MeetingPrepSheet(plan: service.menteeGrowthPlan)
        }
        .onAppear {
            Task {
                await service.loadMentorships()
                if let mentorship = service.myMentorships.first(where: { _ in !service.isMentor })
                                    ?? service.myMentorships.first {
                    try? await service.fetchGrowthPlan(mentorshipId: mentorship.id)
                }
            }
        }
    }

    // MARK: - Find mentor prompt

    private var findMentorPrompt: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.systemScaled(48, weight: .ultraLight))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .accessibilityHidden(true)
                Text("Find a Mentor")
                    .font(.title2).bold()
                    .foregroundStyle(Color.primary)
                Text("Connect with a mentor in your church community to receive a personalised growth plan.")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Find a Mentor. Connect with a mentor in your church community to receive a personalised growth plan.")
    }

    // MARK: - Growth content

    @ViewBuilder
    private var growthContent: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if service.isLoading && service.menteeGrowthPlan == nil {
                loadingView
            } else if let plan = service.menteeGrowthPlan {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        goalsSection(plan: plan)
                        currentStudySection(plan: plan)
                        nextSessionSection(plan: plan)
                        milestonesSection(plan: plan)
                        suggestedResourcesSection(plan: plan)
                        prayerForMentorSection
                        aiInsightPanel
                    }
                    .padding(.bottom, 48)
                }
                .task {
                    // Wire to MentorshipIntelligenceService.shared when available
                    // aiInsightText = await service.growthInsight(...)
                }
                .refreshable {
                    await service.loadMentorships()
                    if let m = service.myMentorships.first {
                        try? await service.fetchGrowthPlan(mentorshipId: m.id)
                    }
                }
            } else {
                loadingView
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Color.accentColor)
            Text("Loading your growth plan...")
                .font(.systemScaled(14))
                .foregroundStyle(Color.secondary)
        }
        .accessibilityLabel("Loading your growth plan")
    }

    // MARK: - Goals section

    private func goalsSection(plan: BereanMenteeGrowthPlan) -> some View {
        BereanMentorshipSection(title: "YOUR GROWTH PLAN", icon: "target") {
            if plan.goals.isEmpty {
                Text("No goals set yet. Talk with your mentor.")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            } else {
                ForEach(Array(plan.goals.enumerated()), id: \.offset) { _, goal in
                    ChecklistRow(text: goal, isChecked: checkedGoals.contains(goal)) {
                        if checkedGoals.contains(goal) { checkedGoals.remove(goal) }
                        else { checkedGoals.insert(goal) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                Text("These checkmarks are for meeting prep only — not saved.")
                    .font(.systemScaled(11))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Current study section

    @ViewBuilder
    private func currentStudySection(plan: BereanMenteeGrowthPlan) -> some View {
        if let study = plan.currentStudy {
            BereanMentorshipSection(title: "CURRENT STUDY", icon: "book.fill") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .font(.systemScaled(18))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(study)
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(Color.primary)
                        NavigationLink(destination: BereanStudyHomeView()) {
                            Text("Continue")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Continue \(study)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Next session section

    @ViewBuilder
    private func nextSessionSection(plan: BereanMenteeGrowthPlan) -> some View {
        if let date = plan.nextSessionDate {
            BereanMentorshipSection(title: "NEXT SESSION", icon: "calendar") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatSessionDate(date))
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(Color.primary)
                        Text("Prepare your questions and reflections.")
                            .font(.systemScaled(12))
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Button { showMeetingPrep = true } label: {
                        Text("Prepare")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .accessibilityLabel("Prepare for your session on \(formatSessionDate(date))")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Milestones section

    private func milestonesSection(plan: BereanMenteeGrowthPlan) -> some View {
        BereanMentorshipSection(title: "MILESTONES", icon: "star.fill") {
            if plan.milestones.isEmpty {
                Text("Complete sessions to earn milestones.")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(plan.milestones) { badge in
                            MilestoneBadgeView(badge: badge)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Suggested resources section

    private func suggestedResourcesSection(plan: BereanMenteeGrowthPlan) -> some View {
        BereanMentorshipSection(title: "SUGGESTED RESOURCES", icon: "books.vertical.fill") {
            if plan.suggestedResources.isEmpty {
                Text("No resources suggested yet.")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            } else {
                ForEach(plan.suggestedResources.indices, id: \.self) { index in
                    let resource = plan.suggestedResources[index]
                    HStack(spacing: 12) {
                        Image(systemName: "book.circle")
                            .font(.systemScaled(20))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        Text(resource)
                            .font(.systemScaled(14))
                            .foregroundStyle(Color.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Suggested resource: \(resource)")

                    Divider()
                        .background(Color(UIColor.separator))
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Prayer for mentor section

    private var prayerForMentorSection: some View {
        BereanMentorshipSection(title: "PRAYER", icon: "hands.and.sparkles.fill") {
            Button {
                logLocalPrayerForMentor()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hands.and.sparkles")
                        .font(.systemScaled(18))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("Pray for my mentor")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                        .padding(.horizontal, 20)
                )
            }
            .accessibilityLabel("Pray for my mentor")
            .accessibilityHint("Logs a prayer note for your mentor")
            .padding(.bottom, 12)
        }
    }

    // MARK: - AI Insight Panel (PLUS+ tier only)
    // Shows Berean growth observations from Memory Graph.
    // Non-comparative, non-streak-shaming. Private to this user.

    private var aiInsightPanel: some View {
        Group {
            if isPlusEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        Text("Berean Insights")
                            .font(.headline)
                        Spacer()
                        Text("Private to you")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }

                    if aiInsightText.isEmpty {
                        Text("Complete a few more sessions for Berean to notice growth patterns.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text(aiInsightText)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                            .lineSpacing(4)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
            } else {
                // FREE tier upgrade CTA
                VStack(spacing: 8) {
                    Text("Upgrade to Amen+ for AI growth insights")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Helpers

    private func formatSessionDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return fmt.string(from: date)
    }

    private func logLocalPrayerForMentor() {
        var log = UserDefaults.standard.stringArray(forKey: "bereanMentorship_localPrayerLog") ?? []
        log.append(ISO8601DateFormatter().string(from: Date()))
        UserDefaults.standard.set(log, forKey: "bereanMentorship_localPrayerLog")
    }
}

// MARK: - Section container

private struct BereanMentorshipSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.systemScaled(11))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(2)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 14)

            content()
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Checklist row

private struct ChecklistRow: View {
    let text: String
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.systemScaled(20))
                    .foregroundStyle(isChecked ? Color(hex: "#4CAF82") : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
                Text(text)
                    .font(.systemScaled(14))
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    .strikethrough(isChecked)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityValue(isChecked ? "checked" : "unchecked")
        .accessibilityHint("Double-tap to toggle")
    }
}

// MARK: - Milestone badge view

struct MilestoneBadgeView: View {
    let badge: BereanMilestoneBadge

    private var earnedDateText: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: badge.earnedAt)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: badge.iconName)
                .font(.systemScaled(28, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(badge.title)
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(earnedDateText)
                .font(.systemScaled(9))
                .foregroundStyle(Color.secondary)
        }
        .frame(width: 80, height: 100)
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title), earned \(earnedDateText)")
    }
}

// MARK: - Meeting prep sheet

struct MeetingPrepSheet: View {
    let plan: BereanMenteeGrowthPlan?
    @Environment(\.dismiss) private var dismiss
    @State private var checkedItems: Set<String> = []

    private var staticItems: [String] {
        ["Review my goals", "Prepare questions for my mentor", "Review current study material"]
    }

    private var allItems: [String] {
        let extras = plan?.goals ?? []
        return (staticItems + extras).reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }
    }

    private var allChecked: Bool {
        Set(allItems).isSubset(of: checkedItems)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Work through this checklist before your session.")
                            .font(.systemScaled(13))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 16)

                        ForEach(allItems, id: \.self) { item in
                            PrepCheckRow(text: item, isChecked: checkedItems.contains(item)) {
                                if checkedItems.contains(item) { checkedItems.remove(item) }
                                else { checkedItems.insert(item) }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 6)

                            Divider()
                                .background(Color(UIColor.separator))
                                .padding(.horizontal, 24)
                        }

                        Spacer(minLength: 32)

                        Button { dismiss() } label: {
                            Text(allChecked ? "Ready for session!" : "Close")
                                .font(.systemScaled(16, weight: .semibold))
                                .foregroundStyle(allChecked ? Color(.systemBackground) : Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    allChecked
                                        ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(Color.clear),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                                .overlay(
                                    allChecked ? nil :
                                        AnyView(RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                                )
                        }
                        .padding(.horizontal, 24)
                        .accessibilityLabel(allChecked ? "Ready for session — dismiss" : "Close meeting prep")
                    }
                }
            }
            .navigationTitle("Session Prep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.secondary)
                        .accessibilityLabel("Close session prep")
                }
            }
        }
    }
}

// MARK: - Prep check row

private struct PrepCheckRow: View {
    let text: String
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.systemScaled(22))
                    .foregroundStyle(isChecked ? Color(hex: "#4CAF82") : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
                Text(text)
                    .font(.systemScaled(15))
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    .strikethrough(isChecked)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityValue(isChecked ? "checked" : "unchecked")
        .accessibilityHint("Double-tap to toggle")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Mentee Growth View") {
    NavigationStack {
        BereanMenteeGrowthView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Milestone Badge") {
    MilestoneBadgeView(badge: BereanMentorshipMockData.growthPlan.milestones[0])
        .padding()
        .background(Color(.systemBackground))
}

#Preview("Meeting Prep Sheet") {
    MeetingPrepSheet(plan: BereanMentorshipMockData.growthPlan)
}
#endif
