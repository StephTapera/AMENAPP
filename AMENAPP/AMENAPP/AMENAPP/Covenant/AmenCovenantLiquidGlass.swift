import SwiftUI

// MARK: - Moderation Banner State

enum ModerationBannerState: Equatable {
    case safe
    case needsEdit(suggestion: String)
    case sensitive
    case blocked
}

// MARK: - 1. CovenantGlassCard

struct CovenantGlassCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                                .fill(tint.opacity(0.10))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
            .shadow(
                color: LiquidGlassTokens.shadowSoft.color,
                radius: LiquidGlassTokens.shadowSoft.radius,
                y: LiquidGlassTokens.shadowSoft.y
            )
            .scaleEffect(isPressed ? 0.975 : 1.0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82),
                value: isPressed
            )
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
    }
}

// MARK: - 2. CovenantCreatorCard

struct CovenantCreatorCard: View {
    let displayName: String
    let tagline: String
    let avatarURL: String?
    let topics: [String]
    let badges: [TrustBadgeType]
    let onJoin: () -> Void

    var body: some View {
        CovenantGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let urlString = avatarURL, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    avatarFallback
                                }
                            }
                        } else {
                            avatarFallback
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(tagline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    CovenantCapsuleButton(title: "Join", variant: .primary, isLoading: false, action: onJoin)
                        .fixedSize()
                }

                if !topics.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(topics.prefix(3), id: \.self) { topic in
                                Text(topic)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !badges.isEmpty {
                    AmenTrustBadgeRow(badges: badges, size: .compact)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName). \(tagline)")
    }

    private var avatarFallback: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.2))
            Text(String(displayName.prefix(1)).uppercased())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 3. CovenantRoomRow

struct CovenantRoomRow: View {
    let room: CovenantRoom
    let isAccessible: Bool

    init(room: CovenantRoom, membership: CovenantMembership? = nil) {
        self.room = room
        self.isAccessible = AmenCovenantPermissions.canViewRoom(room: room, membership: membership)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: room.type.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isAccessible ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(room.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isAccessible ? Color.primary : Color.secondary)

                    if room.isLocked && !isAccessible {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let preview = room.lastMessage, isAccessible {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if room.unreadCount > 0 && isAccessible {
                Text(room.unreadCount > 99 ? "99+" : "\(room.unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor))
                    .accessibilityLabel("\(room.unreadCount) unread")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .opacity(isAccessible ? 1.0 : 0.5)
        .allowsHitTesting(isAccessible)
        .accessibilityLabel("\(room.name)\(room.isLocked && !isAccessible ? ", locked" : "")\(room.unreadCount > 0 ? ", \(room.unreadCount) unread" : "")")
    }
}

// MARK: - 4. CovenantDigestCard

struct CovenantDigestCard: View {
    let summaryTitle: String
    let highlights: [String]
    let fullBody: String

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CovenantGlassCard(tint: Color(uiColor: .systemAmber)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(summaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                ForEach(highlights.prefix(2), id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.orange.opacity(0.7))
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)
                        Text(highlight)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isExpanded {
                    Text(fullBody)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    withAnimation(
                        reduceMotion
                            ? .easeOut(duration: LiquidGlassTokens.motionFast)
                            : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.8)
                    ) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Catch up in 60 seconds")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse digest" : "Expand digest")
            }
        }
    }
}

// MARK: - 5. CovenantModerationBanner

struct CovenantModerationBanner: View {
    let state: ModerationBannerState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tintColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tintColor)
                if case .needsEdit(let suggestion) = state {
                    Text(suggestion)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tintColor.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tintColor.opacity(0.25), lineWidth: 0.5)
                )
        )
        .accessibilityLabel(headline)
    }

    private var iconName: String {
        switch state {
        case .safe:       return "checkmark.circle.fill"
        case .needsEdit:  return "pencil.circle.fill"
        case .sensitive:  return "exclamationmark.triangle.fill"
        case .blocked:    return "xmark.circle.fill"
        }
    }

    private var headline: String {
        switch state {
        case .safe:              return "Looks good"
        case .needsEdit:         return "Suggested edit"
        case .sensitive:         return "Sensitive content"
        case .blocked:           return "This message cannot be sent"
        }
    }

    private var tintColor: Color {
        switch state {
        case .safe:      return .green
        case .needsEdit: return Color(uiColor: .systemYellow)
        case .sensitive: return .orange
        case .blocked:   return .red
        }
    }
}

// MARK: - 6. CovenantCapsuleButton

struct CovenantCapsuleButton: View {
    enum Variant { case primary, secondary, destructive, quiet }

    let title: String
    let variant: Variant
    let isLoading: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                        .scaleEffect(0.8)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(foregroundColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(minWidth: 64)
            .background(background)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.8),
            value: isPressed
        )
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .disabled(isLoading)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .primary:
            Capsule().fill(Color.primary)
        case .secondary:
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
        case .destructive:
            Capsule().fill(Color.red)
        case .quiet:
            Capsule().fill(Color.clear)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:     return Color(uiColor: .systemBackground)
        case .secondary:   return .primary
        case .destructive: return .white
        case .quiet:       return .primary
        }
    }
}

// MARK: - 7. CovenantTabRail

struct CovenantTabRail: View {
    let tabs: [String]
    @Binding var selected: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs.indices, id: \.self) { index in
                    let isSelected = selected == index
                    Button {
                        withAnimation(
                            reduceMotion
                                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.78)
                        ) {
                            selected = index
                        }
                    } label: {
                        Text(tabs[index])
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.10))
                                        .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
                                        .matchedGeometryEffect(id: "tabRailSelection", in: selectionNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tabs[index])
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - UIColor Amber Helper

private extension UIColor {
    /// Amber — warm yellow-orange used for digest tinting.
    static var systemAmber: UIColor {
        UIColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
    }
}
