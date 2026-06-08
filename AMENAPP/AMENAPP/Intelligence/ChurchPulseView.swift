// ChurchPulseView.swift
// AMENAPP — Church Pulse View
//
// Renders a computed church-health snapshot derived from real Firestore data.
//
// Design rules enforced here:
//   - Pulse score shown as a visual progress bar only — NOT as a raw number
//     (raw value IS available to accessibility via .accessibilityValue)
//   - NO spectacle counters: no "N members", no "N praying right now"
//   - Volunteer roles shown as chips — qualitative, not count-driven
//   - Prayer presence shown as a single sentence — not a count
//   - "Why this score" expandable section shows pulseReasons
//   - All four view states rendered: loading, loaded, empty, error

import SwiftUI

// MARK: - ChurchPulseView

struct ChurchPulseView: View {

    @StateObject private var viewModel: ChurchPulseViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(churchId: String) {
        _viewModel = StateObject(wrappedValue: ChurchPulseViewModel(churchId: churchId))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                loadingView
            case .loaded(let pulse):
                pulseContent(pulse)
            case .empty:
                emptyView
            case .error(let message):
                errorView(message: message)
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
            Text("Loading church pulse…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityLabel("Loading church pulse")
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)

            Text("No activity yet")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("This church hasn't posted events, prayer requests, or teachings yet. Check back soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityLabel("No church activity available yet")
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(40))
                .foregroundStyle(.secondary)

            Text("Couldn't load pulse")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text("Try Again")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading church pulse")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func pulseContent(_ pulse: ChurchPulse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                healthSection(pulse)
                Divider().padding(.horizontal, 4)
                eventsSection(pulse)
                prayerSection(pulse)
                if !pulse.volunteerNeeds.roles.isEmpty {
                    serveSection(pulse)
                }
                if let topic = pulse.recentTeachingTopic {
                    teachingSection(topic: topic)
                }
                whyScoreSection(pulse)
                footerSection(pulse)
            }
            .padding(16)
        }
    }

    // MARK: - Health indicator (score bar, qualitative label)

    private func healthSection(_ pulse: ChurchPulse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Community Health", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                // Qualitative label only — raw number hidden from visual display
                Text(pulse.healthLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(healthLabelColor(pulse.pulseScore))
                    .accessibilityHidden(true)   // label already in progress bar a11y
            }

            // Progress bar — score NOT shown as a number label
            ProgressView(value: Double(pulse.pulseScore), total: 100)
                .progressViewStyle(.linear)
                .tint(healthBarTint(pulse.pulseScore))
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
                // Accessibility reads the score for assistive tech, but it is
                // NOT rendered as visible text per the spectacle-counter rule.
                .accessibilityLabel("Community health: \(pulse.healthLabel)")
                .accessibilityValue("\(pulse.pulseScore) out of 100")

            Text(pulse.memberEngagement.displayLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Community health: \(pulse.healthLabel). \(pulse.memberEngagement.displayLabel).")
    }

    // MARK: - Upcoming events

    private func eventsSection(_ pulse: ChurchPulse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Upcoming Events", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.primary)

            if pulse.upcomingEvents.count == 0 {
                Text("No upcoming events scheduled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Next event details (factual count is ok — it is not a vanity metric)
                if let title = pulse.upcomingEvents.nextEventTitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        if let dateStr = pulse.upcomingEvents.formattedNextEventDate {
                            Text(dateStr)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                let count = pulse.upcomingEvents.count
                let label = count == 1 ? "1 event coming up" : "\(count) events coming up"
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Prayer section (presence only, no count)

    private func prayerSection(_ pulse: ChurchPulse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Prayer", systemImage: "hands.sparkles")
                .font(.headline)
                .foregroundStyle(.primary)

            if pulse.activePrayerRequests.count > 0 {
                Text("Your church community has active prayer requests. Join in prayer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No active public prayer requests right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Serve opportunities (roles as chips, not count-driven)

    private func serveSection(_ pulse: ChurchPulse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Serve Opportunities", systemImage: "figure.2.arms.open")
                .font(.headline)
                .foregroundStyle(.primary)

            FlowChips(items: pulse.volunteerNeeds.roles)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Serve opportunities: \(pulse.volunteerNeeds.roles.joined(separator: ", "))")
    }

    // MARK: - Teaching topic

    private func teachingSection(topic: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Recent Teaching", systemImage: "book.closed")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(topic)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recent teaching: \(topic)")
    }

    // MARK: - Why this score (expandable)

    private func whyScoreSection(_ pulse: ChurchPulse) -> some View {
        WhyScoreDisclosure(reasons: pulse.pulseReasons)
    }

    // MARK: - Footer

    private func footerSection(_ pulse: ChurchPulse) -> some View {
        Text(pulse.lastUpdatedLabel)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
            .accessibilityLabel(pulse.lastUpdatedLabel)
    }

    // MARK: - Color helpers

    private func healthBarTint(_ score: Int) -> Color {
        switch score {
        case 90...100: return Color(red: 0.2, green: 0.7, blue: 0.4)
        case 70...89:  return Color(red: 0.3, green: 0.6, blue: 0.9)
        case 50...69:  return Color(red: 0.9, green: 0.6, blue: 0.2)
        default:       return Color(red: 0.7, green: 0.5, blue: 0.3)
        }
    }

    private func healthLabelColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return Color(red: 0.2, green: 0.7, blue: 0.4)
        case 70...89:  return Color(red: 0.3, green: 0.6, blue: 0.9)
        case 50...69:  return Color(red: 0.9, green: 0.6, blue: 0.2)
        default:       return .secondary
        }
    }
}

// MARK: - WhyScoreDisclosure

private struct WhyScoreDisclosure: View {
    let reasons: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.up.circle" : "info.circle")
                        .font(.caption)
                    Text("Why this score")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse score explanation" : "Expand score explanation")
            .accessibilityHint("Shows the factors contributing to this church's health score")

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if reasons.isEmpty {
                        Text("Not enough activity to generate reasons yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel("Score reasons: \(reasons.joined(separator: ". "))")
            }
        }
    }
}

// MARK: - FlowChips

/// Renders a list of strings as horizontal chips that wrap when needed.
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        // Use a simple wrapping layout via LazyVGrid with adaptive columns
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80, maximum: 200), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .lineLimit(1)
                    .accessibilityLabel(item)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Loaded") {
    let pulse = ChurchPulse(
        churchId: "preview_church",
        computedAt: Date().timeIntervalSince1970 * 1000 - 3_600_000,
        upcomingEvents: UpcomingEventsSnapshot(
            count: 3,
            nextEventTitle: "Sunday Service",
            nextEventDate: Date().addingTimeInterval(86400).timeIntervalSince1970 * 1000
        ),
        activePrayerRequests: ActivePrayerRequestsSnapshot(count: 4),
        volunteerNeeds: VolunteerNeedsSnapshot(count: 2, roles: ["Worship Team", "Children's Ministry"]),
        recentTeachingTopic: "The Sermon on the Mount",
        memberEngagement: .medium,
        pulseScore: 75,
        pulseReasons: [
            "3 events this month",
            "Active prayer requests",
            "Volunteer opportunities posted",
            "Recent teaching: The Sermon on the Mount",
            "Growing community engagement",
        ],
        finite: true,
        spectacleCounters: false
    )

    NavigationStack {
        ChurchPulseView(churchId: "preview_church")
            .navigationTitle("Grace Community")
            .navigationBarTitleDisplayMode(.large)
    }
    .onAppear {
        // Note: preview injects real ViewModel — swap if needed for unit tests
    }
}

#Preview("Empty") {
    let view = VStack {
        Image(systemName: "building.columns")
            .font(.systemScaled(48))
            .foregroundStyle(.secondary)
        Text("No activity yet")
            .font(.headline)
        Text("This church hasn't posted events, prayer requests, or teachings yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity, minHeight: 200)
    return view
}
#endif
