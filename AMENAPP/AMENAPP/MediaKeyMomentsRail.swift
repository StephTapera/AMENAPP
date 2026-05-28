// AmenLegacyAmenLegacyMediaKeyMomentsRail.swift
// AMEN App — Media System
//
// Horizontal scrolling rail of Liquid Glass chapter/key-moment pills.
// Spiritually themed: prayer, scripture, testimony, teaching, reflection,
// call-to-action, and worship moment kinds.
// Gated by AMENFeatureFlags.shared.mediaKeyMomentsEnabled (defaults false).
// Only approved moments are shown; draft moments are filtered out.
// Analytics: AMENAnalyticsService.shared.track(.feedMeaningfulInteraction)

import SwiftUI

// MARK: - Models

struct AmenLegacyMediaKeyMoment: Identifiable, Equatable {
    let id: String
    let title: String
    let timestamp: TimeInterval
    let kind: AmenLegacyAmenLegacyMediaKeyMomentKind
    var isApproved: Bool = true
}

enum AmenLegacyAmenLegacyMediaKeyMomentKind: String, CaseIterable {
    case prayer
    case scripture
    case testimony
    case teaching
    case reflection
    case callToAction
    case worship

    var systemImage: String {
        switch self {
        case .prayer:        return "hands.sparkles"
        case .scripture:     return "book.fill"
        case .testimony:     return "person.fill"
        case .teaching:      return "graduationcap.fill"
        case .reflection:    return "moon.stars.fill"
        case .callToAction:  return "arrow.right.circle.fill"
        case .worship:       return "music.note"
        }
    }

    var tintColor: Color {
        switch self {
        case .prayer:        return Color(red: 0.98, green: 0.80, blue: 0.46)   // warm gold
        case .scripture:     return Color(red: 0.48, green: 0.72, blue: 1.00)   // sky blue
        case .testimony:     return Color(red: 0.62, green: 0.90, blue: 0.72)   // mint green
        case .teaching:      return Color(red: 0.76, green: 0.60, blue: 1.00)   // lavender
        case .reflection:    return Color(red: 0.56, green: 0.78, blue: 0.98)   // soft periwinkle
        case .callToAction:  return Color(red: 1.00, green: 0.50, blue: 0.38)   // coral
        case .worship:       return Color(red: 0.95, green: 0.62, blue: 0.88)   // rose pink
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .prayer:        return "Prayer"
        case .scripture:     return "Scripture"
        case .testimony:     return "Testimony"
        case .teaching:      return "Teaching"
        case .reflection:    return "Reflection"
        case .callToAction:  return "Call to action"
        case .worship:       return "Worship"
        }
    }
}

// MARK: - Rail View

struct AmenLegacyAmenLegacyMediaKeyMomentsRail: View {
    let moments: [AmenLegacyMediaKeyMoment]
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Computed

    /// Filters out unapproved (draft) moments so only public-ready content is shown.
    private var visibleMoments: [AmenLegacyMediaKeyMoment] {
        moments.filter { $0.isApproved }
    }

    /// The currently active moment: the last one whose timestamp has been passed.
    private var activeMomentID: String? {
        visibleMoments
            .filter { $0.timestamp <= currentTime }
            .last?.id
    }

    // MARK: Guard

    private var shouldShow: Bool {
        AMENFeatureFlags.shared.mediaKeyMomentsEnabled && !visibleMoments.isEmpty
    }

    // MARK: Body

    var body: some View {
        Group {
            if shouldShow {
                rail
            }
        }
    }

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleMoments) { moment in
                    pill(for: moment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Key moments rail")
    }

    // MARK: Pill

    @ViewBuilder
    private func pill(for moment: AmenLegacyMediaKeyMoment) -> some View {
        let isActive = moment.id == activeMomentID

        Button {
            onSeek(moment.timestamp)
            AMENAnalyticsService.shared.track(
                .feedMeaningfulInteraction(type: "key_moment_tapped")
            )
        } label: {
            pillLabel(for: moment, isActive: isActive)
        }
        .buttonStyle(KeyMomentPillButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("\(moment.kind.accessibilityDescription): \(moment.title)")
        .accessibilityHint("Seek to \(formattedTimestamp(moment.timestamp))")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .animation(
            reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.78),
            value: isActive
        )
    }

    @ViewBuilder
    private func pillLabel(for moment: AmenLegacyMediaKeyMoment, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: moment.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(moment.kind.tintColor)
                .accessibilityHidden(true)

            Text(moment.title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 0)
        .frame(height: 28)
        .background(pillBackground(for: moment, isActive: isActive))
        .scaleEffect(isActive ? 1.06 : 1.0)
        .opacity(isActive ? 1.0 : 0.70)
    }

    @ViewBuilder
    private func pillBackground(for moment: AmenLegacyMediaKeyMoment, isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                reduceTransparency
                    ? AnyShapeStyle(
                        isActive
                            ? Color(uiColor: .secondarySystemBackground)
                            : Color(uiColor: .tertiarySystemBackground)
                      )
                    : AnyShapeStyle(.regularMaterial)
            )
            .overlay {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(moment.kind.tintColor.opacity(isActive ? 0.14 : 0.06))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isActive
                            ? moment.kind.tintColor.opacity(0.45)
                            : Color.white.opacity(reduceTransparency ? 0.0 : 0.18),
                        lineWidth: isActive ? 1.0 : 0.6
                    )
            }
    }

    // MARK: Helpers

    private func formattedTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Press Button Style

private struct KeyMomentPillButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.70),
                value: configuration.isPressed
            )
    }
}

// MARK: - Previews

#if DEBUG
private let previewMoments: [AmenLegacyMediaKeyMoment] = [
    AmenLegacyMediaKeyMoment(id: "m1", title: "Opening Prayer",    timestamp: 0,    kind: .prayer),
    AmenLegacyMediaKeyMoment(id: "m2", title: "Romans 8:28",       timestamp: 45,   kind: .scripture),
    AmenLegacyMediaKeyMoment(id: "m3", title: "My Testimony",      timestamp: 130,  kind: .testimony),
    AmenLegacyMediaKeyMoment(id: "m4", title: "The Grace Lesson",  timestamp: 240,  kind: .teaching),
    AmenLegacyMediaKeyMoment(id: "m5", title: "Selah",             timestamp: 390,  kind: .reflection),
    AmenLegacyMediaKeyMoment(id: "m6", title: "Come Forward",      timestamp: 480,  kind: .callToAction),
    AmenLegacyMediaKeyMoment(id: "m7", title: "How Great Thou Art",timestamp: 540,  kind: .worship),
    // Draft moment — should not appear
    AmenLegacyMediaKeyMoment(id: "m8", title: "Draft Notes",       timestamp: 100,  kind: .teaching, isApproved: false),
]

#Preview("Rail — mid-session") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            AmenLegacyAmenLegacyMediaKeyMomentsRail(
                moments: previewMoments,
                currentTime: 135,
                onSeek: { _ in }
            )
            .background(.black.opacity(0.20))
        }
    }
    .onAppear {
        // Force flag on in previews
        // AMENFeatureFlags.shared.mediaKeyMomentsEnabled is false by default;
        // swap to a local override struct in a real preview harness if needed.
    }
}

#Preview("Rail — Reduce Transparency") {
    ZStack {
        LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack {
            Spacer()
            AmenLegacyAmenLegacyMediaKeyMomentsRail(
                moments: previewMoments,
                currentTime: 250,
                onSeek: { _ in }
            )
        }
    }
}

#Preview("Rail — Reduce Motion") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        VStack {
            Spacer()
            AmenLegacyAmenLegacyMediaKeyMomentsRail(
                moments: previewMoments,
                currentTime: 50,
                onSeek: { _ in }
            )
        }
    }
}
#endif
