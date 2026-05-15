import SwiftUI
import FirebaseAnalytics

// MARK: - SacredFeedMode
// User-facing feed modes with spiritual framing.
// Maps to HeyFeedSessionMode ranking adjustments — no new ranking engine needed.

enum SacredFeedMode: String, CaseIterable, Identifiable {
    case encourage      = "encourage"
    case reflect        = "reflect"
    case learn          = "learn"
    case connect        = "connect"
    case recover        = "recover"
    case healthyMix     = "healthy_mix"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .encourage:    return "Encourage"
        case .reflect:      return "Reflect"
        case .learn:        return "Learn"
        case .connect:      return "Connect"
        case .recover:      return "Recover"
        case .healthyMix:   return "Healthy Mix"
        }
    }

    var icon: String {
        switch self {
        case .encourage:    return "heart"
        case .reflect:      return "moon.stars"
        case .learn:        return "book"
        case .connect:      return "person.2"
        case .recover:      return "leaf"
        case .healthyMix:   return "dial.medium"
        }
    }

    var description: String {
        switch self {
        case .encourage:  return "Uplifting testimonies, prayer, hope, and lighter tone"
        case .reflect:    return "Church notes, Scripture, and thoughtful prompts"
        case .learn:      return "Teaching, study, and deeper biblical discussion"
        case .connect:    return "Nearby community, events, people, and prayer needs"
        case .recover:    return "Low-noise and calm — less heavy, less debate"
        case .healthyMix: return "Balanced variety with spiritual diversity"
        }
    }

    // Maps to the equivalent HeyFeedSessionMode for ranking
    var sessionMode: HeyFeedSessionMode {
        switch self {
        case .encourage:    return .moreEncouragement
        case .reflect:      return .morePrayerTestimonies
        case .learn:        return .moreBibleTeaching
        case .connect:      return .moreLocalChurches
        case .recover:      return .lighterTonight
        case .healthyMix:   return .none
        }
    }

    // Additional ranking adjustments layered on top of the base session mode
    var extraRankingAdjustments: [String: Double] {
        switch self {
        case .encourage:
            return ["hope": +0.15, "joy": +0.12, "healing": +0.10, "controversy": -0.20]
        case .reflect:
            return ["sermon_notes": +0.25, "scripture_reflection": +0.22, "devotional": +0.18,
                    "debate": -0.25, "trending": -0.20]
        case .learn:
            return ["bible_teaching": +0.28, "exegesis": +0.20, "commentary": +0.18,
                    "entertainment": -0.15]
        case .connect:
            return ["local_churches": +0.28, "community_events": +0.22, "prayer_community": +0.18]
        case .recover:
            return ["calm": +0.20, "gentle": +0.15, "debate": -0.35, "controversy": -0.35,
                    "intense": -0.30, "trending": -0.25]
        case .healthyMix:
            return ["diversity_boost": +0.10]
        }
    }
}

// MARK: - SacredFeedModeService

@MainActor
final class SacredFeedModeService: ObservableObject {
    static let shared = SacredFeedModeService()

    @Published var activeMode: SacredFeedMode? = nil
    @Published var modeExpiresAt: Date? = nil

    private let modeKey = "sacredFeedMode"
    private let expiryKey = "sacredFeedModeExpiry"

    private init() { loadFromDefaults() }

    // MARK: Activate

    func activate(_ mode: SacredFeedMode, duration: HeyFeedDuration = .today) {
        let expiry = duration == .persistent ? nil : duration.expiryDate
        activeMode = mode
        modeExpiresAt = expiry

        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        if let exp = expiry {
            UserDefaults.standard.set(exp.timeIntervalSince1970, forKey: expiryKey)
        } else {
            UserDefaults.standard.removeObject(forKey: expiryKey)
        }

        // Activate the mapped HeyFeedSessionMode
        HeyFeedSessionModeService.shared.setMode(mode.sessionMode, duration: duration)

        Analytics.logEvent("sacred_feed_mode_activated", parameters: [
            "mode": mode.rawValue,
            "duration": duration.rawValue
        ])
    }

    func deactivate() {
        activeMode = nil
        modeExpiresAt = nil
        UserDefaults.standard.removeObject(forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
        HeyFeedSessionModeService.shared.clearMode()
        Analytics.logEvent("sacred_feed_mode_cleared", parameters: [:])
    }

    // MARK: Expiry check

    var isActive: Bool {
        guard let mode = activeMode else { return false }
        _ = mode // silence unused
        if let exp = modeExpiresAt, exp < Date() {
            deactivate()
            return false
        }
        return true
    }

    var activeModeSummary: String? {
        guard isActive, let mode = activeMode else { return nil }
        return "Feed tuned for \(mode.displayName.lowercased())"
    }

    // MARK: Persist

    private func loadFromDefaults() {
        guard let raw = UserDefaults.standard.string(forKey: modeKey),
              let mode = SacredFeedMode(rawValue: raw) else { return }
        let expiryTs = UserDefaults.standard.double(forKey: expiryKey)
        let expiry = expiryTs > 0 ? Date(timeIntervalSince1970: expiryTs) : nil
        if let exp = expiry, exp < Date() { return }
        activeMode = mode
        modeExpiresAt = expiry
    }
}

// MARK: - SacredFeedModeBar
// One-tap horizontal mode switcher. Shows below the feed mode bar or in HeyFeedControls.

struct SacredFeedModeBar: View {

    @ObservedObject private var service = SacredFeedModeService.shared
    @State private var showDurationPicker = false
    @State private var pendingMode: SacredFeedMode? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SacredFeedMode.allCases) { mode in
                    SacredFeedModePill(
                        mode: mode,
                        isActive: service.activeMode == mode && service.isActive
                    ) {
                        if service.activeMode == mode && service.isActive {
                            service.deactivate()
                        } else {
                            pendingMode = mode
                            showDurationPicker = true
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
        .sheet(isPresented: $showDurationPicker) {
            if let mode = pendingMode {
                SacredModeDurationSheet(mode: mode) { duration in
                    service.activate(mode, duration: duration)
                }
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Mode Pill

private struct SacredFeedModePill: View {
    let mode: SacredFeedMode
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(mode.displayName)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(isActive ? Color(.systemBackground) : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isActive ? Color.primary : Color(.systemGray6))
                    .shadow(color: isActive ? Color.black.opacity(0.14) : .clear, radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName + (isActive ? ", active" : ""))
    }
}

// MARK: - Duration Sheet

private struct SacredModeDurationSheet: View {
    let mode: SacredFeedMode
    let onActivate: (HeyFeedDuration) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 20)

            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 22, weight: .light))
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName + " Mode")
                        .font(AMENFont.semiBold(18))
                    Text(mode.description)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            VStack(spacing: 10) {
                ForEach(durations, id: \.rawValue) { duration in
                    Button {
                        onActivate(duration)
                        dismiss()
                    } label: {
                        HStack {
                            Text(duration.displayLabel)
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(duration.shortDescription)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.systemGray6))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var durations: [HeyFeedDuration] {
        [.session, .today, .threeDays, .sevenDays, .persistent]
    }
}

// MARK: - AlgorithmStateBar
// Subtle persistent bar showing what's currently shaping the feed.
// Appears below the ChapelInboxBar when any active tuning is in effect.

struct AlgorithmStateBar: View {

    @ObservedObject private var modeService = SacredFeedModeService.shared
    @ObservedObject private var nlService = HeyFeedNLPreferencesService.shared

    var onTap: () -> Void   // open HeyFeed controls

    var body: some View {
        if let summary = stateSummary {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: "dial.medium")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(summary)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .onTapGesture { clearAll() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(.systemGray6))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Summary text

    private var stateSummary: String? {
        var parts: [String] = []

        if modeService.isActive, let mode = modeService.activeMode {
            parts.append(mode.displayName + " mode")
        }

        let activeNL = nlService.activePreferences.prefix(2)
        for pref in activeNL {
            parts.append(pref.shortSummary)
        }

        if parts.isEmpty { return nil }
        return "Feed tuned for " + parts.joined(separator: " · ")
    }

    private func clearAll() {
        modeService.deactivate()
        nlService.clearAll()
    }
}

// MARK: - HeyFeedDuration display helpers

extension HeyFeedDuration {
    var displayLabel: String {
        switch self {
        case .session:    return "This session"
        case .today:      return "Today"
        case .threeDays:  return "3 days"
        case .sevenDays:  return "7 days"
        case .persistent: return "Until I change it"
        }
    }

    var shortDescription: String {
        switch self {
        case .session:    return "~3 hours"
        case .today:      return "Until midnight"
        case .threeDays:  return "72 hours"
        case .sevenDays:  return "One week"
        case .persistent: return "No expiry"
        }
    }

    var expiryDate: Date {
        switch self {
        case .session:    return Date().addingTimeInterval(3 * 3600)
        case .today:
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = 23; comps.minute = 59
            return Calendar.current.date(from: comps) ?? Date().addingTimeInterval(24 * 3600)
        case .threeDays:  return Date().addingTimeInterval(3 * 24 * 3600)
        case .sevenDays:  return Date().addingTimeInterval(7 * 24 * 3600)
        case .persistent: return .distantFuture
        }
    }
}

// MARK: - HeyFeedNLPreference short summary helper

extension HeyFeedNLPreference {
    var shortSummary: String {
        let verb: String
        switch action {
        case .increase: verb = "more"
        case .decrease: verb = "less"
        case .mute:     verb = "no"
        case .explore:  verb = "explore"
        case .balance:  verb = "balanced"
        }
        return "\(verb) \(targetLabel.lowercased())"
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        SacredFeedModeBar()
        AlgorithmStateBar(onTap: {})
    }
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
}
