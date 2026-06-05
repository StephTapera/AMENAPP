import SwiftUI
import FirebaseFunctions

// MARK: - Models

struct WeeklyPrayerTrend: Identifiable {
    let id: String
    let topic: String
    let requestCount: Int
    let changeDirection: TrendDirection

    enum TrendDirection {
        case rising, stable, falling
        var icon: String {
            switch self {
            case .rising: return "arrow.up.right"
            case .stable: return "minus"
            case .falling: return "arrow.down.right"
            }
        }
        var color: Color {
            switch self {
            case .rising: return .orange
            case .stable: return .secondary
            case .falling: return .blue
            }
        }
    }
}

struct DiscussionTrendItem: Identifiable {
    let id: String
    let topic: String
    let messageCount: Int
    let uniqueParticipants: Int
    let peakDay: String
}

struct VolunteerGap: Identifiable {
    let id: String
    let role: String
    let ministry: String
    let urgency: GapUrgency
    let slotsNeeded: Int

    enum GapUrgency: String {
        case critical = "Critical"
        case moderate = "Moderate"
        case lowPriority = "Low Priority"

        var color: Color {
            switch self {
            case .critical: return .red
            case .moderate: return .orange
            case .lowPriority: return .secondary
            }
        }
    }
}

struct MemberEngagementSummary {
    let totalActiveMembers: Int
    let newMembersThisWeek: Int
    let prayerParticipants: Int
    let studyGroupAttendees: Int
    let firstTimeContributors: Int
    let atRiskMembersCount: Int

    static let preview = MemberEngagementSummary(
        totalActiveMembers: 284,
        newMembersThisWeek: 12,
        prayerParticipants: 97,
        studyGroupAttendees: 63,
        firstTimeContributors: 8,
        atRiskMembersCount: 3
    )
}

struct CommunityWeeklyRecap: Identifiable {
    let id: String
    let weekEnding: Date
    let communityName: String
    let healthScore: Double
    let healthScoreDelta: Double
    let prayerTrends: [WeeklyPrayerTrend]
    let discussionTrends: [DiscussionTrendItem]
    let volunteerGaps: [VolunteerGap]
    let engagement: MemberEngagementSummary
    let aiInsight: String
    let suggestedFollowUps: [SmartFollowUp]

    static let preview = CommunityWeeklyRecap(
        id: "recap-preview",
        weekEnding: Date(),
        communityName: "Grace Community Church",
        healthScore: 0.78,
        healthScoreDelta: 0.05,
        prayerTrends: [
            WeeklyPrayerTrend(id: "p1", topic: "Health & Healing", requestCount: 34, changeDirection: .rising),
            WeeklyPrayerTrend(id: "p2", topic: "Employment", requestCount: 18, changeDirection: .stable),
            WeeklyPrayerTrend(id: "p3", topic: "Family Restoration", requestCount: 12, changeDirection: .falling)
        ],
        discussionTrends: [
            DiscussionTrendItem(id: "d1", topic: "Sunday Sermon Q&A", messageCount: 142, uniqueParticipants: 38, peakDay: "Sunday"),
            DiscussionTrendItem(id: "d2", topic: "Men's Bible Study", messageCount: 67, uniqueParticipants: 14, peakDay: "Wednesday")
        ],
        volunteerGaps: [
            VolunteerGap(id: "v1", role: "Children's Ministry Leader", ministry: "Kids Church", urgency: .critical, slotsNeeded: 2),
            VolunteerGap(id: "v2", role: "Worship Team Vocalist", ministry: "Worship", urgency: .moderate, slotsNeeded: 1)
        ],
        engagement: .preview,
        aiInsight: "Prayer requests around health increased 41% this week — this may reflect the seasonal illness pattern seen in prior years. Consider a dedicated healing prayer night. Volunteer gap in children's ministry is approaching critical — three leaders flagged unavailability for next month.",
        suggestedFollowUps: [
            SmartFollowUp(id: "f1", title: "Schedule a Healing Prayer Night", context: "Prayer request trend", urgency: .high, requiresApproval: true),
            SmartFollowUp(id: "f2", title: "Recruit Children's Ministry Volunteers", context: "Critical volunteer gap", urgency: .critical, requiresApproval: true),
            SmartFollowUp(id: "f3", title: "Celebrate first-time contributors", context: "8 members posted for the first time", urgency: .low, requiresApproval: true)
        ]
    )
}

// MARK: - Smart Follow-Up

struct SmartFollowUp: Identifiable {
    let id: String
    let title: String
    let context: String
    let urgency: FollowUpUrgency
    let requiresApproval: Bool
    var isApproved: Bool = false

    enum FollowUpUrgency: String {
        case critical = "Critical"
        case high = "High"
        case medium = "Medium"
        case low = "Low"

        var color: Color {
            switch self {
            case .critical: return .red
            case .high: return .orange
            case .medium: return Color.amenGold
            case .low: return .secondary
            }
        }
    }
}

// MARK: - Main View

struct CommunityWeeklyRecapView: View {
    let recap: CommunityWeeklyRecap
    @State private var expandedSections: Set<String> = ["health", "prayer"]
    @State private var localFollowUps: [SmartFollowUp]
    @State private var pendingFollowUp: SmartFollowUp? = nil
    @State private var showFollowUpConfirmation = false
    @Environment(\.colorScheme) private var colorScheme

    init(recap: CommunityWeeklyRecap) {
        self.recap = recap
        self._localFollowUps = State(initialValue: recap.suggestedFollowUps)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                weekHeader
                healthSection
                aiInsightCard
                prayerTrendsSection
                discussionTrendsSection
                volunteerGapsSection
                engagementSection
                followUpsSection
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .confirmationDialog(
            "Approve follow-up action?",
            isPresented: $showFollowUpConfirmation,
            titleVisibility: .visible
        ) {
            if let fu = pendingFollowUp {
                Button("Approve: \(fu.title)") {
                    approveFollowUp(fu)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingFollowUp = nil
            }
        } message: {
            if let fu = pendingFollowUp {
                Text("This will initiate '\(fu.title)'. No outreach happens automatically — you'll be guided through the next steps.")
            }
        }
    }

    // MARK: - Header

    private var weekHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weekly Community Recap")
                .font(.title2.weight(.semibold))
            Text("Week ending \(recap.weekEnding.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(recap.communityName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.amenGold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Health Score

    private var healthSection: some View {
        CollapsibleSection(title: "Community Health", icon: "heart.fill", key: "health", expandedSections: $expandedSections) {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemFill), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: recap.healthScore)
                        .stroke(healthScoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(Int(recap.healthScore * 100))")
                            .font(.system(size: 28, weight: .bold))
                        Text("/ 100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 8) {
                    healthRow(label: "Active Members", value: "\(recap.engagement.totalActiveMembers)")
                    healthRow(label: "New This Week", value: "+\(recap.engagement.newMembersThisWeek)")
                    healthRow(label: "Prayer Participants", value: "\(recap.engagement.prayerParticipants)")
                    HStack {
                        Image(systemName: recap.healthScoreDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(recap.healthScoreDelta >= 0 ? .green : .red)
                        Text("\(abs(Int(recap.healthScoreDelta * 100))) pts this week")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func healthRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }

    private var healthScoreColor: Color {
        switch recap.healthScore {
        case 0.8...: return .green
        case 0.6..<0.8: return Color.amenGold
        default: return .orange
        }
    }

    // MARK: - AI Insight

    private var aiInsightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Community Insight", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Color.amenGold)
            Text(recap.aiInsight)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Text("This insight is private — only visible to community leaders.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.amenGold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.amenGold.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Prayer Trends

    private var prayerTrendsSection: some View {
        CollapsibleSection(title: "Prayer Request Trends", icon: "hands.sparkles.fill", key: "prayer", expandedSections: $expandedSections) {
            ForEach(recap.prayerTrends) { trend in
                HStack {
                    Text(trend.topic)
                        .font(.subheadline)
                    Spacer()
                    Text("\(trend.requestCount) requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: trend.changeDirection.icon)
                        .foregroundStyle(trend.changeDirection.color)
                        .font(.caption)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    // MARK: - Discussion Trends

    private var discussionTrendsSection: some View {
        CollapsibleSection(title: "Discussion Trends", icon: "bubble.left.and.bubble.right.fill", key: "discussion", expandedSections: $expandedSections) {
            ForEach(recap.discussionTrends) { trend in
                VStack(alignment: .leading, spacing: 4) {
                    Text(trend.topic)
                        .font(.subheadline.weight(.medium))
                    HStack {
                        Label("\(trend.messageCount) messages", systemImage: "bubble.left")
                        Label("\(trend.uniqueParticipants) people", systemImage: "person.2")
                        Spacer()
                        Text("Peak: \(trend.peakDay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    // MARK: - Volunteer Gaps

    private var volunteerGapsSection: some View {
        CollapsibleSection(title: "Volunteer Gaps", icon: "person.badge.plus", key: "volunteers", expandedSections: $expandedSections) {
            if recap.volunteerGaps.isEmpty {
                Text("No volunteer gaps detected this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recap.volunteerGaps) { gap in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gap.role)
                                .font(.subheadline.weight(.medium))
                            Text(gap.ministry)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(gap.urgency.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(gap.urgency.color)
                            Text("\(gap.slotsNeeded) needed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    // MARK: - Engagement

    private var engagementSection: some View {
        CollapsibleSection(title: "Member Engagement", icon: "person.3.fill", key: "engagement", expandedSections: $expandedSections) {
            let eng = recap.engagement
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                engagementCell(label: "Study Groups", value: "\(eng.studyGroupAttendees)")
                engagementCell(label: "First Posts", value: "\(eng.firstTimeContributors)", highlight: true)
                engagementCell(label: "Prayer Partners", value: "\(eng.prayerParticipants)")
                if eng.atRiskMembersCount > 0 {
                    engagementCell(label: "Needs Pastoral Care", value: "\(eng.atRiskMembersCount)", urgent: true)
                }
            }
        }
    }

    private func engagementCell(label: String, value: String, highlight: Bool = false, urgent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(urgent ? .red : (highlight ? Color.amenGold : .primary))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Follow-Ups

    private var followUpsSection: some View {
        CollapsibleSection(title: "Suggested Follow-Ups", icon: "arrow.right.circle.fill", key: "followups", expandedSections: $expandedSections) {
            Text("All follow-ups require your approval. Nothing is automated or sent without your explicit action.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            ForEach($localFollowUps) { $fu in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fu.title)
                            .font(.subheadline.weight(.medium))
                        Text(fu.context)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if fu.isApproved {
                        Label("Approved", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            pendingFollowUp = fu
                            showFollowUpConfirmation = true
                        } label: {
                            Text(fu.urgency.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(fu.urgency.color.opacity(0.15))
                                .foregroundStyle(fu.urgency.color)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private func approveFollowUp(_ followUp: SmartFollowUp) {
        guard let idx = localFollowUps.firstIndex(where: { $0.id == followUp.id }) else { return }
        localFollowUps[idx].isApproved = true
        pendingFollowUp = nil
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let key: String
    @Binding var expandedSections: Set<String>
    @ViewBuilder let content: () -> Content

    var isExpanded: Bool { expandedSections.contains(key) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    if isExpanded { expandedSections.remove(key) }
                    else { expandedSections.insert(key) }
                }
            } label: {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding()
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CommunityWeeklyRecapView(recap: .preview)
            .navigationTitle("Weekly Recap")
    }
}
