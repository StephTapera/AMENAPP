import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct QuickShareFriend: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: URL?
}

struct QuickShareSheet: View {
    @Binding var isPresented: Bool
    var mediaId: String
    var onShared: ([String], String) -> Void

    @State private var friends: [QuickShareFriend] = []
    @State private var selectedIds: Set<String> = []
    @State private var message = ""
    @State private var showSystemShare = false
    @FocusState private var messageFocused: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shareURL: URL {
        URL(string: "https://amen.app/media/\(mediaId)") ?? URL(string: "https://amen.app")!
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                friendsRow
                    .padding(.vertical, 16)

                Divider()

                actionsRow
                    .padding(.vertical, 16)

                Divider()

                messageField
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                Spacer()
            }
            .navigationTitle("Share to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onShared(Array(selectedIds), message)
                        isPresented = false
                    }
                    .disabled(selectedIds.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.65)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.ultraThinMaterial)
        .task { await loadFriends() }
        .background {
            if showSystemShare {
                SystemSharePresenter(items: [shareURL], isPresented: $showSystemShare)
                    .frame(width: 0, height: 0)
            }
        }
    }

    private var friendsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(friends) { friend in
                    friendCell(friend)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func friendCell(_ friend: QuickShareFriend) -> some View {
        let isSelected = selectedIds.contains(friend.id)
        return VStack(spacing: 6) {
            ZStack {
                AsyncImage(url: friend.avatarURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                if isSelected {
                    Circle()
                        .strokeBorder(Color.purple, lineWidth: 2.5)
                        .frame(width: 56, height: 56)
                }
            }
            Text(friend.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 56)
        }
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected { selectedIds.remove(friend.id) } else { selectedIds.insert(friend.id) }
        }
        .accessibilityLabel("\(friend.displayName), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var actionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                actionButton(icon: "link", label: "Copy Link") {
                    UIPasteboard.general.string = shareURL.absoluteString
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                actionButton(icon: "square.and.arrow.up", label: "Share") {
                    showSystemShare = true
                }
                actionButton(icon: "message.fill", label: "iMessage") {
                    let smsURL = URL(string: "sms:&body=\(shareURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
                    if let url = smsURL, UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
                actionButton(icon: "paperplane.fill", label: "Send") {
                    guard !selectedIds.isEmpty else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onShared(Array(selectedIds), message)
                    isPresented = false
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay { Circle().fill(Color.white.opacity(0.12)) }
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5) }
                        .overlay { Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6) }
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var messageField: some View {
        TextField("Add a message...", text: $message)
            .textFieldStyle(.plain)
            .font(.body)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(LiquidGlassTokens.blurThin))
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6)
                    }
            }
            .focused($messageFocused)
    }

    @MainActor
    private func loadFriends() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let profiles = (try? await FollowService.shared.fetchFollowing(userId: uid)) ?? []
        if profiles.isEmpty {
            // Fallback: show people the current user follows by ID set
            friends = FollowService.shared.following.prefix(20).map { uid in
                QuickShareFriend(id: uid, displayName: uid, avatarURL: nil)
            }
        } else {
            friends = profiles.prefix(20).map { profile in
                QuickShareFriend(
                    id: profile.id,
                    displayName: profile.displayName,
                    avatarURL: profile.profileImageURL.flatMap(URL.init)
                )
            }
        }
    }
}

// MARK: - System Share Sheet Presenter

private struct SystemSharePresenter: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiVC: UIViewController, context: Context) {
        guard isPresented, uiVC.presentedViewController == nil else { return }
        let shareVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        shareVC.completionWithItemsHandler = { _, _, _, _ in
            isPresented = false
        }
        uiVC.present(shareVC, animated: true)
    }
}
