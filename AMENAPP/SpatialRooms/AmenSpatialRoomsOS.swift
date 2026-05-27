import SwiftUI

// MARK: - Amen Spatial Rooms OS

struct AmenSpatialRoom: Identifiable, Equatable {
    let id: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let kind: AmenSpatialRoomKind
    let atmosphere: AmenSpatialRoomAtmosphere
    let presence: AmenSpatialRoomPresence
    let primaryActionTitle: String
    let secondaryActionTitle: String?
    let isLocked: Bool
}

enum AmenSpatialRoomKind: String, CaseIterable, Equatable {
    case prayer
    case discussion
    case bibleStudy
    case church
    case creator
    case voice
    case event
    case community
    case selah
    case berean

    var icon: String {
        switch self {
        case .prayer: return "hands.sparkles.fill"
        case .discussion: return "bubble.left.and.bubble.right.fill"
        case .bibleStudy: return "book.closed.fill"
        case .church: return "building.columns.fill"
        case .creator: return "sparkles.rectangle.stack.fill"
        case .voice: return "waveform.circle.fill"
        case .event: return "calendar.badge.clock"
        case .community: return "person.3.sequence.fill"
        case .selah: return "moon.stars.fill"
        case .berean: return "text.magnifyingglass"
        }
    }
}

struct AmenSpatialRoomPresence: Equatable {
    var activeCount: Int
    var activityText: String
    var secondaryText: String
    var isLive: Bool
    var momentum: Double

    static let calm = AmenSpatialRoomPresence(
        activeCount: 0,
        activityText: "Quiet now",
        secondaryText: "Open for reflection",
        isLive: false,
        momentum: 0.18
    )
}

struct AmenSpatialRoomAtmosphere: Equatable {
    let base: Color
    let mid: Color
    let glow: Color
    let textProtection: Color

    static func forKind(_ kind: AmenSpatialRoomKind) -> AmenSpatialRoomAtmosphere {
        switch kind {
        case .prayer:
            return AmenSpatialRoomAtmosphere(
                base: Color(red: 0.14, green: 0.19, blue: 0.31),
                mid: Color(red: 0.45, green: 0.50, blue: 0.67),
                glow: Color(red: 0.96, green: 0.82, blue: 0.58),
                textProtection: Color.black.opacity(0.58)
            )
        case .discussion, .berean:
            return AmenSpatialRoomAtmosphere(
                base: Color(red: 0.10, green: 0.13, blue: 0.16),
                mid: Color(red: 0.38, green: 0.31, blue: 0.24),
                glow: Color(red: 0.87, green: 0.66, blue: 0.34),
                textProtection: Color.black.opacity(0.64)
            )
        case .bibleStudy:
            return AmenSpatialRoomAtmosphere(
                base: Color(red: 0.10, green: 0.22, blue: 0.21),
                mid: Color(red: 0.34, green: 0.46, blue: 0.38),
                glow: Color(red: 0.85, green: 0.73, blue: 0.47),
                textProtection: Color.black.opacity(0.60)
            )
        case .church, .community, .creator:
            return AmenSpatialRoomAtmosphere(
                base: Color(red: 0.15, green: 0.20, blue: 0.24),
                mid: Color(red: 0.50, green: 0.45, blue: 0.37),
                glow: Color(red: 0.95, green: 0.66, blue: 0.38),
                textProtection: Color.black.opacity(0.56)
            )
        case .voice, .event:
            return AmenSpatialRoomAtmosphere(
                base: Color(red: 0.08, green: 0.18, blue: 0.29),
                mid: Color(red: 0.14, green: 0.46, blue: 0.50),
                glow: Color(red: 0.74, green: 0.88, blue: 0.82),
                textProtection: Color.black.opacity(0.58)
            )
        case .selah:
            return AmenSpatialRoomAtmosphere(
                base: Color(red: 0.12, green: 0.13, blue: 0.26),
                mid: Color(red: 0.34, green: 0.31, blue: 0.51),
                glow: Color(red: 0.82, green: 0.76, blue: 0.96),
                textProtection: Color.black.opacity(0.62)
            )
        }
    }
}

struct AmenSpatialRoomHeroCarousel: View {
    let rooms: [AmenSpatialRoom]
    var title: String = "Living Spaces"
    var subtitle: String = "Move through rooms shaped by prayer, study, presence, and live community."
    var onSelect: (AmenSpatialRoom) -> Void
    var onSecondaryAction: ((AmenSpatialRoom) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !rooms.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                header

                GeometryReader { proxy in
                    let cardWidth = min(proxy.size.width - 40, 360)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(rooms) { room in
                                AmenSpatialRoomCard(
                                    room: room,
                                    reduceMotion: reduceMotion,
                                    onSelect: { onSelect(room) },
                                    onSecondaryAction: { onSecondaryAction?(room) }
                                )
                                .frame(width: cardWidth, height: dynamicTypeSize.isAccessibilitySize ? 430 : 390)
                                .scrollTransition(.animated.threshold(.visible(0.65)), axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity || reduceMotion ? 1.0 : 0.96)
                                        .opacity(phase.isIdentity || reduceMotion ? 1.0 : 0.78)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 430 : 390)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
    }
}

private struct AmenSpatialRoomCard: View {
    let room: AmenSpatialRoom
    let reduceMotion: Bool
    let onSelect: () -> Void
    let onSecondaryAction: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var drift = false

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                AmenSpatialRoomEnvironment(room: room, drift: drift && !reduceMotion)
                    .accessibilityHidden(true)

                AmenSpatialReadabilityLayer(atmosphere: room.atmosphere)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    topPresenceRow
                    Spacer(minLength: 16)
                    contentBlock
                    controlDock
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(contrast == .increased ? 0.42 : 0.22), lineWidth: contrast == .increased ? 1.2 : 0.8)
            }
            .shadow(color: Color.black.opacity(reduceTransparency ? 0.08 : 0.22), radius: 22, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .onDisappear { drift = false }
    }

    private var topPresenceRow: some View {
        HStack(spacing: 8) {
            Label(room.presence.isLive ? "Live" : room.eyebrow, systemImage: room.presence.isLive ? "dot.radiowaves.left.and.right" : room.kind.icon)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(glassShape)

            Spacer(minLength: 8)

            if room.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(glassShape)
            }
        }
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(room.title)
                .font(.system(size: 30, weight: .bold, design: .default))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)

            Text(room.subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                AmenSpatialPresenceMetric(
                    value: room.presence.activeCount > 0 ? "\(room.presence.activeCount)" : "--",
                    label: room.presence.activityText
                )
                AmenSpatialPresenceMetric(
                    value: room.presence.isLive ? "On" : "Open",
                    label: room.presence.secondaryText
                )
            }
            .padding(.top, 2)
        }
    }

    private var controlDock: some View {
        HStack(spacing: 10) {
            Text(room.primaryActionTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(primaryActionBackground)
                .clipShape(Capsule())

            if let secondary = room.secondaryActionTitle {
                Button(action: onSecondaryAction) {
                    Text(secondary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .background(glassShape)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 18)
    }

    private var primaryActionBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color.white.opacity(0.24))
        }
        return AnyShapeStyle(Color.white.opacity(0.18))
    }

    private var glassShape: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color.black.opacity(0.28))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var accessibilityLabel: String {
        var parts = [room.title, room.subtitle, room.presence.activityText]
        if room.isLocked { parts.append("Locked") }
        if room.presence.isLive { parts.append("Live now") }
        return parts.joined(separator: ", ")
    }
}

private struct AmenSpatialRoomEnvironment: View {
    let room: AmenSpatialRoom
    let drift: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [room.atmosphere.base, room.atmosphere.mid, room.atmosphere.glow],
                startPoint: drift ? .topTrailing : .topLeading,
                endPoint: drift ? .bottomLeading : .bottomTrailing
            )

            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let waveOffset = drift ? CGFloat(sin(time * 0.34)) * 22 : 0
                    let highlightOffset = drift ? CGFloat(cos(time * 0.22)) * 18 : 0

                    var lowerPath = Path()
                    lowerPath.move(to: CGPoint(x: -30, y: size.height * 0.62 + waveOffset))
                    lowerPath.addCurve(
                        to: CGPoint(x: size.width + 40, y: size.height * 0.52 - waveOffset),
                        control1: CGPoint(x: size.width * 0.24, y: size.height * 0.44 - waveOffset),
                        control2: CGPoint(x: size.width * 0.72, y: size.height * 0.74 + waveOffset)
                    )
                    lowerPath.addLine(to: CGPoint(x: size.width + 40, y: size.height + 40))
                    lowerPath.addLine(to: CGPoint(x: -30, y: size.height + 40))
                    lowerPath.closeSubpath()

                    context.fill(
                        lowerPath,
                        with: .linearGradient(
                            Gradient(colors: [room.atmosphere.glow.opacity(0.34), room.atmosphere.base.opacity(0.12)]),
                            startPoint: CGPoint(x: 0, y: size.height * 0.48),
                            endPoint: CGPoint(x: size.width, y: size.height)
                        )
                    )

                    var upperPath = Path()
                    upperPath.move(to: CGPoint(x: -20, y: size.height * 0.18 + highlightOffset))
                    upperPath.addCurve(
                        to: CGPoint(x: size.width + 20, y: size.height * 0.30 - highlightOffset),
                        control1: CGPoint(x: size.width * 0.18, y: size.height * 0.10),
                        control2: CGPoint(x: size.width * 0.74, y: size.height * 0.42)
                    )
                    upperPath.addLine(to: CGPoint(x: size.width + 20, y: -20))
                    upperPath.addLine(to: CGPoint(x: -20, y: -20))
                    upperPath.closeSubpath()

                    context.fill(
                        upperPath,
                        with: .linearGradient(
                            Gradient(colors: [Color.white.opacity(0.24), room.atmosphere.mid.opacity(0.08)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: size.width, y: size.height * 0.44)
                        )
                    )
                }
            }
            .opacity(0.86)

            Image(systemName: room.kind.icon)
                .font(.system(size: 180, weight: .thin))
                .foregroundStyle(Color.white.opacity(0.08))
                .rotationEffect(.degrees(drift ? 4 : -3))
                .offset(x: 92, y: -72)
        }
    }
}

private struct AmenSpatialReadabilityLayer: View {
    let atmosphere: AmenSpatialRoomAtmosphere

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.12), Color.black.opacity(0.05), atmosphere.textProtection],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.black.opacity(0.38), Color.clear, Color.black.opacity(0.18)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private struct AmenSpatialPresenceMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension AmenSpatialRoom {
    static let discoverySeeds: [AmenSpatialRoom] = [
        AmenSpatialRoom(
            id: "spatial-prayer-room",
            eyebrow: "Prayer Room",
            title: "Evening Prayer",
            subtitle: "A quiet room for requests, voice prayer, and gentle reflection.",
            kind: .prayer,
            atmosphere: .forKind(.prayer),
            presence: AmenSpatialRoomPresence(activeCount: 14, activityText: "praying now", secondaryText: "voice prayer", isLive: true, momentum: 0.72),
            primaryActionTitle: "Join",
            secondaryActionTitle: "Listen",
            isLocked: false
        ),
        AmenSpatialRoom(
            id: "spatial-berean-study",
            eyebrow: "Bible Study",
            title: "Romans Study",
            subtitle: "Scripture-led discussion with context, questions, and live responses.",
            kind: .bibleStudy,
            atmosphere: .forKind(.bibleStudy),
            presence: AmenSpatialRoomPresence(activeCount: 9, activityText: "studying", secondaryText: "3 reflections", isLive: false, momentum: 0.54),
            primaryActionTitle: "Open",
            secondaryActionTitle: "Save",
            isLocked: false
        ),
        AmenSpatialRoom(
            id: "spatial-young-adults",
            eyebrow: "Community",
            title: "Young Adults Nearby",
            subtitle: "Local conversation, upcoming gatherings, and a live voice room.",
            kind: .community,
            atmosphere: .forKind(.community),
            presence: AmenSpatialRoomPresence(activeCount: 22, activityText: "active today", secondaryText: "event soon", isLive: true, momentum: 0.68),
            primaryActionTitle: "Explore",
            secondaryActionTitle: "Invite",
            isLocked: false
        )
    ]
}
