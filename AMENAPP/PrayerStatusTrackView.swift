import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// 3-stage prayer status track shown on prayer posts authored by current user.
/// Read-only for other users.
struct PrayerStatusTrackView: View {
    let post: Post
    var onAnswered: () -> Void = {}

    @State private var status: String
    @State private var isUpdating = false
    @State private var pulseScale: CGFloat = 1.0

    private let db = Firestore.firestore()
    private let stages = ["praying", "believing", "answered"]
    private let stageLabels = ["Praying", "Believing", "Answered"]
    private let charcoal = Color(red: 0.110, green: 0.110, blue: 0.102) // #1c1c1a

    private var isAuthor: Bool {
        Auth.auth().currentUser?.uid == post.authorId
    }

    init(post: Post, onAnswered: @escaping () -> Void = {}) {
        self.post = post
        self.onAnswered = onAnswered
        _status = State(initialValue: post.prayerStatus ?? "praying")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Track
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    // Stage node
                    stageNode(index: index, stage: stage)

                    // Connector (not after last)
                    if index < stages.count - 1 {
                        connectorLine(completed: stageIndex(status) > index)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )

            // Author-only: advance button (shown when not at answered stage)
            if isAuthor && status != "answered" {
                advanceButton
            }

            // Answered CTA
            if status == "answered" {
                answeredCTA
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.3
            }
        }
    }

    private func stageNode(index: Int, stage: String) -> some View {
        let completed = stageIndex(status) > index
        let active    = stageIndex(status) == index

        return VStack(spacing: 4) {
            ZStack {
                if completed {
                    Circle()
                        .fill(charcoal)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else if active {
                    Circle()
                        .strokeBorder(charcoal, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(charcoal)
                        .frame(width: 10, height: 10)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulseScale)
                } else {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 22, height: 22)
                }
            }
            Text(stageLabels[index])
                .font(.system(size: 10, weight: active || completed ? .semibold : .regular))
                .foregroundStyle(completed || active ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .onTapGesture {
            if isAuthor && !isUpdating { advanceToStage(index) }
        }
    }

    private func connectorLine(completed: Bool) -> some View {
        Rectangle()
            .fill(completed ? charcoal : Color(.separator))
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18) // align with circle centers
    }

    private var advanceButton: some View {
        let nextIndex = min(stageIndex(status) + 1, stages.count - 1)
        let nextLabel = stageLabels[nextIndex]
        return Button {
            advanceToStage(nextIndex)
        } label: {
            Text("Mark as \(nextLabel)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(charcoal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
    }

    private var answeredCTA: some View {
        Button(action: onAnswered) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(charcoal)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Write your testimony")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text("Share what God did")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.leading, 10)
                .padding(.vertical, 10)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .padding(.trailing, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func stageIndex(_ s: String) -> Int {
        stages.firstIndex(of: s) ?? 0
    }

    private func advanceToStage(_ index: Int) {
        guard index < stages.count else { return }
        let newStatus = stages[index]
        guard newStatus != status else { return }
        isUpdating = true
        status = newStatus
        Task {
            defer { isUpdating = false }
            try? await db.collection("posts").document(post.firestoreId)
                .updateData(["prayerStatus": newStatus])
            if newStatus == "answered" { onAnswered() }
        }
    }
}
