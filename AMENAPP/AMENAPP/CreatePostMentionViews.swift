import SwiftUI
import FirebaseFirestore

struct AlgoliaMentionSuggestionRow: View {
    let user: AlgoliaUser
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var resolvedImageURL: String? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 40, height: 40)

                    let effectiveURL = resolvedImageURL ?? user.profileImageURL

                    if let urlStr = effectiveURL,
                       !urlStr.isEmpty,
                       let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(user.displayName.prefix(1).uppercased())
                                .font(AMENFont.bold(16))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Text(user.displayName.prefix(1).uppercased())
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.primary)
                    }
                }
                .task(id: user.objectID) {
                    guard (user.profileImageURL ?? "").isEmpty else { return }
                    if let url = await fetchProfileImageURL(userId: user.objectID) {
                        resolvedImageURL = url
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(alignment: .center) {
                            AlgoliaBrushstrokeHighlight()
                                .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.15, opacity: 0.75))
                        }

                    Text("@\(user.username)")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                isPressed
                    ? Color(uiColor: .tertiarySystemFill)
                    : Color.clear
            )
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        ._onButtonGesture { pressing in
            isPressed = pressing
        } perform: {}
    }

    private func fetchProfileImageURL(userId: String) async -> String? {
        guard !userId.isEmpty else { return nil }
        do {
            let doc = try await Firestore.firestore().collection("users").document(userId).getDocument()
            return doc.data()?["profileImageURL"] as? String
        } catch {
            return nil
        }
    }
}
