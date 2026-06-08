import SwiftUI
import FirebaseAnalytics

// MARK: - PostPublishTiming
// When a composed post should go live.
// "Post After Prayer" flow: the compose button offers these options
// instead of immediately publishing.

enum PostPublishTiming: String, CaseIterable, Identifiable {
    case now            = "now"
    case afterPrayer    = "after_prayer"
    case tonight        = "tonight"
    case tomorrowMorning = "tomorrow_morning"
    case saveDraft      = "save_draft"
    case trustedCircle  = "trusted_circle"

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .now:              return "Post now"
        case .afterPrayer:      return "Post after prayer"
        case .tonight:          return "Post tonight"
        case .tomorrowMorning:  return "Post tomorrow morning"
        case .saveDraft:        return "Save as private draft"
        case .trustedCircle:    return "Share with trusted circle first"
        }
    }

    var icon: String {
        switch self {
        case .now:              return "arrow.up.circle.fill"
        case .afterPrayer:      return "hands.sparkles"
        case .tonight:          return "moon.stars"
        case .tomorrowMorning:  return "sunrise"
        case .saveDraft:        return "lock"
        case .trustedCircle:    return "person.2.circle"
        }
    }

    var description: String {
        switch self {
        case .now:              return "Goes live immediately"
        case .afterPrayer:      return "Pause 15 minutes — then decide"
        case .tonight:          return "Around 8 PM"
        case .tomorrowMorning:  return "Around 8 AM"
        case .saveDraft:        return "Only you can see it"
        case .trustedCircle:    return "Share with close friends before posting publicly"
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .now: return false
        default:   return true
        }
    }

    // How many minutes to pause before surfacing the post prompt
    var prayerPauseMinutes: Int? {
        switch self {
        case .afterPrayer: return 15
        default:           return nil
        }
    }

    // Absolute publish date if scheduled
    func scheduledDate(from now: Date = Date()) -> Date? {
        var cal = Calendar.current
        switch self {
        case .tonight:
            return cal.nextDate(after: now,
                                matching: DateComponents(hour: 20, minute: 0),
                                matchingPolicy: .nextTimePreservingSmallerComponents)
        case .tomorrowMorning:
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
            return cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
        case .afterPrayer:
            return cal.date(byAdding: .minute, value: 15, to: now)
        default:
            return nil
        }
    }
}

// MARK: - PostPublishTimingContext
// Signals that trigger the "Post After Prayer?" prompt.
// The tone checker or create-post logic evaluates these and calls PostAfterPrayerSheet.

enum PostContentSignal {
    case reactive           // short, reactive-sounding, emotional charge
    case emotionallyHeavy   // grief, loss, trauma language
    case corrective         // directed correction or rebuking tone
    case vulnerable         // deeply personal disclosure
    case spirituallyImportant // testimony, answered prayer, conviction
    case conflictAdjacent   // argues with or names another person

    var message: String {
        switch self {
        case .reactive:
            return "This post reads as a quick reaction. A short pause often helps."
        case .emotionallyHeavy:
            return "This is a heavy post. You may want to sit with it before sharing."
        case .corrective:
            return "This post has a corrective tone. Prayer before posting often softens the delivery."
        case .vulnerable:
            return "You're sharing something personal. There's no rush."
        case .spirituallyImportant:
            return "This feels like a significant moment. Consider marking it carefully."
        case .conflictAdjacent:
            return "This post involves another person. A pause and prayer are wisdom."
        }
    }
}

// MARK: - PostAfterPrayerSheet
// Shown when the tone checker or post analysis detects reactive/heavy content.
// Not a block — an offer. Calm, no shame.

struct PostAfterPrayerSheet: View {

    let signal: PostContentSignal
    var onSelectTiming: (PostPublishTiming) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTiming: PostPublishTiming = .now

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            header
            timingList
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            confirmButton
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
        .background(Color(.systemBackground))
        .onAppear {
            Analytics.logEvent("post_after_prayer_shown", parameters: [
                "signal": "\(signal)"
            ])
        }
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When would you like to post this?")
                .font(AMENFont.semiBold(20))

            Text(signal.message)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var timingList: some View {
        VStack(spacing: 10) {
            ForEach(PostPublishTiming.allCases) { timing in
                PostTimingRow(
                    timing: timing,
                    isSelected: selectedTiming == timing
                ) {
                    withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82))) {
                        selectedTiming = timing
                    }
                }
            }
        }
    }

    private var confirmButton: some View {
        Button {
            Analytics.logEvent("post_timing_selected", parameters: [
                "timing": selectedTiming.rawValue
            ])
            onSelectTiming(selectedTiming)
            dismiss()
        } label: {
            Text(selectedTiming == .now ? "Post Now" : "Continue")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timing Row

private struct PostTimingRow: View {
    let timing: PostPublishTiming
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: timing.icon)
                    .font(.systemScaled(18, weight: .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timing.displayText)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(timing.description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.primary : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PostContentAnalyzer
// Lightweight heuristic. Called before publishing to decide whether to surface timing prompt.

enum PostContentAnalyzer {

    static func analyze(content: String) -> PostContentSignal? {
        let lower = content.lowercased()
        let wordCount = content.split(separator: " ").count

        if conflictSignals.contains(where: { lower.contains($0) }) { return .conflictAdjacent }
        if correctiveSignals.contains(where: { lower.contains($0) }) { return .corrective }
        if heavySignals.contains(where: { lower.contains($0) }) { return .emotionallyHeavy }
        if vulnerableSignals.contains(where: { lower.contains($0) }) { return .vulnerable }
        if spiritualSignals.contains(where: { lower.contains($0) }) { return .spirituallyImportant }
        if wordCount < 20 && reactiveSignals.contains(where: { lower.contains($0) }) { return .reactive }

        return nil
    }

    private static let conflictSignals = [
        "you people", "they always", "why do you", "stop doing", "i'm calling out",
        "why does @", "you need to", "some of you"
    ]

    private static let correctiveSignals = [
        "stop saying", "this is wrong", "false teaching", "you're wrong", "needs to be corrected",
        "i rebuke", "false prophet", "heresy", "unbiblical"
    ]

    private static let heavySignals = [
        "lost my", "passed away", "died", "suicide", "depression", "abuse",
        "divorce", "grief", "mourning", "devastating", "i can't do this"
    ]

    private static let vulnerableSignals = [
        "i'm sharing this", "i never told anyone", "for the first time",
        "scared to post this", "being vulnerable", "my testimony is"
    ]

    private static let spiritualSignals = [
        "god spoke to me", "this is my testimony", "he answered my prayer",
        "breakthrough", "vision", "prophetic word", "i felt led", "god told me"
    ]

    private static let reactiveSignals = [
        "i can't believe", "seriously?", "unbelievable", "this is ridiculous",
        "why is this", "come on", "smh", "🤦", "🙄", "no way"
    ]
}

// MARK: - Preview

#Preview {
    PostAfterPrayerSheet(signal: .corrective) { _ in }
        .presentationDetents([.large])
}
