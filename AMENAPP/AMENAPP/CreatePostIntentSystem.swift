import SwiftUI

// MARK: - PostComposerIntent
// Author's declared intent for a post. Shapes distribution toward matching readers.
// Stored on the post as `postIntent` raw value.

enum PostComposerIntent: String, CaseIterable, Codable, Identifiable {
    case encourage       = "encourage"
    case reflect         = "reflect"
    case prayerRequest   = "prayer_request"
    case shareTestimony  = "share_testimony"
    case teach           = "teach"
    case discuss         = "discuss"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .encourage:      return "Encourage"
        case .reflect:        return "Reflect"
        case .prayerRequest:  return "Ask for Prayer"
        case .shareTestimony: return "Share Testimony"
        case .teach:          return "Teach"
        case .discuss:        return "Discuss"
        }
    }

    var icon: String {
        switch self {
        case .encourage:      return "heart"
        case .reflect:        return "moon.stars"
        case .prayerRequest:  return "hands.sparkles"
        case .shareTestimony: return "star.bubble"
        case .teach:          return "book"
        case .discuss:        return "bubble.left.and.bubble.right"
        }
    }

    // Suggested category override when this intent implies one
    var suggestedCategory: Post.PostCategory? {
        switch self {
        case .prayerRequest:  return .prayer
        case .shareTestimony: return .testimonies
        default:              return nil
        }
    }

    // Ranking taxonomy tags written to the post on publish
    var rankingTags: [String] {
        switch self {
        case .encourage:      return ["encouragement", "hope"]
        case .reflect:        return ["reflection", "devotional"]
        case .prayerRequest:  return ["prayer_requests"]
        case .shareTestimony: return ["testimonies", "answered_prayers"]
        case .teach:          return ["bible_teaching", "practical_faith"]
        case .discuss:        return ["debate", "open_discussion"]
        }
    }
}

// MARK: - PostAudienceHint
// Author's optional signal for who this post is most relevant to.
// Helps distribution match the post to receptive readers faster.
// Stored on the post as `audienceHint` raw value.

enum PostAudienceHint: String, CaseIterable, Codable, Identifiable {
    case encouragementSeekers = "encouragement_seekers"
    case prayerCommunity      = "prayer_community"
    case localCommunity       = "local_community"
    case scriptureReaders     = "scripture_readers"
    case openDiscussion       = "open_discussion"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .encouragementSeekers: return "Encouragement seekers"
        case .prayerCommunity:      return "Prayer community"
        case .localCommunity:       return "Local community"
        case .scriptureReaders:     return "Scripture readers"
        case .openDiscussion:       return "Open discussion"
        }
    }

    var icon: String {
        switch self {
        case .encouragementSeekers: return "heart.fill"
        case .prayerCommunity:      return "hands.sparkles.fill"
        case .localCommunity:       return "mappin.circle.fill"
        case .scriptureReaders:     return "book.fill"
        case .openDiscussion:       return "bubble.left.and.bubble.right.fill"
        }
    }

    // NL taxonomy IDs to boost distribution toward these readers
    var distributionTags: [String] {
        switch self {
        case .encouragementSeekers: return ["encouragement", "hope"]
        case .prayerCommunity:      return ["prayer_requests", "testimonies"]
        case .localCommunity:       return ["local_churches", "community"]
        case .scriptureReaders:     return ["bible_teaching", "verse_reflection"]
        case .openDiscussion:       return ["debate", "open_discussion"]
        }
    }
}

// MARK: - ComposerSuggestionChips
// Quick-tag strip shown below the text area.
// Tapping auto-sets the post category without requiring the user to navigate menus.

struct ComposerSuggestionChips: View {
    @Binding var selectedCategory: Post.PostCategory
    var onAddScripture: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(icon: "star.bubble",     label: "Tag as Testimony") { selectedCategory = .testimonies }
                chip(icon: "hands.sparkles",  label: "Mark as Prayer")   { selectedCategory = .prayer }
                if let action = onAddScripture {
                    chip(icon: "book",        label: "Add Scripture")     { action() }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 40)
    }

    private func chip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(label)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ComposerIntentRow
// Horizontal intent selector shown in the compose toolbar.

struct ComposerIntentRow: View {
    @Binding var selectedIntent: PostComposerIntent?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PostComposerIntent.allCases) { intent in
                    IntentPill(
                        intent: intent,
                        isSelected: selectedIntent == intent
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82))) {
                            selectedIntent = selectedIntent == intent ? nil : intent
                        }
                        HapticManager.impact(style: .light)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 40)
    }
}

// MARK: - ComposerAudienceRow
// Optional audience targeting hint — shown after intent is selected.

struct ComposerAudienceRow: View {
    @Binding var selectedHint: PostAudienceHint?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PostAudienceHint.allCases) { hint in
                    AudiencePill(
                        hint: hint,
                        isSelected: selectedHint == hint
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82))) {
                            selectedHint = selectedHint == hint ? nil : hint
                        }
                        HapticManager.impact(style: .light)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 40)
    }
}

// MARK: - IntentPill

private struct IntentPill: View {
    let intent: PostComposerIntent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: intent.icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(intent.displayName)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(isSelected ? Color(.systemBackground) : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.primary : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(intent.displayName + (isSelected ? ", selected" : ""))
    }
}

// MARK: - AudiencePill

private struct AudiencePill: View {
    let hint: PostAudienceHint
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: hint.icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(hint.displayName)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(isSelected ? Color(.systemBackground) : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.primary : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hint.displayName + (isSelected ? ", selected" : ""))
    }
}

// MARK: - Preview

#Preview("Intent Row") {
    @Previewable @State var intent: PostComposerIntent? = .encourage
    @Previewable @State var hint: PostAudienceHint? = nil
    VStack(spacing: 12) {
        ComposerIntentRow(selectedIntent: $intent)
        ComposerAudienceRow(selectedHint: $hint)
    }
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
}
