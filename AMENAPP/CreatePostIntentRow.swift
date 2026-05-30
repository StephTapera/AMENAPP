//
//  CreatePostIntentRow.swift
//  AMENAPP
//
//  Optional intent selector row inside CreatePostView.
//  Uses the existing PostIntent enum from PostIntentDetector.swift and adds
//  the display/distribution properties needed for the composer UI.
//

import SwiftUI

// MARK: - PostIntent display extensions

extension PostIntent {
    /// SF Symbol for display in the intent row.
    var composerIcon: String {
        switch self {
        case .reflection:    return "moon.stars"
        case .testimony:     return "star.bubble"
        case .prayerRequest: return "hands.sparkles"
        case .teaching:      return "book.closed"
        case .question:      return "bubble.left.and.bubble.right"
        case .gratitude:     return "heart"
        case .announcement:  return "megaphone"
        case .sermonClip:    return "waveform"
        case .eventRecap:    return "calendar"
        case .missionUpdate: return "globe"
        case .resource:      return "link"
        case .general:       return "text.bubble"
        }
    }

    /// Human-readable display name shown in the picker pill.
    var composerDisplayName: String {
        switch self {
        case .reflection:    return "Reflect"
        case .testimony:     return "Testimony"
        case .prayerRequest: return "Ask for Prayer"
        case .teaching:      return "Teach"
        case .question:      return "Start Discussion"
        case .gratitude:     return "Encourage"
        case .announcement:  return "Announce"
        case .sermonClip:    return "Sermon Clip"
        case .eventRecap:    return "Event Recap"
        case .missionUpdate: return "Mission Update"
        case .resource:      return "Resource"
        case .general:       return "Share"
        }
    }

    /// Maps to a HeyFeed NL taxonomy key for feed distribution and personalization learning.
    var feedTopicKey: String {
        switch self {
        case .reflection:    return "reflection"
        case .testimony:     return "testimonies"
        case .prayerRequest: return "prayer_requests"
        case .teaching:      return "bible_teaching"
        case .question:      return "community"
        case .gratitude:     return "encouragement"
        case .announcement:  return "announcement"
        case .sermonClip:    return "bible_teaching"
        case .eventRecap:    return "community"
        case .missionUpdate: return "community"
        case .resource:      return "bible_teaching"
        case .general:       return "community"
        }
    }

    /// Confirmation copy shown when intent is selected.
    var confirmationLabel: String {
        switch self {
        case .reflection:    return "Sharing a reflection"
        case .testimony:     return "Sharing your testimony"
        case .prayerRequest: return "Asking for prayer"
        case .teaching:      return "Sharing what you've learned"
        case .question:      return "Opening a discussion"
        case .gratitude:     return "Sending encouragement"
        case .announcement:  return "Sharing an announcement"
        case .sermonClip:    return "Sharing a sermon clip"
        case .eventRecap:    return "Sharing an event recap"
        case .missionUpdate: return "Sharing a mission update"
        case .resource:      return "Sharing a resource"
        case .general:       return "Sharing a thought"
        }
    }
}

// MARK: - Row View

struct CreatePostIntentRow: View {
    @Binding var selectedIntent: PostIntent?

    /// Primary intents shown in the compact picker row.
    private let primaryIntents: [PostIntent] = [
        .gratitude, .reflection, .prayerRequest, .testimony, .teaching, .question
    ]

    var body: some View {
        Group {
            if let intent = selectedIntent {
                selectedStateRow(intent)
            } else {
                pickerRow
            }
        }
        .animation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.78)), value: selectedIntent?.rawValue)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Picker

    private var pickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's this post for?")
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(primaryIntents, id: \.rawValue) { intent in
                        IntentPill(intent: intent) {
                            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.7))) {
                                selectedIntent = intent
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Selected State

    private func selectedStateRow(_ intent: PostIntent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: intent.composerIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            Text(intent.confirmationLabel)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.7))) {
                    selectedIntent = nil
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Circle().fill(Color(.systemGray5)))
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selected intent")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Removes the selected post intent")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Intent Pill

private struct IntentPill: View {
    let intent: PostIntent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: intent.composerIcon)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityHidden(true)
                Text(intent.composerDisplayName)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(intent.composerDisplayName)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Selects \(intent.composerDisplayName) as the intent for your post")
    }
}
