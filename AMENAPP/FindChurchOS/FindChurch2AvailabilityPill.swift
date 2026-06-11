// FindChurch2AvailabilityPill.swift
// AMENAPP — Find Church 2.0, Wave 6 UI Refresh
//
// Status pills for church availability states.
//
// Design rules enforced:
//   - Glass background: .ultraThinMaterial + tint color at 0.12 opacity
//   - reduceTransparency fallback: solid tint at 0.15 opacity (no material)
//   - Luminous border: Color.white.opacity(0.45) strokeBorder 0.5pt
//   - No force-unwrap anywhere
//   - All text uses Dynamic Type (.caption2 style)
//   - Compact padding: 6pt horizontal, 4pt vertical

import SwiftUI

// MARK: - FindChurch2AvailabilityPill

struct FindChurch2AvailabilityPill: View {

    // MARK: PillType

    enum PillType {
        /// A regular service is happening today. `time` is optional (e.g. "10:30 AM").
        case serviceToday(time: String?)
        /// The building / ministry is open right now.
        case openNow
        /// A livestream is currently active or scheduled for today.
        case livestream
        /// A Bible study is happening tonight.
        case studyTonight
        /// Prayer ministry is available today.
        case prayerAvailable
    }

    let type: PillType

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    // MARK: Body

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(.caption2).weight(.semibold))
                .foregroundStyle(tintColor)
                .accessibilityHidden(true)

            Text(labelText)
                .font(.system(.caption2).weight(.semibold))
                .foregroundStyle(tintColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(pillBackground)
        .overlay(pillBorder)
        .clipShape(Capsule(style: .continuous))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Computed properties

    private var iconName: String {
        switch type {
        case .serviceToday:    return "clock"
        case .openNow:         return "circle.fill"
        case .livestream:      return "dot.radiowaves.right"
        case .studyTonight:    return "book"
        case .prayerAvailable: return "hands.sparkles"
        }
    }

    private var labelText: String {
        switch type {
        case .serviceToday(let time):
            if let time, !time.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Service Today \(time)"
            }
            return "Service Today"
        case .openNow:         return "Open Now"
        case .livestream:      return "Livestream"
        case .studyTonight:    return "Bible Study Tonight"
        case .prayerAvailable: return "Prayer Available"
        }
    }

    private var accessibilityLabel: String {
        switch type {
        case .serviceToday(let time):
            if let time, !time.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Service today at \(time)"
            }
            return "Service today"
        case .openNow:         return "Open now"
        case .livestream:      return "Livestream available"
        case .studyTonight:    return "Bible study tonight"
        case .prayerAvailable: return "Prayer available"
        }
    }

    private var tintColor: Color {
        switch type {
        case .serviceToday, .openNow: return Color(red: 0.18, green: 0.75, blue: 0.35)   // green
        case .livestream:             return Color(red: 0.95, green: 0.26, blue: 0.35)   // red/pink
        case .studyTonight:           return Color(red: 0.27, green: 0.53, blue: 0.96)   // blue
        case .prayerAvailable:        return Color(red: 0.60, green: 0.30, blue: 0.90)   // purple
        }
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            // Solid fallback — no material blur
            Capsule(style: .continuous)
                .fill(tintColor.opacity(0.15))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(tintColor.opacity(0.12))
                )
        }
    }

    private var pillBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                Color.white.opacity(contrast == .increased ? 0.55 : 0.45),
                lineWidth: 0.5
            )
    }
}

// MARK: - FindChurch2AvailabilityPillRow

/// Renders a horizontal row of `FindChurch2AvailabilityPill` views derived from an
/// `AvailabilityStatus`. Only shows pills for states that are true.
/// Returns no view (zero height) when all status flags are false.
struct FindChurch2AvailabilityPillRow: View {
    let status: AvailabilityStatus

    /// True when there are no active availability states to display.
    var isEmpty: Bool {
        !status.serviceToday
            && !status.openNow
            && !status.livestreamActive
            && !status.studyTonight
            && !status.prayerAvailable
    }

    var body: some View {
        if !isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // serviceToday has priority over openNow to avoid redundancy
                    if status.serviceToday {
                        FindChurch2AvailabilityPill(type: .serviceToday(time: status.serviceTime))
                    } else if status.openNow {
                        FindChurch2AvailabilityPill(type: .openNow)
                    }
                    if status.livestreamActive {
                        FindChurch2AvailabilityPill(type: .livestream)
                    }
                    if status.studyTonight {
                        FindChurch2AvailabilityPill(type: .studyTonight)
                    }
                    if status.prayerAvailable {
                        FindChurch2AvailabilityPill(type: .prayerAvailable)
                    }
                }
                .padding(.horizontal, 1) // avoid clip on pill border
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("All pills") {
    VStack(alignment: .leading, spacing: 12) {
        FindChurch2AvailabilityPill(type: .serviceToday(time: "10:30 AM"))
        FindChurch2AvailabilityPill(type: .serviceToday(time: nil))
        FindChurch2AvailabilityPill(type: .openNow)
        FindChurch2AvailabilityPill(type: .livestream)
        FindChurch2AvailabilityPill(type: .studyTonight)
        FindChurch2AvailabilityPill(type: .prayerAvailable)
    }
    .padding()
}

#Preview("Pill row — service + livestream") {
    let status = AvailabilityStatus(
        openNow: false,
        serviceToday: true,
        serviceTime: "9:00 AM",
        studyTonight: false,
        livestreamActive: true,
        prayerAvailable: false,
        contactNeeded: false,
        computedAt: Date()
    )
    FindChurch2AvailabilityPillRow(status: status)
        .padding()
}

#Preview("Pill row — empty (no output)") {
    let status = AvailabilityStatus.unknown
    FindChurch2AvailabilityPillRow(status: status)
        .padding()
}

#Preview("Pill row — reduce transparency") {
    let status = AvailabilityStatus(
        openNow: true,
        serviceToday: true,
        serviceTime: "11:00 AM",
        studyTonight: true,
        livestreamActive: false,
        prayerAvailable: true,
        contactNeeded: false,
        computedAt: Date()
    )
    FindChurch2AvailabilityPillRow(status: status)
        .padding()
        .environment(\.accessibilityReduceTransparency, true)
}
#endif
