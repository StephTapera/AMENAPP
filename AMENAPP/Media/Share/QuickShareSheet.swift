import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - QuickShareSheet
// Glass share sheet for forwarding media to followers.
// Loads up to 8 recent contacts from /users/{uid}/following.
// Multi-select recipients with glass ring indicator; message field optional.

struct QuickShareSheet: View {
    @Binding var isPresented: Bool
    var mediaId: String
    var onShared: ([String], String) -> Void

    @State private var friends: [ShareContact] = []
    @State private var selectedIds: Set<String> = []
    @State private var message: String = ""
    @State private var isLoading = true
    @State private var isSending = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let selectionHaptic = UIImpactFeedbackGenerator(style: .light)
    private let sendHaptic = UINotificationFeedbackGenerator()

    var body: some View {
        Color.clear
            .glassSheet(isPresented: $isPresented, detent: .medium) {
                sheetBody
            }
    }

    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerRow
            if isLoading {
                loadingRow
            } else {
                friendsScrollRow
            }
            messageField
            sendButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .onAppear { loadFriends() }
    }

    // MARK: - Header
    private var headerRow: some View {
        Text("Share to")
            .font(.title3.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Loading skeleton
    private var loadingRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                VStack(spacing: 6) {
                    AmenGlassLoadingSkeleton(cornerRadius: 28, height: 56)
                        .frame(width: 56)
                    AmenGlassLoadingSkeleton(cornerRadius: 4, height: 10)
                        .frame(width: 44)
                }
            }
        }
        .frame(height: 80)
    }

    // MARK: - Friends row
    private var friendsScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(friends) { contact in
                    friendAvatar(contact)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 88)
    }

    private func friendAvatar(_ contact: ShareContact) -> some View {
        let selected = selectedIds.contains(contact.id)
        return Button {
            toggleSelection(contact.id)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    AsyncImage(url: URL(string: contact.avatarURL ?? "")) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Circle()
                                .fill(reduceTransparency
                                    ? AnyShapeStyle(Color(.systemFill))
                                    : AnyShapeStyle(LiquidGlassTokens.blurRegular))
                                .overlay {
                                    Text(contact.initials)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                                }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                    if selected {
                        Circle()
                            .strokeBorder(Color.amenPurple, lineWidth: 3)
                            .frame(width: 56, height: 56)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color.amenPurple)
                                    .background(Circle().fill(Color(.systemBackground)).frame(width: 20, height: 20))
                                    .offset(x: 3, y: 3)
                            }
                    }
                }

                Text(contact.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(selected && !reduceMotion ? 1.04 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(response: LiquidGlassTokens.motionFast, dampingFraction: 0.7),
            value: selected
        )
        .accessibilityLabel("\(contact.displayName)\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Message field
    private var messageField: some View {
        TextField("Add a message...", text: $message, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .lineLimit(1...4)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(reduceTransparency
                        ? AnyShapeStyle(Color(.systemFill))
                        : AnyShapeStyle(LiquidGlassTokens.blurThin))
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.7)
                    }
            }
            .accessibilityLabel("Message")
            .accessibilityHint("Optional message to send with media")
    }

    // MARK: - Send button
    private var sendButton: some View {
        let enabled = !selectedIds.isEmpty && !isSending
        return Button {
            guard enabled else { return }
            sendHaptic.notificationOccurred(.success)
            isSending = true
            onShared(Array(selectedIds), message)
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSending ? "Sending…" : "Send")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(enabled ? Color.amenGold : Color.secondary.opacity(0.4))
            }
            .shadow(
                color: enabled ? Color.amenGold.opacity(0.35) : .clear,
                radius: 10, y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(
            reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast),
            value: enabled
        )
        .accessibilityLabel("Send")
        .accessibilityHint(selectedIds.isEmpty ? "Select at least one recipient to send" : "Send media to selected recipients")
    }

    // MARK: - Helpers
    private func toggleSelection(_ id: String) {
        selectionHaptic.impactOccurred()
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func loadFriends() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        Firestore.firestore()
            .collection("users").document(uid).collection("following")
            .order(by: "lastInteractionAt", descending: true)
            .limit(to: 8)
            .getDocuments { [self] snapshot, _ in
                guard let docs = snapshot?.documents else {
                    isLoading = false
                    return
                }
                friends = docs.compactMap { ShareContact(doc: $0) }
                isLoading = false
            }
    }
}

// MARK: - ShareContact model
struct ShareContact: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: String?

    var initials: String {
        let parts = displayName.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return chars.joined().uppercased()
    }

    init?(doc: QueryDocumentSnapshot) {
        id = doc.documentID
        guard let name = doc.data()["displayName"] as? String else { return nil }
        displayName = name
        avatarURL = doc.data()["avatarURL"] as? String
    }
}

