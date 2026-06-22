import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Sheet that opens when user taps "Write your testimony" on an answered prayer.
struct AnsweredPrayerComposerView: View {
    let originalPrayerPost: Post
    var onPosted: (String) -> Void = { _ in } // passes new testimony postId

    @Environment(\.dismiss) var dismiss
    @State private var testimonyText = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @FocusState private var isTextFocused: Bool

    private let charcoal = Color(red: 0.110, green: 0.110, blue: 0.102) // #1c1c1a
    private let amber    = Color(red: 0.784, green: 0.447, blue: 0.165) // #c8722a

    var body: some View {
        VStack(spacing: 0) {
            // Dark header
            VStack(spacing: 4) {
                Text("Your prayer was answered")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Share what God did")
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .background(charcoal)

            ScrollView {
                VStack(spacing: 16) {
                    // Origin box
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(charcoal)
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("YOU PRAYED FOR")
                                .font(.systemScaled(9, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .kerning(0.5)
                            Text(originalPrayerPost.content)
                                .font(.systemScaled(13).italic())
                                .foregroundStyle(Color.primary)
                                .lineLimit(4)
                        }
                        .padding(.leading, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Text editor
                    TextEditor(text: $testimonyText)
                        .font(.systemScaled(15).italic())
                        .frame(minHeight: 180)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                        )
                        .overlay(
                            Group {
                                if testimonyText.isEmpty {
                                    Text("God provided... (share what happened)")
                                        .font(.systemScaled(15).italic())
                                        .foregroundStyle(Color.secondary.opacity(0.6))
                                        .allowsHitTesting(false)
                                        .padding(.leading, 14)
                                        .padding(.top, 18)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                            }
                        )
                        .focused($isTextFocused)
                        .padding(.horizontal, 16)

                    if let err = errorMessage {
                        Text(err)
                            .font(.systemScaled(13))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }

                    // Post button
                    Button {
                        Task { await postTestimony() }
                    } label: {
                        Group {
                            if isPosting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Post testimony")
                                    .font(.systemScaled(16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(testimonyText.isEmpty ? amber.opacity(0.4) : amber)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(testimonyText.isEmpty || isPosting)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .background(Color(red: 0.949, green: 0.949, blue: 0.941)) // #f2f2f0
        }
        .onAppear { isTextFocused = true }
    }

    private func postTestimony() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        let prayerId = originalPrayerPost.firestoreId
        let newRef = Firestore.firestore().collection("posts").document()

        // Build testimony document
        let testimonyData: [String: Any] = [
            "category": "testimonies",
            "type": "testimony",
            "linkedPrayerRequestId": prayerId,
            "linkedPrayerText": originalPrayerPost.content,
            "authorId": uid,
            "authorName": Auth.auth().currentUser?.displayName ?? "",
            "content": testimonyText,
            "createdAt": Timestamp(date: Date()),
            "isAnsweredPrayer": true,
            "amenCount": 0,
            "commentCount": 0,
            "repostCount": 0,
            "visibility": "Everyone"
        ]

        do {
            try await newRef.setData(testimonyData)
            // Update prayer post
            try await Firestore.firestore().collection("posts").document(prayerId).updateData([
                "prayerStatus": "answered",
                "linkedTestimonyId": newRef.documentID
            ])
            // Notify via Cloud Function
            await PrayerAnsweredNotificationService.shared.notifyPrayerAnswered(
                prayerPostId: prayerId,
                testimonyPostId: newRef.documentID,
                authorId: uid
            )
            onPosted(newRef.documentID)
            dismiss()
        } catch {
            errorMessage = "Could not post. Try again."
        }
    }
}
