import SwiftUI
import FirebaseFirestore

/// Subtle banner shown on prayer posts when linkedTestimonyId is set.
/// Tapping navigates to the testimony.
struct PrayerAnsweredBannerView: View {
    let post: Post
    var onTap: (Post) -> Void = { _ in }

    @State private var testimonyPost: Post?
    @State private var isFetching = false

    private let charcoal = Color(red: 0.110, green: 0.110, blue: 0.102)
    private let bgColor   = Color(red: 0.957, green: 0.957, blue: 0.949) // #f4f4f2

    var body: some View {
        Button {
            if let tp = testimonyPost { onTap(tp) }
        } label: {
            HStack(spacing: 0) {
                Rectangle().fill(charcoal).frame(width: 3)

                HStack {
                    Text("This prayer was answered — read the testimony")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(testimonyPost == nil)
        .task { await fetchTestimony() }
    }

    private func fetchTestimony() async {
        guard !isFetching, let tid = post.linkedTestimonyId else { return }
        isFetching = true
        let snap = try? await Firestore.firestore().collection("posts").document(tid).getDocument()
        if let snap, snap.exists, let fp = try? snap.data(as: FirestorePost.self) {
            testimonyPost = fp.toPost()
        }
        isFetching = false
    }
}
