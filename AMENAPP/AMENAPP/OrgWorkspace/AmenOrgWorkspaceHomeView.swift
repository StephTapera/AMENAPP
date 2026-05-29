import SwiftUI

// MARK: - Models

struct WorkspaceChannel: Identifiable {
    var id: String
    var name: String
    var isPrivate: Bool
    var unreadCount: Int
    var isMuted: Bool
}

struct WorkspaceDM: Identifiable {
    var id: String
    var contactName: String
    var contactInitial: String
    var contactColor: String
    var lastMessage: String
    var unreadCount: Int
    var timestamp: Date
}

struct WorkspaceQuickStats {
    var catchUpCount: Int
    var threadCount: Int
    var prayerRoomLiveCount: Int
    var unreadDMCount: Int
}

// MARK: - ViewModel

@MainActor
final class AmenOrgWorkspaceHomeViewModel: ObservableObject {
    @Published var channels: [WorkspaceChannel] = []
    @Published var recentDMs: [WorkspaceDM] = []
    @Published var stats = WorkspaceQuickStats(catchUpCount: 0, threadCount: 0, prayerRoomLiveCount: 0, unreadDMCount: 0)
    @Published var workspaceName: String = "My Church"
    @Published var unreadsSectionExpanded = true
    @Published var isLoading = false

    func load(orgId: String) async {
        isLoading = true
        try? await Task.sleep(nanoseconds: 500_000_000)
        workspaceName = "AMEN Workspace"
        channels = [
            WorkspaceChannel(id: "1", name: "announcements", isPrivate: false, unreadCount: 3, isMuted: false),
            WorkspaceChannel(id: "2", name: "prayer-requests", isPrivate: false, unreadCount: 7, isMuted: false),
            WorkspaceChannel(id: "3", name: "sermon-notes", isPrivate: false, unreadCount: 0, isMuted: false),
            WorkspaceChannel(id: "4", name: "leadership", isPrivate: true, unreadCount: 2, isMuted: false),
            WorkspaceChannel(id: "5", name: "youth-ministry", isPrivate: false, unreadCount: 0, isMuted: false),
        ]
        recentDMs = [
            WorkspaceDM(id: "1", contactName: "Pastor James", contactInitial: "P", contactColor: "#7043CC", lastMessage: "See you Sunday 🙏", unreadCount: 2, timestamp: Date()),
        ]
        stats = WorkspaceQuickStats(catchUpCount: 14, threadCount: 3, prayerRoomLiveCount: 2, unreadDMCount: 5)
        isLoading = false
    }
}

// MARK: - Main View

struct AmenOrgWorkspaceHomeView: View {
    let orgId: String
    var onYouTapped: () -> Void = {}
    var onDMsTapped: () -> Void = {}
    var onDMRowTapped: (WorkspaceDM) -> Void = { _ in }
    var onChannelTapped: (WorkspaceChannel) -> Void = { _ in }
    var onAddChannelTapped: () -> Void = {}
    var onQuickActionTapped: (String) -> Void = { _ in }

    @StateObject private var viewModel = AmenOrgWorkspaceHomeViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerBar
                        .padding(.bottom, 12)

                    VStack(spacing: 20) {
                        quickActionRow

                        if viewModel.stats.unreadDMCount > 0 {
                            unreadDMsRow
                        }

                        if let firstDM = viewModel.recentDMs.first {
                            recentDMPreview(firstDM)
                        }

                        unreadsSection

                        channelListSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
            }
            .background(AmenTheme.Colors.backgroundPrimary)

            fabButton
                .padding(.trailing, 20)
                .padding(.bottom, 32)
        }
        .task {
            await viewModel.load(orgId: orgId)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        ZStack {
            glassBackground(cornerRadius: 0)
                .ignoresSafeArea(edges: .top)

            HStack(alignment: .center, spacing: 12) {
                Text(viewModel.workspaceName)
                    .font(AMENFont.bold(18))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .lineLimit(1)

                Spacer()

                Button {
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.large)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter")

                Button {
                    HapticManager.impact(style: .light)
                    onYouTapped()
                } label: {
                    Circle()
                        .fill(AmenTheme.Colors.amenPurple.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Text("Y")
                                .font(AMENFont.bold(14))
                                .foregroundStyle(.white)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your profile")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Actions

    private var quickActionRow: some View {
        HStack(spacing: 10) {
            quickTile(
                actionKey: "catchup",
                icon: "newspaper.fill",
                label: "Catch Up",
                badge: viewModel.stats.catchUpCount > 0 ? "\(viewModel.stats.catchUpCount)" : nil,
                badgeColor: AmenTheme.Colors.amenGold,
                subtitle: nil
            )
            quickTile(
                actionKey: "berean",
                icon: "brain.head.profile",
                label: "Berean AI",
                badge: nil,
                badgeColor: AmenTheme.Colors.amenGold,
                subtitle: "Ask scripture"
            )
            quickTile(
                actionKey: "threads",
                icon: "bubble.left.and.bubble.right.fill",
                label: "Threads",
                badge: viewModel.stats.threadCount > 0 ? "\(viewModel.stats.threadCount)" : nil,
                badgeColor: AmenTheme.Colors.amenGold,
                subtitle: nil
            )
            quickTile(
                actionKey: "prayer",
                icon: "person.wave.2.fill",
                label: "Prayer Room",
                badge: nil,
                badgeColor: AmenTheme.Colors.amenGold,
                subtitle: viewModel.stats.prayerRoomLiveCount > 0
                    ? "\(viewModel.stats.prayerRoomLiveCount) live"
                    : nil,
                subtitleIsLive: viewModel.stats.prayerRoomLiveCount > 0
            )
        }
    }

    private func quickTile(
        actionKey: String,
        icon: String,
        label: String,
        badge: String?,
        badgeColor: Color,
        subtitle: String?,
        subtitleIsLive: Bool = false
    ) -> some View {
        QuickActionTile(
            actionKey: actionKey,
            icon: icon,
            label: label,
            badge: badge,
            badgeColor: badgeColor,
            subtitle: subtitle,
            subtitleIsLive: subtitleIsLive,
            reduceTransparency: reduceTransparency,
            reduceMotion: reduceMotion,
            onTap: onQuickActionTapped
        )
    }

    // MARK: - Unread DMs Row

    private var unreadDMsRow: some View {
        Button {
            HapticManager.impact(style: .light)
            onDMsTapped()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                    .imageScale(.medium)

                Text("Unread DMs")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Spacer()

                countBadge(viewModel.stats.unreadDMCount, color: AmenTheme.Colors.amenPurple)

                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(rowBackground)
            .overlay(rowStroke)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unread DMs, \(viewModel.stats.unreadDMCount) unread")
        .accessibilityHint("Opens direct messages")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Recent DM Preview

    private func recentDMPreview(_ dm: WorkspaceDM) -> some View {
        Button {
            HapticManager.impact(style: .light)
            onDMRowTapped(dm)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: dm.contactColor))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(dm.contactInitial)
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(dm.contactName)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(dm.lastMessage)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(dm.timestamp, style: .relative)
                        .font(AMENFont.regular(11))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)

                    if dm.unreadCount > 0 {
                        countBadge(dm.unreadCount, color: AmenTheme.Colors.amenPurple)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(rowBackground)
            .overlay(rowStroke)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dm.contactName). \(dm.lastMessage). \(dm.unreadCount) unread.")
        .accessibilityHint("Open conversation")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Unreads Section

    private var unreadsSection: some View {
        let unreadChannels = viewModel.channels.filter { $0.unreadCount > 0 && !$0.isMuted }

        return VStack(spacing: 0) {
            Button {
                HapticManager.impact(style: .light)
                withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78)) {
                    viewModel.unreadsSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.unreadsSectionExpanded ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)

                    Text("Unreads")
                        .font(AMENFont.bold(15))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    if !unreadChannels.isEmpty {
                        countBadge(unreadChannels.reduce(0) { $0 + $1.unreadCount }, color: AmenTheme.Colors.amenGold)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unreads section, \(unreadChannels.count) channels")
            .accessibilityHint(viewModel.unreadsSectionExpanded ? "Collapse" : "Expand")
            .accessibilityAddTraits(.isButton)

            if viewModel.unreadsSectionExpanded && !unreadChannels.isEmpty {
                VStack(spacing: 0) {
                    ForEach(unreadChannels) { channel in
                        channelRow(channel)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .background(rowBackground)
        .overlay(rowStroke)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Channel List Section

    private var channelListSection: some View {
        let publicChannels = viewModel.channels.filter { !$0.isPrivate }
        let privateChannels = viewModel.channels.filter { $0.isPrivate }

        return VStack(spacing: 0) {
            if !publicChannels.isEmpty {
                sectionHeader("Channels")
                ForEach(publicChannels) { channel in
                    channelRow(channel)
                    if channel.id != publicChannels.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }

            if !privateChannels.isEmpty {
                sectionHeader("Private Channels")
                    .padding(.top, publicChannels.isEmpty ? 0 : 4)
                ForEach(privateChannels) { channel in
                    channelRow(channel)
                    if channel.id != privateChannels.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .background(rowBackground)
        .overlay(rowStroke)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(AMENFont.semiBold(11))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func channelRow(_ channel: WorkspaceChannel) -> some View {
        Button {
            HapticManager.impact(style: .light)
            onChannelTapped(channel)
        } label: {
            HStack(spacing: 10) {
                Text(channel.isPrivate ? "🔒" : "#")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(width: 22, alignment: .center)

                Text(channel.name)
                    .font(channel.unreadCount > 0 ? AMENFont.semiBold(15) : AMENFont.regular(15))
                    .foregroundStyle(channel.unreadCount > 0
                        ? AmenTheme.Colors.textPrimary
                        : AmenTheme.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()

                if channel.unreadCount > 0 && !channel.isMuted {
                    if channel.unreadCount <= 9 {
                        countBadge(channel.unreadCount, color: AmenTheme.Colors.amenGold)
                    } else {
                        Circle()
                            .fill(AmenTheme.Colors.amenGold)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(channel.isPrivate ? "Private channel" : "Channel") \(channel.name)\(channel.unreadCount > 0 ? ", \(channel.unreadCount) unread" : "")")
        .accessibilityHint("Open channel")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            HapticManager.impact(style: .light)
            onAddChannelTapped()
        } label: {
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.amenGold)
                    .frame(width: 56, height: 56)
                    .shadow(color: AmenTheme.Colors.amenGold.opacity(0.4), radius: 12, y: 4)

                Image(systemName: "plus")
                    .imageScale(.large)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(SpringFABStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Add channel")
        .accessibilityHint("Create or join a new channel")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Shared helpers

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(AMENFont.bold(11))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }

    @ViewBuilder
    private var rowBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.25))
            }
        }
    }

    private var rowStroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
    }

    @ViewBuilder
    private func glassBackground(cornerRadius: CGFloat) -> some View {
        if reduceTransparency {
            Rectangle().fill(AmenTheme.Colors.backgroundPrimary)
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.white.opacity(0.18))
            }
        }
    }
}

// MARK: - Quick Action Tile

private struct QuickActionTile: View {
    let actionKey: String
    let icon: String
    let label: String
    let badge: String?
    let badgeColor: Color
    let subtitle: String?
    let subtitleIsLive: Bool
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let onTap: (String) -> Void

    var body: some View {
        Button {
            HapticManager.impact(style: .light)
            onTap(actionKey)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .frame(width: 36, height: 36)

                    if let badge = badge {
                        Text(badge)
                            .font(AMENFont.bold(10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(badgeColor))
                            .offset(x: 8, y: -6)
                    }
                }

                Text(label)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let subtitle = subtitle {
                    if subtitleIsLive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AmenTheme.Colors.statusSuccess)
                                .frame(width: 6, height: 6)
                            Text(subtitle)
                                .font(AMENFont.regular(10))
                                .foregroundStyle(AmenTheme.Colors.statusSuccess)
                        }
                    } else {
                        Text(subtitle)
                            .font(AMENFont.regular(10))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Spacer().frame(height: 14)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(tileBackground)
            .overlay(tileStroke)
        }
        .buttonStyle(SpringFABStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label + (badge != nil ? ", \(badge!) unread" : "") + (subtitle != nil ? ", \(subtitle!)" : ""))
        .accessibilityHint("Open \(label)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var tileBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.25))
            }
        }
    }

    private var tileStroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
    }
}

// MARK: - Spring Button Style (FAB + tiles)

private struct SpringFABStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1.0)
            .animation(
                reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}

