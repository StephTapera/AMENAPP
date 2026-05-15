import SwiftUI
import FirebaseFirestore

struct AmenCovenantPostRouteDetailView: View {
    let covenantId: String
    let postId: String

    @State private var title = "Community Post"
    @State private var body = ""
    @State private var author = "Community"
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let errorMessage {
                    ContentUnavailableView("Post Unavailable", systemImage: "doc.text.magnifyingglass", description: Text(errorMessage))
                        .padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title2.bold())
                        Label(author, systemImage: "person.crop.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(body.isEmpty ? "This post has no body text." : body)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(20)
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPost() }
    }

    private func loadPost() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let doc = try await db.collection("covenants")
                .document(covenantId)
                .collection("posts")
                .document(postId)
                .getDocument()

            guard let data = doc.data() else {
                errorMessage = "This post could not be found."
                return
            }

            title = data["title"] as? String ?? "Community Post"
            body = data["body"] as? String ?? ""
            author = data["authorDisplayName"] as? String ?? data["authorName"] as? String ?? "Community"
        } catch {
            errorMessage = "We could not load this post. Please try again."
        }
    }
}
