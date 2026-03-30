// WorkspaceHubView.swift
// AMENAPP — Cadence Workspace Hub (KORA · VERGE · HELIX)

import SwiftUI
import FirebaseAuth

// MARK: - Root view

struct WorkspaceHubView: View {

    @StateObject private var vm = WorkspaceViewModel()
    @State private var showSwitcher = false

    // Placeholder counts — replace with real subcollection listeners per platform
    private let koraCheckInCount  = 3
    private let vergeLiveCount    = 1
    private let helixWorkflowCount = 2

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 20) {

                        // ── Workspace switcher ───────────────────────────────
                        workspaceSwitcherRow

                        // ── Platform cards ──────────────────────────────────
                        NavigationLink(destination: KoraRootView()) {
                            PlatformCard(
                                gradient: koraGradient,
                                icon: "hands.sparkles.fill",
                                platformName: "Kora",
                                subtitle: "Your Circles",
                                status: koraCheckInCount > 0
                                    ? "\(koraCheckInCount) active check-ins"
                                    : "No active check-ins",
                                badgeCount: koraCheckInCount
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink(destination: VergeRootView()) {
                            PlatformCard(
                                gradient: vergeGradient,
                                icon: "video.fill",
                                platformName: "Verge",
                                subtitle: "Live Discussions",
                                status: vergeLiveCount > 0
                                    ? "\(vergeLiveCount) live now"
                                    : "0 live now",
                                badgeCount: vergeLiveCount
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        NavigationLink(destination: HelixRootView()) {
                            PlatformCard(
                                gradient: helixGradient,
                                icon: "wand.and.stars.inverse",
                                platformName: "Helix",
                                subtitle: "Workflows",
                                status: "\(helixWorkflowCount) workflows active",
                                badgeCount: 0
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // ── Recent activity ─────────────────────────────────
                        recentActivitySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSwitcher) {
                WorkspaceSwitcherView(vm: vm)
            }
            .task {
                await vm.loadWorkspaces()
            }
        }
    }

    // MARK: - Subviews

    private var workspaceSwitcherRow: some View {
        Button {
            showSwitcher = true
        } label: {
            HStack(spacing: 10) {
                // Org avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "6B48FF"), Color(hex: "F59E0B")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Text(workspaceInitials)
                        .font(AMENFont.bold(14))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.currentWorkspace?.name ?? "Personal Workspace")
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.white)
                    Text(vm.currentWorkspace.map { "\($0.memberCount) members" } ?? "Just you")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(CoCreationPressStyle())
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(AMENFont.semiBold(17))
                .foregroundColor(.white)
                .padding(.horizontal, 4)

            LazyVStack(spacing: 8) {
                ForEach(vm.recentActivity) { item in
                    WorkspaceActivityRow(activity: item)
                }
            }
        }
    }

    // MARK: - Helpers

    private var workspaceInitials: String {
        guard let name = vm.currentWorkspace?.name, !name.isEmpty else { return "P" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - PlatformCard

private struct PlatformCard: View {
    let gradient: LinearGradient
    let icon: String
    let platformName: String
    let subtitle: String
    let status: String
    let badgeCount: Int

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            // Gradient header band
            ZStack(alignment: .bottomLeading) {
                gradient
                    .frame(height: 80)

                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)

                    Text(platformName)
                        .font(AMENFont.bold(22))
                        .foregroundColor(.white)

                    Spacer()

                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(AMENFont.bold(12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            // Glass info strip
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(subtitle)
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(.white)
                    Text(status)
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .overlay(
                // Bottom + side border only; top is handled by gradient
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: - WorkspaceActivityRow

struct WorkspaceActivityRow: View {
    let activity: WorkspaceActivity

    var body: some View {
        HStack(spacing: 12) {
            // Platform color dot + icon
            ZStack {
                Circle()
                    .fill(dotColor(for: activity.platform))
                    .frame(width: 36, height: 36)
                Image(systemName: activity.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.description)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                Text(timeAgo(from: activity.timestamp))
                    .font(AMENFont.regular(11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Helpers

    private func dotColor(for platform: String) -> Color {
        switch platform {
        case "kora":  return Color(hex: "F59E0B")
        case "verge": return Color(hex: "06B6D4")
        case "helix": return Color(hex: "10B981")
        default:      return Color(hex: "6B48FF")
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        switch seconds {
        case ..<60:             return "Just now"
        case 60..<3600:         return "\(seconds / 60)m ago"
        case 3600..<86400:      return "\(seconds / 3600)h ago"
        default:                return "\(seconds / 86400)d ago"
        }
    }
}

// MARK: - Gradient constants (file-scoped)

private let koraGradient = LinearGradient(
    colors: [Color(hex: "F59E0B"), Color(hex: "EF4444")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let vergeGradient = LinearGradient(
    colors: [Color(hex: "06B6D4"), Color(hex: "6B48FF")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let helixGradient = LinearGradient(
    colors: [Color(hex: "10B981"), Color(hex: "0EA5E9")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

