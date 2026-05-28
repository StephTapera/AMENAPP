import SwiftUI
import FirebaseFirestore

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
    @FocusState private var messageFocused: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                friendsRow
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
        .presentationDetents([.fraction(0.55)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
        .task { await loadFriends() }
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
        // Stub: return placeholder friends until real Firestore query is wired
        friends = (1...8).map { i in
            QuickShareFriend(id: "user_\(i)", displayName: "Friend \(i)", avatarURL: nil)
        }
    }
}
