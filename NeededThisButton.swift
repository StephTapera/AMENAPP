import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Amber bookmark-heart toggle button shown on testimony post replies.
/// Saves/removes the testimony to the user's private "neededTestimonies" subcollection.
struct NeededThisButton: View {
    let postId: String

    @State private var isSaved = false
    @State private var isInFlight = false
    @State private var checked = false

    private let db = Firestore.firestore()

    var body: some View {
        Button {
            guard !isInFlight else { return }
            toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSaved ? "bookmark.heart.fill" : "bookmark.heart")
                    .font(.system(size: 13))
                    .foregroundStyle(isSaved ? Color.orange : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                if isSaved {
                    Text("Saved")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSaved)
        }
        .buttonStyle(.plain)
        .task { await checkSavedState() }
    }

    private func toggle() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isInFlight = true
        let ref = db.collection("users").document(uid)
            .collection("neededTestimonies").document(postId)
        let newState = !isSaved
        isSaved = newState
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            defer { isInFlight = false }
            if newState {
                try? await ref.setData(["postId": postId, "savedAt": Timestamp(date: Date())])
                // Increment neededCount on post for Cloud Function trigger
                try? await db.collection("posts").document(postId)
                    .updateData(["neededCount": FieldValue.increment(Int64(1))])
            } else {
                try? await ref.delete()
                try? await db.collection("posts").document(postId)
                    .updateData(["neededCount": FieldValue.increment(Int64(-1))])
            }
        }
    }

    private func checkSavedState() async {
        guard !checked, let uid = Auth.auth().currentUser?.uid else { return }
        checked = true
        let snap = try? await db.collection("users").document(uid)
            .collection("neededTestimonies").document(postId).getDocument()
        isSaved = snap?.exists ?? false
    }
}
