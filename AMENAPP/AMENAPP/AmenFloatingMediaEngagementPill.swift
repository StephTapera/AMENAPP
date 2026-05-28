import SwiftUI
import Foundation

struct AmenMediaEngagementPerson: Identifiable, Hashable {
    enum EngagementType: String, Hashable {
        case closeFriend
        case prayed
        case replied
        case community
        case viewed

        var displayName: String {
            switch self {
            case .closeFriend: return "Close friend"
            case .prayed: return "Prayed"
            case .replied: return "Discussing"
            case .community: return "Community"
            case .viewed: return "Present"
            }
        }

        var priority: Int {
            switch self {
            case .closeFriend: return 0
            case .prayed: return 1
            case .replied: return 2
            case .community: return 3
            case .viewed: return 4
            }
        }
    }

    let id: String
    let displayName: String
    let avatarURL: String?
    let engagementType: EngagementType
    let canShowEngagementType: Bool
}

enum AmenMediaPresenceContext: Hashable {
    case standard
    case prayer
    case community(name: String?)
    case bereanDiscussion
    case reflection

    var trayTitle: String {
        switch self {
        case .standard: return "People engaging"
        case .prayer: return "Praying with this"
        case .community: return "Community around this"
        case .bereanDiscussion: return "Discussion active"
        case .reflection: return "Reflect on this"
        }
    }

    var fallbackSystemImage: String {
        switch self {
        case .standard: return "sparkles"
        case .prayer: return "hands.sparkles"
        case .community: return "building.columns"
        case .bereanDiscussion: return "text.book.closed"
        case .reflection: return "sparkle.magnifyingglass"
        }
    }

    var trailingSystemImage: String {
        switch self {
        case .community: return "building.columns.fill"
        case .bereanDiscussion: return "book.closed.fill"
        case .reflection: return "sparkles"
        default: return "chevron.right"
        }
    }

    var tint: Color {
        switch self {
        case .standard: return Color.white
        case .prayer: return Color(red: 1.0, green: 0.80, blue: 0.56)
        case .community: return Color(red: 0.70, green: 0.88, blue: 1.0)
        case .bereanDiscussion: return Color(red: 0.78, green: 0.74, blue: 1.0)
        case .reflection: return Color(red: 0.82, green: 0.92, blue: 0.86)
        }
    }

    var shouldPulse: Bool {
        switch self {
        case .prayer, .bereanDiscussion: return true
        default: return false
        }
    }
}

struct AmenMediaEngagementPillModel: Hashable {
    let people: [AmenMediaEngagementPerson]
    let fallbackTitle: String?
    let fallbackSystemImage: String?
    let context: AmenMediaPresenceContext
    let statusText: String?

    var trayTitle: String { context.trayTitle }

    var hasVisibleContent: Bool {
        !people.isEmpty || fallbackTitle != nil || statusText != nil
    }
}

struct AmenFloatingMediaEngagementPill: View {
    let model: AmenMediaEngagementPillModel
    let foregroundStyle: AmenFloatingMediaEngagementForeground
    let isDimmed: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var ambientPulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leadingPresence

                if let statusText = model.statusText ?? model.fallbackTitle {
                    Text(statusText)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }

                Image(systemName: model.context.trailingSystemImage)
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(width: 22, height: 28)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(foregroundColor)
            .padding(.leading, model.people.isEmpty ? 10 : 8)
            .padding(.trailing, 7)
            .frame(minHeight: 44)
            .background(pillBackground)
            .overlay(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(reduceTransparency ? 0 : 0.18))
                    .frame(height: 12)
                    .padding(.horizontal, 12)
                    .blur(radius: 8)
                    .opacity(0.54)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(reduceTransparency ? 0 : 0.36), lineWidth: 0.75)
            }
            .shadow(color: shadowColor, radius: isDimmed ? 8 : 16, x: 0, y: isDimmed ? 4 : 9)
            .opacity(isDimmed ? 0.52 : 1)
            .scaleEffect(reduceMotion || !isDimmed ? 1 : 0.98)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("People engaging with this post")
        .accessibilityHint("Opens contextual presence around this media")
        .onAppear { startAmbientPulseIfNeeded() }
        .onChange(of: model.context) { _, _ in startAmbientPulseIfNeeded() }
    }

    @ViewBuilder
    private var leadingPresence: some View {
        if !model.people.isEmpty {
            avatarCluster
        } else {
            Image(systemName: model.fallbackSystemImage ?? model.context.fallbackSystemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(model.context.tint.opacity(reduceTransparency ? 0.12 : 0.20))
                        .scaleEffect(ambientPulse ? 1.12 : 0.94)
                        .opacity(model.context.shouldPulse ? 0.78 : 0.0)
                }
        }
    }

    private var avatarCluster: some View {
        HStack(spacing: -10) {
            ForEach(Array(model.people.prefix(3).enumerated()), id: \.element.id) { index, person in
                AmenFloatingMediaEngagementAvatar(
                    person: person,
                    foregroundColor: foregroundColor,
                    glowColor: person.engagementType == .prayed ? AmenMediaPresenceContext.prayer.tint : model.context.tint
                )
                .zIndex(Double(3 - index))
            }
        }
        .padding(.leading, 2)
        .background {
            if model.context.shouldPulse && !reduceMotion && !reduceTransparency {
                Capsule(style: .continuous)
                    .fill(model.context.tint.opacity(0.16))
                    .blur(radius: 8)
                    .scaleEffect(ambientPulse ? 1.10 : 0.94)
                    .opacity(ambientPulse ? 0.52 : 0.25)
            }
        }
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.82) : Color.white.opacity(0.94))
        } else {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(model.context.tint.opacity(contextTintOpacity))
                }
        }
    }

    private var contextTintOpacity: Double {
        switch model.context {
        case .standard: return 0.08
        case .reflection: return 0.11
        case .prayer: return 0.15
        case .community, .bereanDiscussion: return 0.13
        }
    }

    private var foregroundColor: Color {
        switch foregroundStyle {
        case .light: return .white
        case .dark: return .black.opacity(0.82)
        }
    }

    private var shadowColor: Color {
        switch foregroundStyle {
        case .light: return .black.opacity(0.26)
        case .dark: return model.context.tint.opacity(model.context == .standard ? 0.10 : 0.22)
        }
    }

    private func startAmbientPulseIfNeeded() {
        guard model.context.shouldPulse, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        ambientPulse = false
        withAnimation(.easeInOut(duration: model.context == .prayer ? 1.9 : 1.35).repeatForever(autoreverses: true)) {
            ambientPulse = true
        }
    }
}

enum AmenFloatingMediaEngagementForeground: Hashable {
    case light
    case dark
}

private struct AmenFloatingMediaEngagementAvatar: View {
    let person: AmenMediaEngagementPerson
    let foregroundColor: Color
    let glowColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(glowColor.opacity(person.engagementType == .prayed ? 0.24 : 0.10))
                .blur(radius: 4)
                .offset(y: 1)

            if let avatarURL = person.avatarURL, let url = URL(string: avatarURL) {
                CachedAsyncImage(url: url, size: CGSize(width: 30, height: 30)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.regularMaterial, lineWidth: 1.6)
        }
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.74), lineWidth: 0.9)
        }
        .shadow(color: glowColor.opacity(0.18), radius: 5, x: 0, y: 2)
        .accessibilityHidden(true)
    }

    private var initialsView: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay {
                Text(initials)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(foregroundColor)
                    .minimumScaleFactor(0.7)
            }
    }

    private var initials: String {
        let parts = person.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(parts).uppercased()
        return value.isEmpty ? "A" : value
    }
}

struct AmenMediaEngagementTray: View {
    let model: AmenMediaEngagementPillModel
    let onPray: () -> Void
    let onReply: () -> Void
    let onInvite: () -> Void
    let onViewProfile: (AmenMediaEngagementPerson) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.people.isEmpty {
                    fallbackState
                } else {
                    peopleList
                }
                quickActions
            }
            .navigationTitle(model.trayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(model.people.isEmpty ? 230 : 380), .medium])
        .presentationDragIndicator(.visible)
    }

    private var peopleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.people) { person in
                    Button {
                        onViewProfile(person)
                    } label: {
                        HStack(spacing: 12) {
                            AmenFloatingMediaEngagementAvatar(person: person, foregroundColor: .primary, glowColor: model.context.tint)
                                .frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(person.displayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if person.canShowEngagementType {
                                    Text(person.engagementType.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }

    private var fallbackState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.fallbackSystemImage ?? model.context.fallbackSystemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(model.context.tint)
            Text(model.fallbackTitle ?? model.statusText ?? "Community is present")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 128)
        .padding(.horizontal, 24)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            switch model.context {
            case .bereanDiscussion:
                trayAction("Study", systemImage: "text.book.closed", action: onReply)
                trayAction("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
                trayAction("Pray", systemImage: "hands.sparkles", action: onPray)
            case .reflection:
                trayAction("Reflect", systemImage: "sparkle.magnifyingglass", action: onReply)
                trayAction("Pray", systemImage: "hands.sparkles", action: onPray)
                trayAction("Save", systemImage: "bookmark", action: onInvite)
            default:
                trayAction("Pray", systemImage: "hands.sparkles", action: onPray)
                trayAction("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
                trayAction("Invite", systemImage: "person.badge.plus", action: onInvite)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func trayAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

#if DEBUG
private enum AmenFloatingMediaEngagementPillPreviewData {
    static let people = [
        AmenMediaEngagementPerson(id: "mentor-1", displayName: "Maya Flores", avatarURL: nil, engagementType: .closeFriend, canShowEngagementType: true),
        AmenMediaEngagementPerson(id: "prayer-1", displayName: "Jon Bell", avatarURL: nil, engagementType: .prayed, canShowEngagementType: false),
        AmenMediaEngagementPerson(id: "reply-1", displayName: "Ana Kim", avatarURL: nil, engagementType: .replied, canShowEngagementType: true)
    ]

    static let prayerModel = AmenMediaEngagementPillModel(
        people: people,
        fallbackTitle: nil,
        fallbackSystemImage: nil,
        context: .prayer,
        statusText: "3 praying now"
    )

    static let communityModel = AmenMediaEngagementPillModel(
        people: people,
        fallbackTitle: nil,
        fallbackSystemImage: nil,
        context: .community(name: "Young Adults"),
        statusText: "Young Adults here"
    )

    static let privatePrayerModel = AmenMediaEngagementPillModel(
        people: [],
        fallbackTitle: "Someone praying",
        fallbackSystemImage: "hands.sparkles",
        context: .prayer,
        statusText: nil
    )
}

#Preview("Presence Pill Small") {
    ZStack(alignment: .topTrailing) {
        LinearGradient(
            colors: [.black, .blue.opacity(0.68)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        AmenFloatingMediaEngagementPill(
            model: AmenFloatingMediaEngagementPillPreviewData.prayerModel,
            foregroundStyle: .light,
            isDimmed: false,
            action: {}
        )
        .padding(.top, 14)
        .padding(.trailing, 12)
    }
    .frame(width: 320, height: 220)
}

#Preview("Presence Pill Dark") {
    ZStack(alignment: .topTrailing) {
        Color.black
        AmenFloatingMediaEngagementPill(
            model: AmenFloatingMediaEngagementPillPreviewData.communityModel,
            foregroundStyle: .light,
            isDimmed: true,
            action: {}
        )
        .padding(.top, 18)
        .padding(.trailing, 18)
    }
    .frame(width: 430, height: 240)
    .environment(\.colorScheme, .dark)
}

#Preview("Presence Pill Private Prayer") {
    ZStack(alignment: .topTrailing) {
        Color(.systemBackground)
        AmenFloatingMediaEngagementPill(
            model: AmenFloatingMediaEngagementPillPreviewData.privatePrayerModel,
            foregroundStyle: .dark,
            isDimmed: false,
            action: {}
        )
        .padding(.top, 18)
        .padding(.trailing, 18)
    }
    .frame(width: 768, height: 300)
}
#endif
