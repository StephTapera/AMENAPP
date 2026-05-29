// AmenMoreSheetView.swift
// AMENAPP
//
// Slack-style "More" tab destination surfacing secondary faith-native features,
// a quick-create tray, recent files, and starred items.
//
// Tab destination — NOT a sheet. Present inside a NavigationStack or as a tab root.

import SwiftUI

// MARK: - AmenCreateType

enum AmenCreateType: String, CaseIterable {
    case canvas
    case prayerRoom
    case channel
    case message

    var icon: String {
        switch self {
        case .canvas:     return "doc.richtext.fill"
        case .prayerRoom: return "headphones.circle.fill"
        case .channel:    return "number"
        case .message:    return "message.fill"
        }
    }

    var displayName: String {
        switch self {
        case .canvas:     return "Canvas"
        case .prayerRoom: return "Prayer Room"
        case .channel:    return "Channel"
        case .message:    return "Message"
        }
    }

    var subtitle: String {
        switch self {
        case .canvas:     return "Create rich study docs"
        case .prayerRoom: return "Start audio/video prayer"
        case .channel:    return "Organize your team"
        case .message:    return "Start a conversation"
        }
    }

    var tintColor: Color {
        switch self {
        case .canvas:     return AmenTheme.Colors.amenGold
        case .prayerRoom: return AmenTheme.Colors.amenPurple
        case .channel:    return AmenTheme.Colors.amenBlue
        case .message:    return AmenTheme.Colors.amenGold
        }
    }
}

// MARK: - AmenMoreViewModel

@MainActor
final class AmenMoreViewModel: ObservableObject {
    @Published var recentFiles: [RecentFile] = []
    @Published var isLoading = false

    struct RecentFile: Identifiable {
        var id: String
        var name: String
        var fileType: String    // "pdf", "audio", "image", "note"
        var formattedSize: String
        var modifiedDate: Date
    }

    func load() async {
        isLoading = true
        // Simulate network delay then inject stub data
        try? await Task.sleep(nanoseconds: 700_000_000)
        recentFiles = [
            RecentFile(
                id: "1",
                name: "Romans Study Notes.pdf",
                fileType: "pdf",
                formattedSize: "342 KB",
                modifiedDate: Date().addingTimeInterval(-3600)
            ),
            RecentFile(
                id: "2",
                name: "Sunday Sermon Recording",
                fileType: "audio",
                formattedSize: "18.4 MB",
                modifiedDate: Date().addingTimeInterval(-86400)
            ),
            RecentFile(
                id: "3",
                name: "Prayer Wall Screenshot",
                fileType: "image",
                formattedSize: "1.2 MB",
                modifiedDate: Date().addingTimeInterval(-172800)
            ),
        ]
        isLoading = false
    }
}

// MARK: - AmenMoreSheetView

struct AmenMoreSheetView: View {

    // MARK: Callbacks
    var onYouTapped: () -> Void = {}
    var onCreateTapped: (AmenCreateType) -> Void = { _ in }
    var onScriptureTapped: () -> Void = {}
    var onPrayerCommitmentsTapped: () -> Void = {}
    var onExternalConnectionsTapped: () -> Void = {}

    // MARK: State
    @StateObject private var viewModel = AmenMoreViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                Divider()
                    .background(AmenTheme.Colors.separatorSubtle)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                featureRowsSection
                    .padding(.horizontal, 16)

                sectionHeader("Create")
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                quickCreateGrid
                    .padding(.horizontal, 16)

                sectionHeader("Recent")
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                recentFilesSection
                    .padding(.horizontal, 16)

                sectionHeader("Starred")
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                starredEmptyState
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
            }
        }
        .background(AmenTheme.Colors.backgroundGrouped.ignoresSafeArea())
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            Text("More")
                .font(AMENFont.bold(28))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Spacer()

            Button {
                HapticManager.impact(style: .light)
                onYouTapped()
            } label: {
                ZStack {
                    Circle()
                        .fill(AmenTheme.Colors.amenPurple.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your profile")
            .accessibilityHint("Opens your profile and settings")
        }
    }

    // MARK: - Feature Rows

    private var featureRowsSection: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "books.vertical.fill",
                tint: AmenTheme.Colors.amenGold,
                title: "Scripture Library",
                subtitle: "Your verses, notes & audio",
                accessibilityLabel: "Scripture Library. Your verses, notes and audio.",
                action: onScriptureTapped
            )

            Divider()
                .background(AmenTheme.Colors.separatorSubtle)
                .padding(.leading, 60)

            featureRow(
                icon: "hands.sparkles.fill",
                tint: AmenTheme.Colors.amenPurple,
                title: "Prayer Commitments",
                subtitle: "Check off your prayer list",
                accessibilityLabel: "Prayer Commitments. Check off your prayer list.",
                action: onPrayerCommitmentsTapped
            )

            Divider()
                .background(AmenTheme.Colors.separatorSubtle)
                .padding(.leading, 60)

            featureRow(
                icon: "building.2.fill",
                tint: AmenTheme.Colors.amenBlue,
                title: "External Connections",
                subtitle: "Connect with other ministries",
                accessibilityLabel: "External Connections. Connect with other ministries.",
                action: onExternalConnectionsTapped
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        )
    }

    private func featureRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.impact(style: .light)
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(AmenPressableRowStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Quick Create Grid

    private var quickCreateGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AmenCreateType.allCases, id: \.rawValue) { type in
                createTile(type: type)
            }
        }
    }

    private func createTile(type: AmenCreateType) -> some View {
        Button {
            HapticManager.impact(style: .light)
            onCreateTapped(type)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(type.tintColor)
                    .padding(.bottom, 2)

                Text(type.displayName)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text(type.subtitle)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 100)
            .background(createTileBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName). \(type.subtitle).")
        .accessibilityHint("Creates a new \(type.displayName.lowercased())")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var createTileBackground: some View {
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

    // MARK: - Recent Files

    @ViewBuilder
    private var recentFilesSection: some View {
        if viewModel.isLoading {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    recentFileSkeleton
                    Divider()
                        .background(AmenTheme.Colors.separatorSubtle)
                        .padding(.leading, 52)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
            )
        } else if viewModel.recentFiles.isEmpty {
            Text("No recent files")
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.recentFiles.enumerated()), id: \.element.id) { index, file in
                    recentFileRow(file: file)
                    if index < viewModel.recentFiles.count - 1 {
                        Divider()
                            .background(AmenTheme.Colors.separatorSubtle)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
            )
        }
    }

    private func recentFileRow(file: AmenMoreViewModel.RecentFile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fileTypeColor(file.fileType).opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: fileTypeIcon(file.fileType))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(fileTypeColor(file.fileType))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text("\(file.formattedSize) · \(file.modifiedDate.relativeFormatted)")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                HapticManager.impact(style: .light)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .padding(8)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More options for \(file.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(file.formattedSize), \(file.modifiedDate.relativeFormatted)")
    }

    private var recentFileSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                skeletonBar(width: 160, height: 13)
                skeletonBar(width: 90, height: 10)
            }

            Spacer(minLength: 0)

            skeletonBar(width: 20, height: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityHidden(true)
    }

    // MARK: - Starred Empty State

    private var starredEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "star.fill")
                .font(.system(size: 30))
                .foregroundStyle(AmenTheme.Colors.amenGold)

            Text("Star important messages and files")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Button {
                HapticManager.impact(style: .light)
            } label: {
                Text("Get Started")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AmenTheme.Colors.amenGold)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get started with starred items")
            .accessibilityHint("Learn how to star messages and files")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AMENFont.semiBold(12))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .tracking(0.5)
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(AmenTheme.Colors.shimmerBase)
            .frame(width: width, height: height)
    }

    private func fileTypeIcon(_ fileType: String) -> String {
        switch fileType {
        case "audio":  return "waveform"
        case "image":  return "photo.fill"
        case "pdf":    return "doc.fill"
        default:       return "doc.text.fill"
        }
    }

    private func fileTypeColor(_ fileType: String) -> Color {
        switch fileType {
        case "audio":  return AmenTheme.Colors.amenPurple
        case "image":  return AmenTheme.Colors.amenBlue
        case "pdf":    return AmenTheme.Colors.amenGold
        default:       return AmenTheme.Colors.textSecondary
        }
    }
}

// MARK: - AmenPressableRowStyle

/// A ButtonStyle that applies a subtle pressed-state overlay on the row background.
private struct AmenPressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? AmenTheme.Colors.pressedOverlay
                    : Color.clear
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

// MARK: - Date relative formatting helper

private extension Date {
    var relativeFormatted: String {
        let seconds = -timeIntervalSinceNow
        if seconds < 3600 {
            let mins = Int(seconds / 60)
            return mins <= 1 ? "Just now" : "\(mins)m ago"
        } else if seconds < 86400 {
            let hrs = Int(seconds / 3600)
            return "\(hrs)h ago"
        } else {
            let days = Int(seconds / 86400)
            return days == 1 ? "Yesterday" : "\(days)d ago"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Light") {
    AmenMoreSheetView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AmenMoreSheetView()
        .preferredColorScheme(.dark)
}

#Preview("Reduce Motion") {
    AmenMoreSheetView()
}
#endif
