import SwiftUI
import Foundation

// MARK: - AmenDailyDigestView
//
// Placement: inserted at the TOP of the Home tab, above the existing feed.
// The feed below is never removed — this surface is purely additive.
//
// Feature-flagged via AppStorage key "spiritualOS_daily_enabled" (matches
// Remote Config flag name exactly). Renders EmptyView when flag is false.

struct AmenDailyDigestView: View {

    @ObservedObject var viewModel: AmenDailyDigestViewModel
    var userId: String

    // Feature flag — key must match Remote Config exactly
    @AppStorage("spiritualOS_daily_enabled") private var isEnabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Category filter state
    @State private var selectedFilter: DigestFilter = .all

    var body: some View {
        if !isEnabled {
            EmptyView()
        } else {
            content
                .task {
                    await viewModel.load(userId: userId)
                }
        }
    }

    // MARK: - Main content

    private var content: some View {
        VStack(spacing: 16) {
            // Greeting header
            greetingHeader

            // Category filter chips
            filterChipRow

            // "Today" section label
            Text("Today")
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Color.amenSlate.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Timeline body
            timelineBody
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Greeting header

    private var greetingHeader: some View {
        Text(viewModel.greeting)
            .font(.systemScaled(28, weight: .light))
            .foregroundStyle(Color.amenBlack)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(viewModel.greeting.isEmpty
                ? "Good \(viewModel.timeOfDay)"
                : viewModel.greeting)
    }

    // MARK: - Filter chip row

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DigestFilter.allCases) { filter in
                    GlassChip(
                        label: filter.label,
                        icon: filter.icon,
                        tint: filter.tint,
                        size: .compact,
                        isActive: selectedFilter == filter
                    ) {
                        withAnimation(.soAdaptive(reduceMotion: reduceMotion)) {
                            selectedFilter = filter
                        }
                    }
                    .accessibilityLabel(filter.accessibilityLabel)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Timeline body

    @ViewBuilder
    private var timelineBody: some View {
        if viewModel.isLoading {
            loadingSkeleton
        } else if filteredItems.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { item in
                    TimelineRow(
                        icon: item.type.sfSymbol,
                        iconTint: item.type.iconTint,
                        title: item.title,
                        subtitle: item.body,
                        timestamp: nil,
                        badge: item.isRead ? nil : .dot(item.type.iconTint),
                        isCompleted: item.isRead,
                        onTap: {
                            viewModel.markRead(itemId: item.id)
                            navigateIfNeeded(to: item.sourceRef)
                        }
                    )
                    .accessibilityHint("Double tap to open")
                }
            }
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                TimelineRow(
                    icon: "circle.fill",
                    iconTint: Color.amenSlate,
                    title: "Loading…",
                    subtitle: nil,
                    timestamp: nil,
                    badge: nil,
                    isCompleted: false,
                    onTap: nil
                )
                .opacity(0.3)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text("Your day is clear \u{2014} a good time for quiet prayer")
            .font(.subheadline)
            .foregroundStyle(Color.amenSlate)
            .multilineTextAlignment(.center)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Your day is clear, a good time for quiet prayer")
    }

    // MARK: - Filtered items

    private var filteredItems: [DigestItem] {
        switch selectedFilter {
        case .all:
            return viewModel.items
        case .verse:
            return viewModel.items.filter { $0.type == .verse || $0.type == .readingPlan || $0.type == .bereanStudy }
        case .prayer:
            return viewModel.items.filter { $0.type == .prayerReminder }
        case .events:
            return viewModel.items.filter { $0.type == .eventToday || $0.type == .spaceUpdate || $0.type == .birthday }
        case .mentions:
            return viewModel.items.filter { $0.type == .mention }
        }
    }

    // MARK: - Navigation helper

    private func navigateIfNeeded(to sourceRef: String?) {
        // Navigation is handled at the parent level via deep link / NavigationStack.
        // sourceRef is a path string (e.g. "spaces/abc123") that the parent coordinator
        // can interpret. This view surfaces the tap; routing is the caller's responsibility.
        guard let ref = sourceRef, !ref.isEmpty else { return }
        NotificationCenter.default.post(
            name: .amenDigestItemTapped,
            object: nil,
            userInfo: ["sourceRef": ref]
        )
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let amenDigestItemTapped = Notification.Name("amenDigestItemTapped")
}

// MARK: - DigestFilter

private enum DigestFilter: String, CaseIterable, Identifiable {
    case all      = "all"
    case verse    = "verse"
    case prayer   = "prayer"
    case events   = "events"
    case mentions = "mentions"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "All"
        case .verse:    return "Verse"
        case .prayer:   return "Prayer"
        case .events:   return "Events"
        case .mentions: return "Mentions"
        }
    }

    var icon: String? {
        switch self {
        case .all:      return "list.bullet"
        case .verse:    return "book.fill"
        case .prayer:   return "hands.sparkles"
        case .events:   return "calendar"
        case .mentions: return "at"
        }
    }

    var tint: Color {
        switch self {
        case .all:      return .accentColor
        case .verse:    return .amenPurple
        case .prayer:   return .amenBlue
        case .events:   return .accentColor
        case .mentions: return .amenSlate
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .all:      return "Show all items"
        case .verse:    return "Show verse and study items"
        case .prayer:   return "Show prayer reminders"
        case .events:   return "Show events and spaces"
        case .mentions: return "Show mentions"
        }
    }
}

// MARK: - DigestItemType view helpers

private extension DigestItemType {

    var sfSymbol: String {
        switch self {
        case .verse:          return "book.fill"
        case .prayerReminder: return "hands.sparkles"
        case .eventToday:     return "calendar"
        case .mention:        return "at"
        case .bereanStudy:    return "sparkles"
        case .birthday:       return "gift"
        case .spaceUpdate:    return "bubble.left.fill"
        case .readingPlan:    return "list.bullet"
        }
    }

    var iconTint: Color {
        switch self {
        case .verse, .bereanStudy, .readingPlan:
            return .amenPurple
        case .prayerReminder:
            return .amenBlue
        case .eventToday, .birthday, .spaceUpdate:
            return .accentColor
        case .mention:
            return .amenSlate
        }
    }
}
