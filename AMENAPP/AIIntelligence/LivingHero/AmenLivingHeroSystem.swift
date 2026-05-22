import SwiftUI

// MARK: - Amen Living Hero System

struct AmenLivingHeroScene: Identifiable, Equatable {
    let id: String
    let surface: AmenLivingHeroSurface
    let eyebrow: String
    let title: String
    let subtitle: String
    let detail: String?
    let primaryActionTitle: String?
    let secondaryActionTitle: String?
    let symbols: [String]
    let theme: AmenLivingHeroTheme

    init(
        id: String,
        surface: AmenLivingHeroSurface,
        eyebrow: String,
        title: String,
        subtitle: String,
        detail: String? = nil,
        primaryActionTitle: String? = nil,
        secondaryActionTitle: String? = nil,
        symbols: [String] = [],
        theme: AmenLivingHeroTheme = .scripture
    ) {
        self.id = id
        self.surface = surface
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.symbols = symbols
        self.theme = theme
    }
}

enum AmenLivingHeroSurface: String, CaseIterable, Identifiable {
    case dailyVerse
    case dailyDigest
    case discover
    case selah
    case bereanPulse
    case churchProfile
    case liveEvent
    case creatorKit

    var id: String { rawValue }

    var analyticsName: String { rawValue }
}

struct AmenLivingHeroTheme: Equatable {
    let accent: Color
    let secondaryAccent: Color
    let background: Color
    let symbolBackground: Color

    static let scripture = AmenLivingHeroTheme(
        accent: Color(red: 0.00, green: 0.28, blue: 0.26),
        secondaryAccent: Color(red: 0.96, green: 0.53, blue: 0.04),
        background: .white,
        symbolBackground: Color.black.opacity(0.055)
    )

    static let reflection = AmenLivingHeroTheme(
        accent: Color(red: 0.13, green: 0.26, blue: 0.58),
        secondaryAccent: Color(red: 0.12, green: 0.50, blue: 0.48),
        background: .white,
        symbolBackground: Color.black.opacity(0.052)
    )

    static let worship = AmenLivingHeroTheme(
        accent: Color(red: 0.54, green: 0.18, blue: 0.22),
        secondaryAccent: Color(red: 0.96, green: 0.53, blue: 0.04),
        background: .white,
        symbolBackground: Color.black.opacity(0.05)
    )

    static let discovery = AmenLivingHeroTheme(
        accent: Color(red: 0.06, green: 0.31, blue: 0.54),
        secondaryAccent: Color(red: 0.18, green: 0.56, blue: 0.36),
        background: .white,
        symbolBackground: Color.black.opacity(0.05)
    )
}

struct AmenLivingHeroMotionEngine: Equatable {
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let lowPowerMode: Bool
    let scrollActivity: CGFloat

    var shouldAnimate: Bool {
        !reduceMotion && !reduceTransparency && !lowPowerMode && scrollActivity < 0.58
    }

    var driftAnimation: Animation? {
        shouldAnimate ? .easeInOut(duration: 7.0).repeatForever(autoreverses: true) : nil
    }

    var cardAnimation: Animation? {
        shouldAnimate ? .spring(response: 0.75, dampingFraction: 0.86) : nil
    }
}

struct AmenLivingHeroView: View {
    let scene: AmenLivingHeroScene
    var scrollActivity: CGFloat = 0
    var onPrimaryAction: (() -> Void)?
    var onSecondaryAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var floated = false

    private var motion: AmenLivingHeroMotionEngine {
        AmenLivingHeroMotionEngine(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            scrollActivity: scrollActivity
        )
    }

    private var useFallback: Bool {
        reduceMotion || reduceTransparency || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        Group {
            if useFallback {
                AmenLivingHeroReduceMotionFallback(scene: scene, onPrimaryAction: onPrimaryAction, onSecondaryAction: onSecondaryAction)
            } else {
                AmenLivingHeroCard(
                    scene: scene,
                    motion: motion,
                    floated: floated,
                    highContrast: contrast == .increased,
                    dynamicTypeSize: dynamicTypeSize,
                    onPrimaryAction: onPrimaryAction,
                    onSecondaryAction: onSecondaryAction
                )
            }
        }
        .onAppear {
            AmenLivingHeroTelemetry.shared.trackImpression(scene)
            guard motion.shouldAnimate else { return }
            withAnimation(motion.driftAnimation) { floated = true }
        }
        .onDisappear {
            floated = false
        }
    }
}

struct AmenLivingHeroCard: View {
    let scene: AmenLivingHeroScene
    let motion: AmenLivingHeroMotionEngine
    let floated: Bool
    let highContrast: Bool
    let dynamicTypeSize: DynamicTypeSize
    let onPrimaryAction: (() -> Void)?
    let onSecondaryAction: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AmenLivingHeroAmbientLayer(scene: scene, floated: floated, motion: motion)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 14) {
                symbolCluster
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(scene.eyebrow.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(scene.theme.accent)
                        .lineLimit(1)

                    Text(scene.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(scene.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(highContrast ? 0.9 : 0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = scene.detail, !detail.isEmpty, !dynamicTypeSize.isAccessibilitySize {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.black.opacity(highContrast ? 0.82 : 0.58))
                            .lineLimit(2)
                    }

                    actionRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 180 : 148)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(highContrast ? 0.18 : 0.08), lineWidth: highContrast ? 1.2 : 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var symbolCluster: some View {
        ZStack {
            ForEach(Array(scene.symbols.prefix(4).enumerated()), id: \.offset) { index, symbol in
                Image(systemName: symbol)
                    .font(.system(size: index == 0 ? 23 : 18, weight: .semibold))
                    .foregroundStyle(index == 0 ? scene.theme.accent : scene.theme.secondaryAccent)
                    .frame(width: index == 0 ? 52 : 38, height: index == 0 ? 52 : 38)
                    .background(scene.theme.symbolBackground, in: Circle())
                    .offset(offset(for: index))
                    .scaleEffect(floated && motion.shouldAnimate ? 1.04 : 1.0)
                    .animation(motion.cardAnimation, value: floated)
            }
        }
        .frame(width: 72, height: 72)
    }

    @ViewBuilder
    private var actionRow: some View {
        if scene.primaryActionTitle != nil || scene.secondaryActionTitle != nil {
            HStack(spacing: 10) {
                if let title = scene.primaryActionTitle {
                    Button {
                        AmenLivingHeroTelemetry.shared.trackAction(scene, action: "primary")
                        onPrimaryAction?()
                    } label: {
                        Label(title, systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .tint(scene.theme.accent.opacity(0.16))
                }

                if let title = scene.secondaryActionTitle {
                    Button {
                        AmenLivingHeroTelemetry.shared.trackAction(scene, action: "secondary")
                        onSecondaryAction?()
                    } label: {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.black.opacity(0.74))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    private var accessibilityLabel: String {
        [scene.eyebrow, scene.title, scene.subtitle, scene.detail]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private func offset(for index: Int) -> CGSize {
        let direction: CGFloat = floated && motion.shouldAnimate ? 1 : -1
        switch index {
        case 0: return CGSize(width: direction * 1, y: direction * -2)
        case 1: return CGSize(width: 26 + direction * 3, y: -19 + direction * 2)
        case 2: return CGSize(width: -22 + direction * -2, y: 20 + direction * -1)
        default: return CGSize(width: 28 + direction * -2, y: 24 + direction * 2)
        }
    }
}

private struct AmenLivingHeroAmbientLayer: View {
    let scene: AmenLivingHeroScene
    let floated: Bool
    let motion: AmenLivingHeroMotionEngine

    var body: some View {
        ZStack {
            Circle()
                .fill(scene.theme.accent.opacity(0.10))
                .frame(width: 150, height: 150)
                .blur(radius: 34)
                .offset(x: floated && motion.shouldAnimate ? 98 : 78, y: floated && motion.shouldAnimate ? -40 : -20)

            Circle()
                .fill(scene.theme.secondaryAccent.opacity(0.10))
                .frame(width: 120, height: 120)
                .blur(radius: 30)
                .offset(x: floated && motion.shouldAnimate ? -86 : -62, y: floated && motion.shouldAnimate ? 72 : 54)
        }
    }
}

struct AmenLivingHeroReduceMotionFallback: View {
    let scene: AmenLivingHeroScene
    var onPrimaryAction: (() -> Void)?
    var onSecondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: scene.symbols.first ?? "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(scene.theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.055), in: Circle())
                    .accessibilityHidden(true)

                Text(scene.eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(scene.theme.accent)
                    .lineLimit(1)
            }

            Text(scene.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)

            Text(scene.subtitle)
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            if let detail = scene.detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.black.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.black.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

enum AmenLivingHeroContentResolver {
    static func dailyVerse(verse: PersonalizedDailyVerse?, digest: AmenDailyDigest?) -> AmenLivingHeroScene {
        let reference = verse?.reference ?? digest?.verseReference ?? "Daily Verse"
        let text = verse?.text ?? digest?.verseText ?? "Take a quiet moment with today's scripture."
        let reflection = verse?.reflection ?? digest?.reflectionText ?? digest?.contextText
        return AmenLivingHeroScene(
            id: "daily-verse-\(reference)",
            surface: .dailyVerse,
            eyebrow: "Scripture Focus",
            title: reference,
            subtitle: text,
            detail: reflection,
            primaryActionTitle: "Reflect",
            secondaryActionTitle: "Classic",
            symbols: ["book.closed", "sparkles", "hands.sparkles", "sun.max"],
            theme: .scripture
        )
    }

    static func dailyDigest(_ digest: AmenDailyDigest?) -> AmenLivingHeroScene {
        let digest = digest ?? AmenDailyDigest.fallback()
        return AmenLivingHeroScene(
            id: "daily-digest-\(digest.dateKey)",
            surface: .dailyDigest,
            eyebrow: digest.greeting,
            title: digest.title,
            subtitle: digest.contextText ?? digest.verseReference,
            detail: digest.reflectionText ?? digest.prayerPrompt,
            primaryActionTitle: digest.collapsedActions.first?.title,
            secondaryActionTitle: digest.collapsedActions.dropFirst().first?.title,
            symbols: ["sun.max", "book.closed", "calendar", "sparkles"],
            theme: .reflection
        )
    }

    static func discover(filter: String, itemCount: Int) -> AmenLivingHeroScene {
        AmenLivingHeroScene(
            id: "discover-\(filter)",
            surface: .discover,
            eyebrow: "Amen Discover",
            title: filter == "For You" ? "A curated path for today" : filter,
            subtitle: itemCount > 0 ? "Explore \(itemCount) church, teaching, Scripture, and community moments." : "Explore churches, teachings, Scripture, and community moments.",
            detail: "Recommendations stay grounded in AMEN context and discovery controls.",
            primaryActionTitle: "Explore",
            secondaryActionTitle: "Why this",
            symbols: ["safari", "building.2", "book.closed", "person.2"],
            theme: .discovery
        )
    }

    static func selah() -> AmenLivingHeroScene {
        AmenLivingHeroScene(
            id: "selah-reflection",
            surface: .selah,
            eyebrow: "Selah",
            title: "Pause with clarity",
            subtitle: "A focused reading space for Scripture, reflection, and next steps.",
            detail: "Motion stays outside the reading text and falls back to stillness when needed.",
            primaryActionTitle: "Continue",
            secondaryActionTitle: nil,
            symbols: ["pause.circle", "book.closed", "text.alignleft", "sparkles"],
            theme: .scripture
        )
    }

    static func bereanPulse() -> AmenLivingHeroScene {
        AmenLivingHeroScene(
            id: "berean-pulse",
            surface: .bereanPulse,
            eyebrow: "Berean Pulse",
            title: "Community rhythm and next best steps",
            subtitle: "Review contextual signals and continue with grounded actions.",
            detail: "No divine claims, only suggested context from AMEN activity.",
            primaryActionTitle: "Review",
            secondaryActionTitle: nil,
            symbols: ["waveform.path.ecg", "sparkles", "checklist", "book.closed"],
            theme: .reflection
        )
    }

    static func creatorKit() -> AmenLivingHeroScene {
        AmenLivingHeroScene(
            id: "creator-kit",
            surface: .creatorKit,
            eyebrow: "Creator Kit",
            title: "Create with review and intent",
            subtitle: "Captions, translation, explain, summarize, and prayer points stay grouped in one calm workspace.",
            detail: "AI-assisted outputs still require user review before use.",
            primaryActionTitle: "Start",
            secondaryActionTitle: nil,
            symbols: ["wand.and.stars", "mic", "text.bubble", "checkmark.seal"],
            theme: .discovery
        )
    }

    static func churchProfile(name: String, detail: String?) -> AmenLivingHeroScene {
        AmenLivingHeroScene(
            id: "church-profile-\(name)",
            surface: .churchProfile,
            eyebrow: "Current Church Moment",
            title: name,
            subtitle: detail ?? "Service times, location, and next steps stay close without replacing the profile.",
            detail: "Use Plan My Visit, directions, and contact actions from the existing profile.",
            primaryActionTitle: "Plan Visit",
            secondaryActionTitle: nil,
            symbols: ["building.2", "calendar", "location", "hands.sparkles"],
            theme: .discovery
        )
    }

    static func liveEvent(title: String, category: String, detail: String?) -> AmenLivingHeroScene {
        AmenLivingHeroScene(
            id: "live-event-\(title)",
            surface: .liveEvent,
            eyebrow: category,
            title: title,
            subtitle: detail ?? "A worship, service, or community gathering moment.",
            detail: "Event details and RSVP remain the source of truth.",
            primaryActionTitle: "View Event",
            secondaryActionTitle: nil,
            symbols: ["calendar", "music.note", "person.3", "sparkles"],
            theme: .worship
        )
    }
}

@MainActor
final class AmenLivingHeroTelemetry {
    static let shared = AmenLivingHeroTelemetry()

    private init() {}

    func trackImpression(_ scene: AmenLivingHeroScene) {
        guard AMENFeatureFlags.shared.spatialHeroPerformanceTelemetryEnabled else { return }
        // Hook point for production analytics. Kept no-op until event taxonomy is approved.
        _ = scene.analyticsName
    }

    func trackAction(_ scene: AmenLivingHeroScene, action: String) {
        guard AMENFeatureFlags.shared.spatialHeroPerformanceTelemetryEnabled else { return }
        _ = "\(scene.analyticsName)_\(action)"
    }
}

extension AmenLivingHeroScene {
    var analyticsName: String { surface.analyticsName }
}

extension AMENFeatureFlags {
    func isLivingHeroEnabled(for surface: AmenLivingHeroSurface) -> Bool {
        guard ambientSpatialHeroEnabled, livingEditorialBannerEnabled else { return false }
        switch surface {
        case .dailyVerse: return dailyVerseLivingHeroEnabled
        case .dailyDigest: return dailyDigestLivingHeroEnabled
        case .discover: return discoverLivingHeroEnabled
        case .selah: return selahLivingHeroEnabled
        case .bereanPulse: return bereanPulseLivingHeroEnabled
        case .churchProfile: return churchProfileLivingHeroEnabled
        case .liveEvent: return liveEventLivingHeroEnabled
        case .creatorKit: return creatorKitLivingHeroEnabled
        }
    }
}
