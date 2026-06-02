import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct AmenCovenantPostRouteDetailView: View {
    let covenantId: String
    let postId: String

    @State private var title = "Community Post"
    @State private var postBody = ""
    @State private var author = ""
    @State private var authorId = ""
    @State private var postType = "post"
    @State private var isAnonymous = false
    @State private var isPaidContent = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    @StateObject private var contentLauncher = ContentDiscussionLauncher()

    private let db = Firestore.firestore()

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }
    private var isOwnPost: Bool { !authorId.isEmpty && authorId == currentUid }

    private var audience: ContentAudience {
        isPaidContent ? .paidMembers : .spaceMembers
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Post Unavailable",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(errorMessage)
                    )
                    .padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title2.bold())
                        Label(
                            isAnonymous ? "Anonymous" : (author.isEmpty ? "Community" : author),
                            systemImage: isAnonymous ? "person.fill.questionmark" : "person.crop.circle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Text(postBody.isEmpty ? "This post has no body text." : postBody)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))

                    if AMENFeatureFlags.shared.contentOSEnabled {
                        discussButton
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AMENFeatureFlags.shared.contentOSEnabled && !isLoading && errorMessage == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentDiscussion()
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.purple)
                    }
                    .accessibilityLabel("Discuss or share this post")
                }
            }
        }
        .task { await loadPost() }
        .contentDiscussionSheet(launcher: contentLauncher)
    }

    // MARK: - Discuss Button (inline, shown in post body area)

    private var discussButton: some View {
        Button {
            presentDiscussion()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.purple)
                Text("Discuss or Share")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.purple)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.15), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discuss or share this post")
    }

    // MARK: - Present

    private func presentDiscussion() {
        let card = ContentCard.from(
            id:                   postId,
            title:                title,
            body:                 postBody,
            sourceType:           contentSourceType,
            sourceSurface:        .space,
            creatorId:            authorId,
            creatorDisplayName:   author.isEmpty ? nil : author,
            audience:             audience,
            isAnonymous:          isAnonymous,
            hasPrayerContent:     postType == "prayer_request",
            isPaidContent:        isPaidContent,
            isDM:                 false,
            isChurchInternal:     false
        )
        contentLauncher.present(
            card:                 card,
            requestorIsCreator:   isOwnPost
        )
    }

    private var contentSourceType: ContentSourceType {
        switch postType {
        case "prayer_request": return .prayerRequest
        case "testimony":      return .testimony
        case "question":       return .question
        case "announcement":   return .post
        default:               return .post
        }
    }

    // MARK: - Load

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

            title        = data["title"] as? String ?? "Community Post"
            postBody     = data["body"] as? String ?? ""
            author       = data["authorDisplayName"] as? String
                            ?? data["authorName"] as? String
                            ?? ""
            authorId     = data["authorId"] as? String ?? data["createdBy"] as? String ?? ""
            postType     = data["type"] as? String
                            ?? data["messageType"] as? String
                            ?? "post"
            isAnonymous  = data["isAnonymous"] as? Bool ?? false
            isPaidContent = (data["visibility"] as? String) == "paid_members_only"
        } catch {
            errorMessage = "We could not load this post. Please try again."
        }
    }
}
