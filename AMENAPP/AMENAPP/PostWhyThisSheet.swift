import SwiftUI
import FirebaseAnalytics

// MARK: - PostWhyThisSheet
// Explains why a post appeared in the feed and offers four quick adjustment actions.

struct PostWhyThisSheet: View {

    let post: Post
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var nlService = HeyFeedNLPreferencesService.shared
    @State private var appliedAction: PostFeedAction?
    @State private var isApplying = false

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    reasonsSection
                    actionsSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            Analytics.logEvent("post_why_this_opened", parameters: [
                "post_category": post.category.rawValue
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Why you're seeing this")
                .font(AMENFont.semiBold(20))
            Text("HeyFeed surfaces this based on your preferences and how this post aligns with your goals.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(computedReasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .padding(.top, 1)
                    Text(reason)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adjust your feed")
                .font(AMENFont.semiBold(15))

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(PostFeedAction.allCases) { action in
                    PostFeedActionButton(
                        action: action,
                        isApplied: appliedAction == action,
                        isDisabled: isApplying && appliedAction != action
                    ) {
                        apply(action)
                    }
                }
            }
        }
    }

    // MARK: - Reason computation

    private var computedReasons: [String] {
        var reasons: [String] = []

        switch post.category {
        case .prayer:
            reasons.append("This is a prayer request — you interact with prayer content regularly.")
        case .testimonies:
            reasons.append("This is a testimony — you have engagement history with testimonies.")
        case .tip:
            reasons.append("This contains practical faith advice.")
        case .funFact:
            reasons.append("This is a lighter content type for variety.")
        case .openTable:
            break
        }

        if let label = post.feedContext {
            reasons.append(label.reason)
        }

        let lower = post.content.lowercased()
        for pref in nlService.activePreferences.prefix(3) where pref.action == .increase {
            let id = pref.targetId
            if (id == "testimonies" && post.category == .testimonies) ||
               (id == "prayer_requests" && post.category == .prayer) ||
               (id == "bible_teaching" && (lower.contains("scripture") || post.verseReference != nil)) ||
               (id == "encouragement" && (lower.contains("hope") || lower.contains("encourage"))) ||
               (id == "community" && post.taggedChurchId != nil) {
                reasons.append("You asked HeyFeed for more \(pref.targetLabel.lowercased()).")
            }
        }

        if post.verseReference != nil {
            reasons.append("This post includes Scripture — a content type you engage with often.")
        }

        if post.churchNoteId != nil {
            reasons.append("This includes a church note — a content type saved for deep reflection.")
        }

        if reasons.isEmpty {
            reasons.append("This appeared to maintain a healthy variety in your feed.")
        }

        return Array(reasons.prefix(4))
    }

    // MARK: - Apply action

    private func apply(_ action: PostFeedAction) {
        guard !isApplying else { return }
        HapticManager.impact(style: .light)
        isApplying = true
        appliedAction = action

        Task {
            let intent = action.intent(for: post)
            try? await HeyFeedNLPreferencesService.shared.applyIntent(intent, source: "why_this_action")
            Analytics.logEvent("post_feed_action_applied", parameters: [
                "action": action.rawValue,
                "post_category": post.category.rawValue
            ])
            isApplying = false
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        }
    }
}

// MARK: - PostFeedAction

enum PostFeedAction: String, CaseIterable, Identifiable {
    case moreLikeThis  = "more_like_this"
    case lessLikeThis  = "less_like_this"
    case muteSeven     = "mute_7_days"
    case tuneForGrowth = "tune_for_growth"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moreLikeThis:  return "More like this"
        case .lessLikeThis:  return "Less like this"
        case .muteSeven:     return "Mute for 7 days"
        case .tuneForGrowth: return "Tune toward growth"
        }
    }

    var subtitle: String {
        switch self {
        case .moreLikeThis:  return "Boost this topic in future recommendations"
        case .lessLikeThis:  return "Lower similar posts without hiding everything"
        case .muteSeven:     return "Good for temporary focus or emotional limits"
        case .tuneForGrowth: return "Prioritize grounded, spiritually healthy content"
        }
    }

    var icon: String {
        switch self {
        case .moreLikeThis:  return "arrow.up.circle"
        case .lessLikeThis:  return "arrow.down.circle"
        case .muteSeven:     return "speaker.slash"
        case .tuneForGrowth: return "leaf"
        }
    }

    func intent(for post: Post) -> HeyFeedParsedIntent {
        let targetId: String
        let targetLabel: String
        switch post.category {
        case .prayer:
            targetId = "prayer_requests"; targetLabel = "Prayer"
        case .testimonies:
            targetId = "testimonies"; targetLabel = "Testimonies"
        default:
            targetId = post.primaryTopicKey ?? "community"; targetLabel = "Similar posts"
        }

        switch self {
        case .moreLikeThis:
            return makeIntent(action: .increase, targetId: targetId, label: targetLabel, duration: .sevenDays)
        case .lessLikeThis:
            return makeIntent(action: .decrease, targetId: targetId, label: targetLabel, duration: .sevenDays)
        case .muteSeven:
            return makeIntent(action: .mute, targetId: targetId, label: targetLabel, duration: .sevenDays)
        case .tuneForGrowth:
            return HeyFeedParsedIntent(
                action: .increase,
                targets: [
                    HeyFeedNLTarget(id: "bible_teaching",  type: .topic, label: "Scripture",      confidence: 0.8),
                    HeyFeedNLTarget(id: "encouragement",   type: .topic, label: "Encouragement",  confidence: 0.8),
                ],
                duration: .sevenDays,
                strength: 0.7,
                confidence: 0.9,
                originalText: "Tune toward growth",
                requiresConfirmation: false,
                parserVersion: 1
            )
        }
    }

    private func makeIntent(
        action: HeyFeedNLAction,
        targetId: String,
        label: String,
        duration: HeyFeedDuration
    ) -> HeyFeedParsedIntent {
        HeyFeedParsedIntent(
            action: action,
            targets: [HeyFeedNLTarget(id: targetId, type: .topic, label: label, confidence: 0.9)],
            duration: duration,
            strength: 0.7,
            confidence: 0.9,
            originalText: "\(title) for \(label)",
            requiresConfirmation: false,
            parserVersion: 1
        )
    }
}

// MARK: - Action Button

private struct PostFeedActionButton: View {
    let action: PostFeedAction
    let isApplied: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: isApplied ? "checkmark.circle.fill" : action.icon)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(isApplied ? .green : .primary)
                    Spacer()
                }
                Text(action.title)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(isApplied ? .green : .primary)
                Text(action.subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isApplied ? Color.green.opacity(0.08) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isApplied ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .animation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82)), value: isApplied)
    }
}

// MARK: - Preview

#Preview {
    PostWhyThisSheet(post: Post(
        authorName: "Grace Church",
        authorInitials: "GC",
        timeAgo: "2h",
        content: "God is still in the business of turning mourning into dancing. Your testimony is coming.",
        category: .testimonies,
        topicTag: nil,
        lightbulbCount: 0,
        commentCount: 0,
        repostCount: 0
    ))
    .presentationDetents([.medium, .large])
}
