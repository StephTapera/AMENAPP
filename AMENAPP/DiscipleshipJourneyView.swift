//
//  DiscipleshipJourneyView.swift
//  AMENAPP
//
//  Shows the user's recent discipleship activity and open follow-up prompts.
//  Private to the user. Gated behind `guidedDiscipleshipEnabled`.
//
//  Design constraints:
//    - No streaks, points, or public leaderboards — formation is between
//      the user and God, not a social performance metric
//    - Follow-up prompts are invitations, never obligations
//    - Leader connections are explicitly opt-in
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DiscipleshipJourneyView: View {
    @StateObject private var viewModel = DiscipleshipJourneyViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if !AMENFeatureFlags.shared.guidedDiscipleshipEnabled {
                    featureUnavailableView
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    journeyContent
                }
            }
            .navigationTitle("Your Journey")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Feature Unavailable

    private var featureUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.systemScaled(40))
                .foregroundStyle(.secondary)

            Text("Journey Coming Soon")
                .font(AMENFont.bold(18))

            Text("Guided discipleship tracking is being rolled out. Check back soon.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Journey Content

    private var journeyContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {

                // Open follow-up prompts
                if !viewModel.followUpPrompts.isEmpty {
                    followUpSection
                }

                // Recent events
                if !viewModel.recentEvents.isEmpty {
                    recentEventsSection
                }

                // Focus areas
                if !viewModel.focusAreas.isEmpty {
                    focusAreasSection
                }

                // Empty state
                if viewModel.followUpPrompts.isEmpty && viewModel.recentEvents.isEmpty {
                    emptyState
                }
            }
            .padding(16)
        }
    }

    // MARK: - Follow-Up Prompts

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Follow-Up Invitations")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)

            ForEach(viewModel.followUpPrompts) { prompt in
                FollowUpPromptRow(prompt: prompt) {
                    Task { await viewModel.dismissPrompt(prompt) }
                }
            }
        }
    }

    // MARK: - Recent Events

    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Study")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)

            ForEach(viewModel.recentEvents) { event in
                DiscipleshipEventRow(event: event)
            }
        }
    }

    // MARK: - Focus Areas

    private var focusAreasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Focus Areas")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)

            Text("Areas you've expressed interest in growing:")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.focusAreas, id: \.rawValue) { area in
                        Text(area.displayName)
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.and.wrench")
                .font(.systemScaled(36))
                .foregroundStyle(.secondary)

            Text("Your Journey Begins Here")
                .font(AMENFont.semiBold(16))

            Text("As you study Scripture with Berean, your journey will take shape here — privately, between you and God.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Follow-Up Prompt Row

private struct FollowUpPromptRow: View {
    let prompt: FollowUpPrompt
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.systemScaled(20))
                .foregroundStyle(Color(red: 0.18, green: 0.44, blue: 0.80))

            VStack(alignment: .leading, spacing: 4) {
                if let ref = prompt.passageReference {
                    Text(ref)
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(Color(red: 0.18, green: 0.44, blue: 0.80))
                }
                Text(prompt.promptText)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Event Row

private struct DiscipleshipEventRow: View {
    let event: DiscipleshipEvent

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 0.22, green: 0.62, blue: 0.28).opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: event.eventType.icon)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 0.28))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(event.eventType.displayName)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)

                if let ref = event.passageReference {
                    Text(ref)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(event.occurredAt, style: .relative)
                .font(AMENFont.regular(11))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - DiscipleshipEventType display extensions

extension DiscipleshipEventType {
    var icon: String {
        switch self {
        case .studySessionCompleted:   return "book.fill"
        case .reflectionSubmitted:     return "heart.fill"
        case .practiceCompleted:       return "checkmark.circle.fill"
        case .leaderConnected:         return "person.2.fill"
        case .leaderReferralAccepted:  return "arrow.right.circle.fill"
        case .growthPathStarted:       return "map.fill"
        case .growthPathCompleted:     return "flag.fill"
        case .crisisEscalated:         return "exclamationmark.shield.fill"
        case .prayerRecorded:          return "hands.sparkles.fill"
        case .scriptureMemorized:      return "brain.head.profile"
        }
    }

    var displayName: String {
        switch self {
        case .studySessionCompleted:   return "Study Session"
        case .reflectionSubmitted:     return "Reflection Written"
        case .practiceCompleted:       return "Practice Completed"
        case .leaderConnected:         return "Leader Connected"
        case .leaderReferralAccepted:  return "Referral Accepted"
        case .growthPathStarted:       return "Growth Path Started"
        case .growthPathCompleted:     return "Growth Path Completed"
        case .crisisEscalated:         return "Support Sought"
        case .prayerRecorded:          return "Prayer Recorded"
        case .scriptureMemorized:      return "Verse Memorized"
        }
    }
}

// MARK: - ViewModel

@MainActor
private final class DiscipleshipJourneyViewModel: ObservableObject {
    @Published var recentEvents: [DiscipleshipEvent] = []
    @Published var followUpPrompts: [FollowUpPrompt] = []
    @Published var focusAreas: [DiscipleshipFocusArea] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()

    func load() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard AMENFeatureFlags.shared.guidedDiscipleshipEnabled else { return }

        isLoading = true
        defer { isLoading = false }

        async let eventsTask = loadRecentEvents(userId: userId)
        async let promptsTask = loadFollowUpPrompts(userId: userId)
        async let profileTask = loadFocusAreas(userId: userId)

        let (events, prompts, areas) = await (eventsTask, promptsTask, profileTask)
        recentEvents = events
        followUpPrompts = prompts
        focusAreas = areas
    }

    func dismissPrompt(_ prompt: FollowUpPrompt) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        try? await db
            .collection("users").document(userId)
            .collection("followUpPrompts").document(prompt.id)
            .updateData(["status": "dismissed", "dismissedAt": Timestamp(date: Date())])

        followUpPrompts.removeAll { $0.id == prompt.id }
    }

    private func loadRecentEvents(userId: String) async -> [DiscipleshipEvent] {
        do {
            let snap = try await db
                .collection("users").document(userId)
                .collection("discipleshipEvents")
                .order(by: "occurredAt", descending: true)
                .limit(to: 10)
                .getDocuments()

            return snap.documents.compactMap { doc -> DiscipleshipEvent? in
                let data = doc.data()
                guard let eventTypeRaw = data["eventType"] as? String,
                      let eventType = DiscipleshipEventType(rawValue: eventTypeRaw),
                      let ts = data["occurredAt"] as? Timestamp else { return nil }
                return DiscipleshipEvent(
                    id: doc.documentID,
                    userId: userId,
                    eventType: eventType,
                    passageId: data["passageId"] as? String,
                    passageReference: data["passageReference"] as? String,
                    bereanSessionId: data["bereanSessionId"] as? String,
                    note: data["note"] as? String,
                    occurredAt: ts.dateValue()
                )
            }
        } catch {
            return []
        }
    }

    private func loadFollowUpPrompts(userId: String) async -> [FollowUpPrompt] {
        do {
            let snap = try await db
                .collection("users").document(userId)
                .collection("followUpPrompts")
                .whereField("status", isEqualTo: "pending")
                .order(by: "createdAt", descending: true)
                .limit(to: 5)
                .getDocuments()

            return snap.documents.compactMap { doc -> FollowUpPrompt? in
                let data = doc.data()
                guard let promptText = data["promptText"] as? String,
                      let ts = data["createdAt"] as? Timestamp else { return nil }
                return FollowUpPrompt(
                    id: doc.documentID,
                    userId: userId,
                    promptText: promptText,
                    sourceSessionId: data["sourceSessionId"] as? String,
                    passageReference: data["passageReference"] as? String,
                    scheduledFor: (data["scheduledFor"] as? Timestamp)?.dateValue(),
                    status: .pending,
                    createdAt: ts.dateValue(),
                    dismissedAt: nil,
                    engagedAt: nil
                )
            }
        } catch {
            return []
        }
    }

    private func loadFocusAreas(userId: String) async -> [DiscipleshipFocusArea] {
        do {
            let doc = try await db
                .collection("users").document(userId)
                .collection("discipleshipProfile").document(userId)
                .getDocument()
            let rawAreas = doc.data()?["focusAreas"] as? [String] ?? []
            return rawAreas.compactMap { DiscipleshipFocusArea(rawValue: $0) }
        } catch {
            return []
        }
    }
}
