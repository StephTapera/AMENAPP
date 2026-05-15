//
//  AMENNotificationsView.swift
//  AMENAPP
//
//  AMEN Activity Intelligence System — Liquid Glass activity inbox.
//  Meaning-based, priority-driven, and action-oriented.
//  Wired to Firestore via NotificationService + AMENActivityIntelligenceEngine.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class AMENNotificationsViewModel: ObservableObject {

    @Published private(set) var rawNotifications: [AppNotification] = []
    @Published var selectedFilter: ActivityFilterCategory = .all
    @Published var focusModeOn: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.notificationFocusMode) {
        didSet { UserDefaults.standard.set(focusModeOn, forKey: UserDefaultsKeys.notificationFocusMode) }
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: Derived

    var processedNotifications: [GroupedNotification] {
        let processed = AMENActivityIntelligenceEngine.process(rawNotifications)
        let focusFiltered = focusModeOn ? processed.filter { $0.priority <= .p1 } : processed
        switch selectedFilter {
        case .all:       return focusFiltered
        case .important: return focusFiltered.filter { $0.priority <= .p1 }
        default:         return focusFiltered.filter { $0.category == selectedFilter }
        }
    }

    var needsAttention: [GroupedNotification] {
        processedNotifications.filter { $0.timeBucket == .needsAttention }
    }
    var todayItems: [GroupedNotification] {
        processedNotifications.filter { $0.timeBucket == .today }
    }
    var yesterdayItems: [GroupedNotification] {
        processedNotifications.filter { $0.timeBucket == .yesterday }
    }
    var lastSevenDaysItems: [GroupedNotification] {
        processedNotifications.filter { $0.timeBucket == .lastSevenDays }
    }
    var earlierItems: [GroupedNotification] {
        processedNotifications.filter { $0.timeBucket == .earlier }
    }

    var unreadCount: Int { rawNotifications.filter { !$0.read }.count }
    var hasContent: Bool { !processedNotifications.isEmpty }

    // MARK: Init

    init() {
        NotificationService.shared.$notifications
            .map { notes in notes.filter { $0.actorId != Auth.auth().currentUser?.uid } }
            .sink { [weak self] in self?.rawNotifications = $0 }
            .store(in: &cancellables)
    }

    // MARK: Mutations

    func markAllReadRemote() {
        Task {
            await NotificationService.shared.markAllAsReadViaQuery()
            BadgeCountManager.shared.clearNotifications()
        }
    }

    func markRead(_ ids: [String]) {
        for id in ids { Task { try? await NotificationService.shared.markAsRead(id) } }
    }

    func dismiss(_ ids: [String]) {
        rawNotifications.removeAll { n in ids.contains(n.id ?? "") }
        for id in ids { Task { try? await NotificationService.shared.deleteNotification(id) } }
    }
}

// MARK: - Helpers

private func relativeTimestamp(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    switch interval {
    case ..<60:    return "now"
    case ..<3600:  return "\(max(1, Int(interval / 60)))m"
    case ..<86400: return "\(max(1, Int(interval / 3600)))h"
    default:       return "\(max(1, Int(interval / 86400)))d"
    }
}

// MARK: - Glass Surface Modifier

private struct ActivityGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 18
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AmenTheme.Colors.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                elevated ? AmenTheme.Colors.glassStroke.opacity(1.6) : AmenTheme.Colors.glassStroke,
                                lineWidth: elevated ? 0.8 : 0.5
                            )
                    )
                    .shadow(
                        color: AmenTheme.Colors.shadowCard.opacity(elevated ? 1.4 : 1.0),
                        radius: elevated ? 18 : 12,
                        x: 0, y: elevated ? 6 : 3
                    )
            )
    }
}

private extension View {
    func activityGlass(cornerRadius: CGFloat = 18, elevated: Bool = false) -> some View {
        modifier(ActivityGlassSurface(cornerRadius: cornerRadius, elevated: elevated))
    }
}

// MARK: - Filter Chip Bar

private struct ActivityFilterChipBar: View {
    @Binding var selected: ActivityFilterCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFilterCategory.allCases) { category in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                            selected = category
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(category.rawValue)
                                .font(AMENFont.semiBold(13))
                        }
                        .foregroundStyle(selected == category ? Color.white : AmenTheme.Colors.textPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selected == category
                                      ? AmenTheme.Colors.buttonPrimary
                                      : .ultraThinMaterial)
                                .overlay(
                                    selected == category ? nil :
                                        Capsule().fill(AmenTheme.Colors.glassFill)
                                )
                                .overlay(
                                    selected == category ? nil :
                                        Capsule().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Actor Avatar Stack

private struct ActivityActorStack: View {
    let primary: NotificationActor?
    let secondary: [NotificationActor]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarView(primary, size: 46)

            ForEach(Array(secondary.prefix(2).enumerated()), id: \.offset) { i, actor in
                avatarView(actor, size: 22)
                    .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                    .offset(x: CGFloat(i) * 10 + 10, y: CGFloat(i) * 4 + 10)
            }
        }
        .frame(width: 54, height: 54)
    }

    @ViewBuilder
    private func avatarView(_ actor: NotificationActor?, size: CGFloat) -> some View {
        let name = actor?.name ?? "?"
        let url  = actor?.profileImageURL.flatMap(URL.init)

        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        initialsCircle(name: name, size: size)
                    }
                }
            } else {
                initialsCircle(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 4, y: 1)
    }

    private func initialsCircle(name: String, size: CGFloat) -> some View {
        let initials = name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return ZStack {
            Circle().fill(.ultraThinMaterial)
                .overlay(Circle().fill(AmenTheme.Colors.glassFill))
            Text(initials)
                .font(.system(size: max(9, size * 0.33), weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
    }
}

// MARK: - Content Preview Thumbnail

private struct ActivityPreviewThumbnail: View {
    let preview: ActivityContentPreview

    var body: some View {
        switch preview {
        case .prayerCard:
            previewCell(icon: "hands.sparkles.fill", color: .purple)
        case .churchNotes:
            previewCell(icon: "note.text", color: .orange)
        case .bereanInsight:
            previewCell(icon: "sparkles", color: .blue)
        case .verseCard(let ref):
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10).fill(AmenTheme.Colors.glassFill))
                Text(ref)
                    .font(AMENFont.bold(9))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(4)
            }
            .frame(width: 46, height: 46)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
        case .postImage(let url):
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    default:
                        previewCell(icon: "photo", color: AmenTheme.Colors.iconSecondary)
                    }
                }
            } else {
                EmptyView()
            }
        case .churchLogo(let url):
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    default:
                        previewCell(icon: "building.columns.fill", color: .gray)
                    }
                }
            } else {
                previewCell(icon: "building.columns.fill", color: .gray)
            }
        case .none:
            EmptyView()
        }
    }

    private func previewCell(icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).fill(AmenTheme.Colors.glassFill))
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color.opacity(0.8))
        }
        .frame(width: 46, height: 46)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
    }
}

// MARK: - Smart Action Button

private struct ActivityActionButton: View {
    let action: ActivitySmartAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: action.systemIcon)
                    .font(.system(size: 11, weight: .semibold))
                Text(action.label)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(
                action.style == .primary
                    ? AmenTheme.Colors.buttonPrimaryText
                    : AmenTheme.Colors.textPrimary
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(action.style == .primary ? AmenTheme.Colors.buttonPrimary : .ultraThinMaterial)
                    .overlay(
                        action.style == .secondary
                            ? Capsule().fill(AmenTheme.Colors.glassFill) : nil
                    )
                    .overlay(
                        action.style == .secondary
                            ? Capsule().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5) : nil
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Notification Row

private struct ActivityNotificationRow: View {
    let item: GroupedNotification
    let index: Int
    let onTap: () -> Void
    let onDismiss: () -> Void
    let onAction: (ActivitySmartAction) -> Void

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread dot
            Circle()
                .fill(item.isRead ? Color.clear : AmenTheme.Colors.iconPrimary)
                .frame(width: 8, height: 8)
                .padding(.top, 20)

            // Actor avatars
            ActivityActorStack(
                primary: item.primaryActor,
                secondary: item.secondaryActors
            )

            // Main content
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(item.attributedTitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text(relativeTimestamp(item.timestamp))
                        .font(AMENFont.regular(12))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if let label = item.contextLabel {
                        Text(label)
                            .font(AMENFont.semiBold(10))
                            .foregroundStyle(AmenTheme.Colors.iconPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(AmenTheme.Colors.iconPrimary.opacity(0.1)))
                    }
                    if item.isQuietGrouped {
                        Text("Quiet")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                if !item.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(item.actions.prefix(2)) { action in
                            ActivityActionButton(action: action) { onAction(action) }
                        }
                    }
                    .padding(.top, 2)
                }
            }

            // Right-side content preview
            Group {
                switch item.contentPreview {
                case .none: EmptyView()
                default:    ActivityPreviewThumbnail(preview: item.contentPreview)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -10)
        .onAppear {
            withAnimation(
                Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.82))
                    .delay(Double(index) * 0.04)
            ) { appeared = true }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDismiss) {
                Label("Clear", systemImage: "xmark.circle.fill")
            }
            .tint(.red)
        }
        .contextMenu {
            Button("Mark Read", systemImage: "checkmark.circle") { onTap() }
            Button("Clear", systemImage: "xmark.circle", role: .destructive) { onDismiss() }
        }
    }
}

private extension GroupedNotification {
    var isQuietGrouped: Bool { priority >= .p3 && totalActorCount > 5 }
}

// MARK: - Needs Your Attention Panel

private struct NeedsAttentionPanel: View {
    let items: [GroupedNotification]
    let onTap: (GroupedNotification) -> Void
    let onDismiss: (GroupedNotification) -> Void
    let onAction: (ActivitySmartAction, GroupedNotification) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.iconPrimary)
                Text("Needs Your Attention")
                    .font(AMENFont.bold(14))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(items.count)")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AmenTheme.Colors.buttonPrimary))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, 14)

            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                ActivityNotificationRow(
                    item: item,
                    index: i,
                    onTap: { onTap(item) },
                    onDismiss: { onDismiss(item) },
                    onAction: { action in onAction(action, item) }
                )
                if i < items.count - 1 {
                    Divider().padding(.leading, 74)
                }
            }
        }
        .activityGlass(cornerRadius: 20, elevated: true)
    }
}

// MARK: - Time Bucket Section

private struct TimeBucketSection: View {
    let title: String
    let items: [GroupedNotification]
    let onTap: (GroupedNotification) -> Void
    let onDismiss: (GroupedNotification) -> Void
    let onAction: (ActivitySmartAction, GroupedNotification) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AMENFont.bold(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    ActivityNotificationRow(
                        item: item,
                        index: i,
                        onTap: { onTap(item) },
                        onDismiss: { onDismiss(item) },
                        onAction: { action in onAction(action, item) }
                    )
                    if i < items.count - 1 {
                        Divider().padding(.leading, 74)
                    }
                }
            }
            .activityGlass(cornerRadius: 18)
        }
    }
}

// MARK: - Focus Mode Pill

private struct FocusModePill: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? "moon.fill" : "moon")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.iconPrimary)
            Text("Focus Mode")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)
            Text(isOn ? "ON" : "OFF")
                .font(AMENFont.bold(12))
                .foregroundStyle(isOn ? AmenTheme.Colors.iconPrimary : AmenTheme.Colors.iconSecondary)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AmenTheme.Colors.buttonPrimary)
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(AmenTheme.Colors.glassFill))
                .overlay(Capsule().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 12, x: 0, y: 3)
        )
        .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.80)), value: isOn)
    }
}

// MARK: - Empty State

private struct ActivityEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(AmenTheme.Colors.glassFill))
                    .overlay(Circle().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
                    .frame(width: 72, height: 72)
                    .shadow(color: AmenTheme.Colors.shadowCard, radius: 16, x: 0, y: 4)
                Image(systemName: "bell.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
            }
            VStack(spacing: 6) {
                Text("You're all caught up")
                    .font(AMENFont.semiBold(17))
                    .foregroundStyle(.primary)
                Text("Prayer, community, scripture, and church activity will appear here.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .activityGlass(cornerRadius: 20)
        .padding(.horizontal, 24)
    }
}

// MARK: - Main View

struct AMENNotificationsView: View {
    @StateObject private var viewModel = AMENNotificationsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AmenTheme.Colors.backgroundGrouped.ignoresSafeArea()
                if viewModel.hasContent {
                    mainContent
                } else {
                    emptyContent
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.unreadCount > 0 {
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
                                viewModel.markAllReadRemote()
                            }
                        } label: {
                            Text("Mark all read")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .onAppear {
                viewModel.markAllReadRemote()
                Task { await NotificationService.shared.recordInboxOpened() }
            }
        }
    }

    // MARK: Empty

    private var emptyContent: some View {
        VStack(spacing: 24) {
            FocusModePill(isOn: $viewModel.focusModeOn).padding(.top, 8)
            Spacer()
            ActivityEmptyState()
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: Main List

    private var mainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                VStack(spacing: 10) {
                    FocusModePill(isOn: $viewModel.focusModeOn)
                    ActivityFilterChipBar(selected: $viewModel.selectedFilter)
                }
                .padding(.top, 4)

                if !viewModel.needsAttention.isEmpty {
                    NeedsAttentionPanel(
                        items: viewModel.needsAttention,
                        onTap: open,
                        onDismiss: { viewModel.dismiss($0.sourceNotificationIds) },
                        onAction: handleAction
                    )
                }

                if !viewModel.todayItems.isEmpty {
                    TimeBucketSection(
                        title: "Today",
                        items: viewModel.todayItems,
                        onTap: open,
                        onDismiss: { viewModel.dismiss($0.sourceNotificationIds) },
                        onAction: handleAction
                    )
                }
                if !viewModel.yesterdayItems.isEmpty {
                    TimeBucketSection(
                        title: "Yesterday",
                        items: viewModel.yesterdayItems,
                        onTap: open,
                        onDismiss: { viewModel.dismiss($0.sourceNotificationIds) },
                        onAction: handleAction
                    )
                }
                if !viewModel.lastSevenDaysItems.isEmpty {
                    TimeBucketSection(
                        title: "Last 7 Days",
                        items: viewModel.lastSevenDaysItems,
                        onTap: open,
                        onDismiss: { viewModel.dismiss($0.sourceNotificationIds) },
                        onAction: handleAction
                    )
                }
                if !viewModel.earlierItems.isEmpty {
                    TimeBucketSection(
                        title: "Earlier",
                        items: viewModel.earlierItems,
                        onTap: open,
                        onDismiss: { viewModel.dismiss($0.sourceNotificationIds) },
                        onAction: handleAction
                    )
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: Routing

    private func open(_ item: GroupedNotification) {
        viewModel.markRead(item.sourceNotificationIds)
        NotificationTapHandler.shared.execute(item.route)
    }

    private func handleAction(_ action: ActivitySmartAction, for item: GroupedNotification) {
        viewModel.markRead(item.sourceNotificationIds)
        NotificationTapHandler.shared.execute(item.route)
    }
}

// MARK: - Preview

struct AMENNotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AMENNotificationsView()
                .previewDisplayName("Activity Inbox — Light")
            AMENNotificationsView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Activity Inbox — Dark")
        }
    }
}
