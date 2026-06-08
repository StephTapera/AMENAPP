import SwiftUI
import Foundation

// MARK: - AmenLifePlannerSectionView
// Renders a "Today / Tomorrow" formation calendar at the top of ResourcesView.
// The view is purely additive — it never removes content below it.

struct AmenLifePlannerSectionView: View {

    var viewModel: AmenLifePlannerViewModel
    var userId: String

    @AppStorage("spiritualOS_planner_enabled") private var isEnabled = true

    // Date formatters — allocated once per view lifetime
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        if !isEnabled {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                plannerHeader
                Divider()
                    .padding(.horizontal, 16)

                if viewModel.isLoading {
                    loadingPlaceholder
                } else {
                    daySectionView(label: "Today",
                                   date: Date(),
                                   events: viewModel.todayEvents,
                                   isToday: true)

                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    daySectionView(label: "Tomorrow",
                                   date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                                   events: viewModel.tomorrowEvents,
                                   isToday: false)
                }
            }
            .task {
                await viewModel.load(userId: userId)
            }
        }
    }

    // MARK: - Header

    private var plannerHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Life Planner")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(Color.amenBlack)
                    .accessibilityAddTraits(.isHeader)

                Text(Self.dayFormatter.string(from: Date()))
                    .font(.caption)
                    .foregroundStyle(Color.amenSlate)
            }

            Spacer()

            GlassChip(
                label: "Add",
                icon: "plus",
                tint: .accentColor,
                size: .compact,
                isActive: false,
                action: nil   // wired by parent when AddEvent sheet is implemented
            )
            .accessibilityLabel("Add planner event")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Day Section

    @ViewBuilder
    private func daySectionView(
        label: String,
        date: Date,
        events: [PlannerEvent],
        isToday: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            // Section header row
            HStack(spacing: 8) {
                GlassChip(
                    label: label,
                    tint: .accentColor,
                    size: .compact,
                    isActive: isToday
                )
                .accessibilityLabel("\(label), \(Self.dayFormatter.string(from: date))")
                .accessibilityAddTraits(isToday ? [.isSelected] : [])

                Text(Self.shortDateFormatter.string(from: date))
                    .font(.caption)
                    .foregroundStyle(Color.amenSlate)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Events or empty state
            if events.isEmpty {
                if isToday {
                    Text("A clear day — a good time for rest or prayer")
                        .font(.subheadline)
                        .foregroundStyle(Color.amenSlate)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .accessibilityLabel("No events today. A clear day — a good time for rest or prayer")
                }
                // Tomorrow empty state is deliberately silent — no comparative count
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(events) { event in
                        TimelineRow(
                            icon: iconName(for: event.type),
                            iconTint: iconTint(for: event.type),
                            title: event.title,
                            subtitle: event.subtitle,
                            timestamp: event.endTime == nil ? nil : event.startTime,
                            badge: badgeForEvent(event),
                            isCompleted: false,
                            onTap: nil
                        )
                        .padding(.horizontal, 16)
                        .accessibilityLabel(accessibilityLabel(for: event))
                        .accessibilityHint("Tap for event details")
                    }
                }
            }

            // Berean suggestions — only shown in Today section
            if isToday, viewModel.todaySuggestion != nil {
                bereanSuggestionsSection
            }
        }
    }

    // MARK: - Berean Suggestions

    private var bereanSuggestionsSection: some View {
        Group {
            if let note = viewModel.todaySuggestion {
                GlassCard(tint: .amenPurple, elevated: false) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(Color.amenPurple)
                            .accessibilityHidden(true)

                        Text(note)
                            .font(.systemScaled(14))
                            .foregroundStyle(Color.amenSlate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Berean suggestion: \(note)")
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.amenSlate.opacity(0.15))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.amenSlate.opacity(0.15))
                            .frame(height: 14)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.amenSlate.opacity(0.10))
                            .frame(width: 100, height: 11)
                    }
                }
                .padding(.horizontal, 16)
                .opacity(0.3)
            }
        }
        .padding(.vertical, 16)
        .accessibilityLabel("Loading planner events")
    }

    // MARK: - Event type helpers

    private func iconName(for type: PlannerEventType) -> String {
        switch type {
        case .church:    return "person.3.fill"
        case .prayer:    return "hands.sparkles"
        case .birthday:  return "birthday.cake"
        case .volunteer: return "heart.fill"
        case .reading:   return "book.fill"
        }
    }

    private func iconTint(for type: PlannerEventType) -> Color {
        switch type {
        case .church, .volunteer: return .amenBlue
        case .prayer, .reading:   return .amenPurple
        case .birthday:           return .accentColor
        }
    }

    private func badgeForEvent(_ event: PlannerEvent) -> TimelineRowBadge? {
        switch event.type {
        case .church:    return .dot(Color.amenBlue)
        case .reading:   return .tag("Reading", .amenPurple)
        case .prayer:    return .tag("Prayer", .amenPurple)
        case .volunteer: return .tag("Volunteer", .amenBlue)
        case .birthday:  return nil
        }
    }

    private func accessibilityLabel(for event: PlannerEvent) -> String {
        let timeString = event.endTime == nil
            ? "all day"
            : Self.timeFormatter.string(from: event.startTime)
        return "\(event.title), \(timeString)"
    }
}
