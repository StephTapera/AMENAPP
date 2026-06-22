import SwiftUI
import FirebaseFirestore

// MARK: - Minimal Reaction Button Style (Instagram/Threads Style)
/// Custom button style for minimal outline/filled reactions.
/// Press-down: immediate tight spring. Release: crisp snap back via Motion presets.
struct MinimalReactionButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(
                Motion.adaptive(
                    configuration.isPressed ? Motion.springPress : Motion.springRelease
                ),
                value: configuration.isPressed
            )
    }
}

// MARK: - Poll Display Component

struct PostPollView: View {
    let postId: String
    let poll: PostPoll
    let currentUserId: String?

    @State private var userVote: String? = nil
    @State private var isVoting = false
    @State private var localPoll: PostPoll

    init(postId: String, poll: PostPoll, currentUserId: String?) {
        self.postId = postId
        self.poll = poll
        self.currentUserId = currentUserId
        self._localPoll = State(initialValue: poll)
    }

    var isPollExpired: Bool {
        guard let expiresAt = poll.expiresAt else { return false }
        return Date() > expiresAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Poll question (if provided)
            if !poll.question.isEmpty {
                Text(poll.question)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
            }

            // Poll options
            VStack(spacing: 8) {
                ForEach(localPoll.options) { option in
                    pollOptionButton(option)
                }
            }

            // Poll footer (total votes + expiry)
            HStack(spacing: 12) {
                Text("\(localPoll.totalVotes) \(localPoll.totalVotes == 1 ? "vote" : "votes")")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)

                if let expiresAt = poll.expiresAt {
                    Text("•")
                        .foregroundStyle(.secondary)

                    if isPollExpired {
                        Text("Poll ended")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ends \(expiresAt, style: .relative)")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .onAppear {
            loadUserVote()
        }
    }

    @ViewBuilder
    private func pollOptionButton(_ option: PostPoll.PollOption) -> some View {
        let hasVoted = userVote != nil
        let isThisOption = userVote == option.id
        let percentage = localPoll.totalVotes > 0 ? Double(option.voteCount) / Double(localPoll.totalVotes) : 0.0

        Button {
            guard !hasVoted && !isPollExpired else { return }
            vote(for: option.id)
        } label: {
            HStack(spacing: 0) {
                // Background bar (shows percentage if voted)
                if hasVoted {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(isThisOption ? Color.blue.opacity(0.2) : Color(.tertiarySystemFill))
                            .frame(width: geometry.size.width * percentage)
                    }
                }

                HStack {
                    Text(option.text)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(isThisOption ? .blue : .primary)

                    Spacer()

                    if hasVoted {
                        Text("\(Int(percentage * 100))%")
                            .font(AMENFont.bold(14))
                            .foregroundStyle(isThisOption ? .blue : .secondary)

                        if isThisOption {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isThisOption ? Color.blue : Color(.separator),
                    lineWidth: isThisOption ? 2 : 1
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hasVoted ? Color.clear : Color(.tertiarySystemFill))
                )
        )
        .disabled(hasVoted || isPollExpired || isVoting)
    }

    private func loadUserVote() {
        guard let uid = currentUserId else { return }

        // Check if user already voted by querying Firestore poll data
        Task {
            do {
                let doc = try await Firestore.firestore()
                    .collection("posts")
                    .document(postId)
                    .getDocument()

                if let pollData = doc.data()?["poll"] as? [String: Any],
                   let voters = pollData["voters"] as? [String: String],
                   let votedOptionId = voters[uid] {
                    await MainActor.run {
                        userVote = votedOptionId
                    }
                }
            } catch {
                dlog("❌ Error loading user vote: \(error)")
            }
        }
    }

    private func vote(for optionId: String) {
        guard currentUserId != nil, !isVoting else { return }

        isVoting = true
        HapticManager.impact(style: .light)

        // Optimistic update
        userVote = optionId
        var updatedOptions = localPoll.options
        if let index = updatedOptions.firstIndex(where: { $0.id == optionId }) {
            updatedOptions[index].voteCount += 1
        }
        localPoll = PostPoll(
            question: localPoll.question,
            options: updatedOptions,
            expiresAt: localPoll.expiresAt,
            totalVotes: localPoll.totalVotes + 1
        )

        Task {
            do {
                try await PollService.shared.vote(postId: postId, optionId: optionId)
                await MainActor.run {
                    isVoting = false
                    HapticManager.notification(type: .success)
                }
            } catch {
                // Revert optimistic update on error
                await MainActor.run {
                    userVote = nil
                    localPoll = poll
                    isVoting = false
                    HapticManager.notification(type: .error)
                    dlog("❌ Error voting: \(error)")
                }
            }
        }
    }
}
