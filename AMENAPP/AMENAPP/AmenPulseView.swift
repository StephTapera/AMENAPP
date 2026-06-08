//
//  AmenPulseView.swift
//  AMENAPP
//
//  AMEN Pulse — Relationship Intelligence Center.
//  Replaces the flat activity inbox with category-stacked expandable cards,
//  a morning greeting hero, and a pulse-mode selector (Focus / Balanced / Everything).
//
//  Coexists with AMENNotificationsView.swift — never deletes it.
//  "See Full Activity" links to AMENNotificationsView via a sheet.
//

import SwiftUI
import FirebaseAuth

// MARK: - PulseMode

enum PulseMode: String, CaseIterable {
    case focus      = "Focus"
    case balanced   = "Balanced"
    case everything = "Everything"
}

// MARK: - PulseCategory

struct PulseCategory: Identifiable {
    let filter: ActivityFilterCategory
    let title: String
    let icon: String
    let gradient: [Color]
    let tintColor: Color

    var id: String { filter.rawValue }
}

// All six stacks, in display order.
private let allPulseCategories: [PulseCategory] = [
    PulseCategory(
        filter: .prayer,
        title: "Prayer",
        icon: "hands.sparkles.fill",
        gradient: [Color(hex: "#2D6A4F"), Color(hex: "#52B788")],
        tintColor: Color.green.opacity(0.12)
    ),
    PulseCategory(
        filter: .community,
        title: "Community",
        icon: "bubble.left.and.bubble.right.fill",
        gradient: [Color(hex: "#1D3557"), Color(hex: "#457B9D")],
        tintColor: Color.blue.opacity(0.10)
    ),
    PulseCategory(
        filter: .church,
        title: "Churches",
        icon: "building.columns.fill",
        gradient: [Color(hex: "#7B5E00"), Color(hex: "#D4A017")],
        tintColor: Color.yellow.opacity(0.10)
    ),
    PulseCategory(
        filter: .berean,
        title: "Berean",
        icon: "sparkles",
        gradient: [Color(hex: "#4A1A7A"), Color(hex: "#9D4EDD")],
        tintColor: Color.purple.opacity(0.10)
    ),
    PulseCategory(
        filter: .scripture,
        title: "Scripture",
        icon: "book.fill",
        gradient: [Color(hex: "#7A3B0A"), Color(hex: "#C96A1F")],
        tintColor: Color.orange.opacity(0.10)
    ),
    PulseCategory(
        filter: .important,
        title: "Urgent",
        icon: "exclamationmark.circle.fill",
        gradient: [Color(hex: "#7A1A1A"), Color(hex: "#D64045")],
        tintColor: Color.red.opacity(0.10)
    ),
]

// MARK: - AmenPulseView

public struct AmenPulseView: View {

    @StateObject private var viewModel = AMENNotificationsViewModel()
    @State private var pulseMode: PulseMode = .balanced
    @State private var showFullActivity = false
    @State private var expandedCategory: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Item Filtering

    private func items(for category: PulseCategory) -> [GroupedNotification] {
        // Pull from unfiltered raw intelligence (ignore viewModel.selectedFilter)
        let all = AMENActivityIntelligenceEngine.process(viewModel.rawNotificationsUnfiltered)
        let base = all.filter { $0.category == category.filter }
        switch pulseMode {
        case .focus:      return base.filter { $0.priority <= .p1 }
        case .balanced:   return base.filter { $0.priority <= .p3 }
        case .everything: return base
        }
    }

    // Only show stacks that have items under the current mode.
    private var visibleStacks: [PulseCategory] {
        allPulseCategories.filter { !items(for: $0).isEmpty }
    }

    private var totalCount: Int {
        visibleStacks.reduce(0) { $0 + items(for: $1).count }
    }

    private var unreadCount: Int { viewModel.unreadCount }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    AmenPulseHeroCard(
                        totalCount: totalCount,
                        showFullActivity: $showFullActivity
                    )

                    PulseModeSelector(mode: $pulseMode)

                    if visibleStacks.isEmpty {
                        AmenPulseEmptyState(showFullActivity: $showFullActivity)
                            .padding(.top, 8)
                    } else {
                        ForEach(visibleStacks) { category in
                            PulseStackCard(
                                category: category,
                                items: items(for: category),
                                isExpanded: Binding(
                                    get: { expandedCategory == category.id },
                                    set: { expanded in
                                        withAnimation(
                                            reduceMotion ? .none :
                                                .spring(response: 0.45, dampingFraction: 0.78)
                                        ) {
                                            expandedCategory = expanded ? category.id : nil
                                        }
                                    }
                                ),
                                onTapItem: { item in
                                    viewModel.markRead(item.sourceNotificationIds)
                                    NotificationTapHandler.shared.execute(item.route)
                                },
                                onDismissItem: { item in
                                    viewModel.dismiss(item.sourceNotificationIds)
                                },
                                onAction: { _, item in
                                    viewModel.markRead(item.sourceNotificationIds)
                                    NotificationTapHandler.shared.execute(item.route)
                                }
                            )
                        }
                    }

                    // Footer
                    Button {
                        showFullActivity = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("See Full Activity")
                                .font(AMENFont.semiBold(15))
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(AmenTheme.Colors.iconPrimary)
                        .padding(.vertical, 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See Full Activity")
                    .accessibilityHint("Opens the complete activity inbox")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if unreadCount > 0 {
                        Button {
                            withAnimation(
                                reduceMotion ? .none :
                                    .spring(response: 0.4, dampingFraction: 0.85)
                            ) {
                                viewModel.markAllReadRemote()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Mark Read")
                                    .font(AMENFont.semiBold(14))
                            }
                            .foregroundStyle(AmenTheme.Colors.iconPrimary)
                        }
                        .accessibilityLabel("Mark all as read")
                    }
                }
            }
            .sheet(isPresented: $showFullActivity) {
                AMENNotificationsView()
            }
        }
    }
}

// Expose the raw, unfiltered notifications for pulse filtering.
extension AMENNotificationsViewModel {
    var rawNotificationsUnfiltered: [AppNotification] { rawNotifications }
}

// MARK: - AmenPulseHeroCard

private struct AmenPulseHeroCard: View {
    let totalCount: Int
    @Binding var showFullActivity: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }

    private var firstName: String {
        Auth.auth().currentUser?.displayName?
            .components(separatedBy: " ").first ?? "Friend"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(greeting), \(firstName)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.8)

                    if totalCount > 0 {
                        Text("Today's Pulse — \(totalCount) meaningful update\(totalCount == 1 ? "" : "s")")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("You're all caught up")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)

                // Date chip
                VStack(spacing: 2) {
                    Text(Date(), format: .dateTime.weekday(.abbreviated))
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(.secondary)
                    Text(Date(), format: .dateTime.day())
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Suggested actions when inbox is empty
            if totalCount == 0 {
                HStack(spacing: 8) {
                    ForEach(["Open Berean", "Find Church", "Prayer Wall"], id: \.self) { label in
                        Text(label)
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(AmenTheme.Colors.iconPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(AmenTheme.Colors.iconPrimary.opacity(0.10))
                                    .overlay(Capsule().strokeBorder(AmenTheme.Colors.iconPrimary.opacity(0.2), lineWidth: 0.5))
                            )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(greeting), \(firstName). \(totalCount > 0 ? "Today's Pulse, \(totalCount) updates" : "You're all caught up")")
    }
}

// MARK: - PulseModeSelector

private struct PulseModeSelector: View {
    @Binding var mode: PulseMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PulseMode.allCases, id: \.self) { m in
                let isSelected = mode == m
                Button {
                    withAnimation(
                        reduceMotion ? .none :
                            .spring(response: 0.3, dampingFraction: 0.7)
                    ) {
                        mode = m
                    }
                } label: {
                    Text(m.rawValue)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                                        )
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.rawValue)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pulse mode selector")
    }
}

// MARK: - PulseStackCard

private struct PulseStackCard: View {
    let category: PulseCategory
    let items: [GroupedNotification]
    @Binding var isExpanded: Bool
    let onTapItem: (GroupedNotification) -> Void
    let onDismissItem: (GroupedNotification) -> Void
    let onAction: (ActivitySmartAction, GroupedNotification) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var hasUrgentItems: Bool {
        items.contains { $0.priority <= .p1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            collapsedHeader
            if isExpanded {
                expandedContent
                    .transition(
                        reduceMotion ? .opacity :
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(
            color: (category.gradient.first ?? .clear).opacity(0.35),
            radius: 16, x: 0, y: 8
        )
        .accessibilityElement(children: isExpanded ? .contain : .combine)
        .accessibilityLabel("\(category.title) stack, \(items.count) update\(items.count == 1 ? "" : "s")\(hasUrgentItems ? ", urgent" : "")")
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
    }

    // MARK: Collapsed Header

    private var collapsedHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            LinearGradient(
                colors: category.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: isExpanded ? 100 : 180)

            // Watermark icon
            Image(systemName: category.icon)
                .font(.system(size: isExpanded ? 52 : 80))
                .foregroundStyle(.white.opacity(0.12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 24)

            // Bottom left: title + count label
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.system(size: isExpanded ? 20 : 28, weight: .bold))
                    .foregroundStyle(.white)
                if !isExpanded {
                    Text("\(items.count) update\(items.count == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(20)

            // Top row: count badge + urgent dot + chevron
            VStack {
                HStack(alignment: .top) {
                    countBadge
                    Spacer()
                    if hasUrgentItems && !isExpanded {
                        UrgentPulseDot()
                            .padding(.top, 4)
                            .padding(.trailing, 4)
                    }
                    chevronButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer()
            }
        }
        .frame(height: isExpanded ? 100 : 180)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(
                reduceMotion ? .none :
                    .spring(response: 0.45, dampingFraction: 0.78)
            ) {
                isExpanded.toggle()
            }
        }
    }

    private var countBadge: some View {
        Text("\(items.count)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
    }

    private var chevronButton: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .padding(8)
            .background(.ultraThinMaterial, in: Circle())
    }

    // MARK: Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Notification rows
            ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { i, item in
                ActivityNotificationRow(
                    item: item,
                    index: i,
                    onTap:    { onTapItem(item) },
                    onDismiss: { onDismissItem(item) },
                    onAction: { action in onAction(action, item) }
                )
                if i < min(items.count, 6) - 1 {
                    Divider().padding(.leading, 74)
                }
            }

            // Footer actions
            HStack(spacing: 12) {
                if items.count > 6 {
                    Button {
                        // "Catch Me Up" — mark all in this category as read
                        items.forEach { onTapItem($0) }
                    } label: {
                        Label("Catch Me Up", systemImage: "bolt.fill")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(category.gradient.last ?? .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill((category.gradient.last ?? .accentColor).opacity(0.12))
                                    .overlay(Capsule().strokeBorder((category.gradient.last ?? .accentColor).opacity(0.3), lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Text("See All in \(category.title)")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: items.count > 6 ? .trailing : .leading)
                    .padding(.leading, items.count <= 6 ? 14 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial)
    }
}

// MARK: - Urgent Pulse Dot

private struct UrgentPulseDot: View {
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(.white.opacity(pulsing ? 0.6 : 0.4))
            .frame(width: 6, height: 6)
            .scaleEffect(pulsing ? 1.15 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 1.1)
                    .repeatForever(autoreverses: true)
                ) { pulsing = true }
            }
    }
}

// MARK: - AmenPulseEmptyState

private struct AmenPulseEmptyState: View {
    @Binding var showFullActivity: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green.opacity(0.7))

            VStack(spacing: 6) {
                Text("You're all caught up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                Text("No urgent updates right now.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }

            // Suggested action chips
            HStack(spacing: 8) {
                ForEach(
                    [
                        ("book.fill", "Continue Reading"),
                        ("sparkles", "Open Berean"),
                        ("building.columns.fill", "Find Church"),
                    ],
                    id: \.1
                ) { icon, label in
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(label)
                            .font(AMENFont.semiBold(12))
                    }
                    .foregroundStyle(AmenTheme.Colors.iconPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(AmenTheme.Colors.iconPrimary.opacity(0.10))
                            .overlay(Capsule().strokeBorder(AmenTheme.Colors.iconPrimary.opacity(0.2), lineWidth: 0.5))
                    )
                }
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're all caught up. No urgent updates right now.")
    }
}

// MARK: - Preview

struct AmenPulseView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AmenPulseView()
                .previewDisplayName("Pulse — Light")
            AmenPulseView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Pulse — Dark")
        }
    }
}
