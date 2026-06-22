// JITConsentSheet.swift — AMEN IntegrationOS
// Just-in-time consent prompt sheet shown before a new scope is accessed.

import SwiftUI

struct JITConsentSheet: View {
    let scope: ConsentScope
    let providerId: String
    let onGrant: () async -> Void
    let onDeny: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isGranting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: scopeIcon)
                    .font(.systemScaled(48))
                    .foregroundStyle(.tint)
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    Text(scopeTitle)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(scopeDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                privacyNote

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task {
                            isGranting = true
                            await onGrant()
                            isGranting = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isGranting { ProgressView().tint(.white) }
                            Text("Allow \(scopeTitle)")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isGranting)

                    Button("Not Now", role: .cancel) {
                        onDeny()
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Permission Needed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onDeny()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
            Text("AMEN never sells your data. This permission is stored securely and can be revoked at any time in Settings > Connections.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
        )
        .padding(.horizontal)
    }

    private var scopeTitle: String {
        switch scope {
        case .calendarRead:         return "Read Calendar"
        case .calendarWrite:        return "Add to Calendar"
        case .locationApproximate:  return "Approximate Location"
        case .locationPrecise:      return "Precise Location"
        case .contactsHashedMatch:  return "Find Friends"
        case .healthWalkingSteps:   return "Steps & Activity"
        case .healthSleepData:      return "Sleep Data"
        case .healthWorkouts:       return "Workouts"
        case .mediaLibraryRead:     return "Music Library"
        case .musicPlayback:        return "Music Playback"
        case .messagingPush:        return "Notifications"
        case .messagingSMS:         return "SMS Messages"
        case .messagingEmail:       return "Email"
        case .webhookReceive:       return "Receive Webhooks"
        case .orgKnowledgeRead:     return "Organization Knowledge"
        case .orgKnowledgeWrite:    return "Update Knowledge Base"
        case .eventsRead:           return "View Events"
        case .eventsRSVP:           return "RSVP to Events"
        case .profileRead:          return "Read Profile"
        case .opportunityPost:      return "Post Opportunities"
        }
    }

    private var scopeDescription: String {
        switch scope {
        case .calendarRead:         return "AMEN will read your calendar to suggest the best times for church visits and events."
        case .calendarWrite:        return "AMEN will add church events and devotionals to your calendar."
        case .locationApproximate:  return "Used to find nearby churches and events in your area."
        case .locationPrecise:      return "Used for turn-by-turn directions to church."
        case .contactsHashedMatch:  return "Your contacts are hashed locally—AMEN never sees the raw list."
        case .healthWalkingSteps:   return "Track your wellness journey alongside your spiritual walk."
        case .healthSleepData:      return "Help AMEN suggest the best times for morning devotionals."
        case .healthWorkouts:       return "Connect physical and spiritual health milestones."
        case .mediaLibraryRead:     return "Access worship music in your library."
        case .musicPlayback:        return "Play worship music and sermons from AMEN."
        case .messagingPush:        return "Receive prayer reminders and event alerts."
        case .messagingSMS:         return "Send prayer requests and invites via SMS."
        case .messagingEmail:       return "Receive weekly spiritual insights and newsletters."
        case .webhookReceive:       return "Allow external services to send updates to AMEN."
        case .orgKnowledgeRead:     return "Access your church or ministry's knowledge base."
        case .orgKnowledgeWrite:    return "Add and update your organization's knowledge base."
        case .eventsRead:           return "Browse and discover church and ministry events."
        case .eventsRSVP:           return "RSVP to events and receive reminders."
        case .profileRead:          return "Allow AMEN to personalize your experience."
        case .opportunityPost:      return "Post ministry and career opportunities to the community."
        }
    }

    private var scopeIcon: String {
        switch scope {
        case .calendarRead, .calendarWrite:         return "calendar.badge.checkmark"
        case .locationApproximate, .locationPrecise: return "location.fill"
        case .contactsHashedMatch:                   return "person.2.fill"
        case .healthWalkingSteps, .healthSleepData, .healthWorkouts: return "heart.fill"
        case .mediaLibraryRead, .musicPlayback:     return "music.note"
        case .messagingPush:                         return "bell.fill"
        case .messagingSMS:                          return "message.fill"
        case .messagingEmail:                        return "envelope.fill"
        case .webhookReceive:                        return "arrow.down.circle.fill"
        case .orgKnowledgeRead, .orgKnowledgeWrite: return "building.2.fill"
        case .eventsRead, .eventsRSVP:               return "ticket.fill"
        case .profileRead:                           return "person.crop.circle"
        case .opportunityPost:                       return "briefcase.fill"
        }
    }
}
