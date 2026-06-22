import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Rooms View Model

@MainActor
final class AmenCovenantRoomsViewModel: ObservableObject {
    @Published var rooms: [CovenantRoom] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let db = Firestore.firestore()

    func load(covenantId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db
                .collection("covenants")
                .document(covenantId)
                .collection("rooms")
                .order(by: "createdAt")
                .getDocuments()
            rooms = snap.documents.compactMap { try? $0.data(as: CovenantRoom.self) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Rooms View

struct AmenCovenantRoomsView: View {
    let covenantId: String
    @EnvironmentObject var vm: AmenCovenantViewModel

    @StateObject private var roomsVM = AmenCovenantRoomsViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paywallRoom: CovenantRoom?

    // MARK: - Derived sections

    private var unreadRooms: [CovenantRoom] {
        roomsVM.rooms.filter { $0.unreadCount > 0 }
    }

    private var accessibleRooms: [CovenantRoom] {
        roomsVM.rooms.filter {
            AmenCovenantPermissions.canViewRoom(room: $0, membership: vm.currentMembership)
        }
    }

    private var lockedRooms: [CovenantRoom] {
        roomsVM.rooms.filter {
            !AmenCovenantPermissions.canViewRoom(room: $0, membership: vm.currentMembership)
        }
    }

    var body: some View {
        Group {
            if roomsVM.isLoading {
                loadingState
            } else if roomsVM.rooms.isEmpty && roomsVM.error == nil {
                emptyState
            } else {
                roomListContent
            }
        }
        .navigationTitle("Rooms")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await roomsVM.load(covenantId: covenantId)
            await vm.loadMembership(for: covenantId)
        }
        .sheet(item: $paywallRoom) { room in
            LockedRoomPaywallSheet(room: room)
        }
        .alert("Error", isPresented: Binding(
            get: { roomsVM.error != nil },
            set: { if !$0 { roomsVM.error = nil } }
        )) {
            Button("Dismiss", role: .cancel) { roomsVM.error = nil }
        } message: {
            Text(roomsVM.error ?? "")
        }
    }

    // MARK: - Room List Content

    private var roomListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !unreadRooms.isEmpty {
                    unreadSection
                }
                if !accessibleRooms.isEmpty {
                    accessibleSection
                }
                if !lockedRooms.isEmpty {
                    lockedSection
                }
                Spacer(minLength: 48)
            }
            .padding(.top, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading rooms…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(44))
                .foregroundStyle(.tertiary)
            Text("No rooms yet")
                .font(.headline)
            Text("Rooms will appear here once the creator sets them up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        )
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Unread Section

    private var unreadSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Unread")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(unreadRooms) { room in
                        UnreadRoomPill(room: room) {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                                vm.navigate(to: .room(covenantId: covenantId, roomId: room.id ?? ""))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Accessible Rooms Section

    private var accessibleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Your Rooms")

            VStack(spacing: 0) {
                ForEach(Array(accessibleRooms.enumerated()), id: \.element.id) { index, room in
                    RoomsViewRoomRow(room: room, isLocked: false) {
                        vm.navigate(to: .room(covenantId: covenantId, roomId: room.id ?? ""))
                    } onLockTap: {}

                    if index < accessibleRooms.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Locked Section

    private var lockedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Premium Rooms")

            VStack(spacing: 0) {
                ForEach(Array(lockedRooms.enumerated()), id: \.element.id) { index, room in
                    RoomsViewRoomRow(room: room, isLocked: true) {} onLockTap: {
                        paywallRoom = room
                    }

                    if index < lockedRooms.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Section Label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
    }
}

// MARK: - Unread Room Pill

private struct UnreadRoomPill: View {
    let room: CovenantRoom
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: room.type.icon)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.purple)

                Text(room.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(room.unreadCount > 99 ? "99+" : "\(room.unreadCount)")
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(room.name), \(room.unreadCount) unread messages")
    }
}

// MARK: - Room Row (private to this file, distinct from CovenantRoomRow in LiquidGlass)

private struct RoomsViewRoomRow: View {
    let room: CovenantRoom
    let isLocked: Bool
    let onTap: () -> Void
    let onLockTap: () -> Void

    var body: some View {
        Button(action: isLocked ? onLockTap : onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isLocked ? Color.secondary.opacity(0.12) : Color.purple.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: room.type.icon)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(isLocked ? Color.secondary : Color.purple)
                }

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(room.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isLocked ? Color.secondary : Color.primary)

                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.systemScaled(11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isLocked, let tierId = room.requiredTierId {
                        Text("Unlock with \(tierId) membership")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let lastMessage = room.lastMessage {
                        Text(lastMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(room.description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // Trailing
                VStack(alignment: .trailing, spacing: 4) {
                    if let lastAt = room.lastMessageAt {
                        Text(lastAt.dateValue().covenantRelativeFormatted())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if isLocked {
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else if room.unreadCount > 0 {
                        Text(room.unreadCount > 99 ? "99+" : "\(room.unreadCount)")
                            .font(.systemScaled(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.red))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .opacity(isLocked ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocked
            ? "\(room.name) room, locked. Requires paid membership."
            : "\(room.name) room\(room.unreadCount > 0 ? ", \(room.unreadCount) unread" : "")"
        )
        .accessibilityHint(isLocked ? "Double-tap to view upgrade options." : "Double-tap to open.")
    }
}

// MARK: - Locked Room Paywall Sheet

private struct LockedRoomPaywallSheet: View {
    let room: CovenantRoom
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "lock.fill")
                            .font(.systemScaled(32, weight: .medium))
                            .foregroundStyle(.purple)
                    }

                    VStack(spacing: 8) {
                        Text(room.name)
                            .font(.title2.weight(.bold))
                        Text("This room is available to paid members.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let tierId = room.requiredTierId {
                            Text("Upgrade to \(tierId) to join this conversation.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 32)

                HStack(spacing: 20) {
                    paywallPill(icon: "person.2.fill", label: "Real community")
                    paywallPill(icon: "heart.fill",   label: "Active rooms")
                    paywallPill(icon: "xmark.circle", label: "Cancel anytime")
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Text("View Membership Options")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .foregroundStyle(.white)
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.purple)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    Text("No pressure. Cancel anytime. This is a real community, not a paywall trap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not Now") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func paywallPill(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Date Formatting Helper

private extension Date {
    func covenantRelativeFormatted() -> String {
        let now = Date()
        let diff = now.timeIntervalSince(self)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 604800 { return "\(Int(diff / 86400))d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}
