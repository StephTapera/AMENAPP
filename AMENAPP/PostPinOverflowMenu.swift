// PostPinOverflowMenu.swift
// AMENAPP
//
// Liquid Glass post overflow menu with Threads-style pinning.
// Present as .sheet(isPresented:) { PostPinOverflowMenu(post: post, isCurrentUser: true) }
// Does NOT modify PostCard or any existing post card component.

import SwiftUI
import Foundation
import FirebaseAuth

// MARK: - PostPinOverflowMenu

struct PostPinOverflowMenu: View {
    let postId: String
    let postAuthorId: String
    let isCurrentUserPost: Bool
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var pinService = PostPinningService.shared
    @State private var showPinTypeSheet = false
    @State private var isPinned: Bool = false
    @State private var selectedPinType: PinnedPostRecord.PinType = .standard
    @State private var isPinActionInFlight = false

    var body: some View {
        ZStack {
            // Liquid Glass background
            Color.white.opacity(0.55)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Drag Handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.45))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                // MARK: Section Header
                HStack {
                    Text("Post options")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundColor(.gray)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // MARK: Menu Rows
                VStack(spacing: 0) {
                    if isCurrentUserPost {
                        ownPostRows
                    } else {
                        otherPostRows
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.45))
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)

                // MARK: Cancel Button
                Button {
                    dlog("PostPinOverflowMenu: user tapped Cancel")
                    dismiss()
                    onDismiss()
                } label: {
                    Text("Cancel")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.85))
                                .background(
                                    Capsule().fill(.ultraThinMaterial)
                                )
                        )
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28
            )
        )
        .onAppear {
            isPinned = pinService.isPinned(postId)
            dlog("PostPinOverflowMenu: appeared for postId=\(postId), isPinned=\(isPinned), isCurrentUserPost=\(isCurrentUserPost)")
        }
    }

    // MARK: - Own Post Rows

    @ViewBuilder
    private var ownPostRows: some View {
        // Pin / Unpin row
        VStack(spacing: 0) {
            MenuRow(
                icon: "pin.fill",
                title: isPinned ? "Unpin from profile" : "Pin to profile",
                subtitle: isPinned ? "Remove pinned post" : "Feature this on your profile",
                isDestructive: false
            ) {
                handlePinTap()
            }

            // Pin type picker — inline expansion
            if showPinTypeSheet {
                Divider().opacity(0.3).padding(.leading, 64)
                PinTypePickerView(selectedType: $selectedPinType) { chosenType in
                    confirmPin(type: chosenType)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.vertical, 8)
            }

            Divider().opacity(0.3).padding(.leading, 64)
        }

        MenuRow(icon: "bookmark.fill", title: "Save post", isDestructive: false) {
            dlog("PostPinOverflowMenu: Save post tapped for \(postId)")
            dismiss(); onDismiss()
        }

        Divider().opacity(0.3).padding(.leading, 64)

        MenuRow(icon: "square.and.arrow.up", title: "Share", isDestructive: false) {
            dlog("PostPinOverflowMenu: Share tapped for \(postId)")
            dismiss(); onDismiss()
        }

        Divider().opacity(0.3).padding(.leading, 64)

        MenuRow(icon: "link", title: "Copy link", isDestructive: false) {
            dlog("PostPinOverflowMenu: Copy link tapped for \(postId)")
            UIPasteboard.general.string = "amenapp://post/\(postId)"
            dismiss(); onDismiss()
        }

        Divider().opacity(0.3).padding(.leading, 64)

        MenuRow(icon: "trash.fill", title: "Delete", isDestructive: true) {
            dlog("PostPinOverflowMenu: Delete tapped for \(postId)")
            dismiss(); onDismiss()
        }
    }

    // MARK: - Other Post Rows

    @ViewBuilder
    private var otherPostRows: some View {
        MenuRow(icon: "bookmark.fill", title: "Save post", isDestructive: false) {
            dlog("PostPinOverflowMenu: Save post tapped for \(postId)")
            dismiss(); onDismiss()
        }

        Divider().opacity(0.3).padding(.leading, 64)

        MenuRow(icon: "square.and.arrow.up", title: "Share", isDestructive: false) {
            dlog("PostPinOverflowMenu: Share tapped for \(postId)")
            dismiss(); onDismiss()
        }

        Divider().opacity(0.3).padding(.leading, 64)

        MenuRow(icon: "link", title: "Copy link", isDestructive: false) {
            dlog("PostPinOverflowMenu: Copy link tapped for \(postId)")
            UIPasteboard.general.string = "amenapp://post/\(postId)"
            dismiss(); onDismiss()
        }

        Divider().opacity(0.3).padding(.leading, 64)

        MenuRow(icon: "flag.fill", title: "Report", subtitle: "Report this post", isDestructive: false, isMuted: true) {
            dlog("PostPinOverflowMenu: Report tapped for \(postId)")
            dismiss(); onDismiss()
        }

        Divider().opacity(0.3).padding(.leading, 64)

        MenuRow(icon: "person.slash.fill", title: "Hide posts like this", isDestructive: false, isMuted: true) {
            dlog("PostPinOverflowMenu: Hide posts like this tapped for \(postId)")
            dismiss(); onDismiss()
        }
    }

    // MARK: - Pin Logic

    private func handlePinTap() {
        if isPinned {
            // Unpin immediately
            Task {
                isPinActionInFlight = true
                do {
                    try await pinService.unpinPost(postId)
                    await MainActor.run {
                        isPinned = false
                        isPinActionInFlight = false
                        dlog("PostPinOverflowMenu: unpinned \(postId)")
                        dismiss()
                        onDismiss()
                    }
                } catch {
                    await MainActor.run {
                        isPinActionInFlight = false
                        dlog("PostPinOverflowMenu: unpin error — \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Show inline pin type picker
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showPinTypeSheet.toggle()
            }
            dlog("PostPinOverflowMenu: showing pin type picker for \(postId)")
        }
    }

    private func confirmPin(type: PinnedPostRecord.PinType) {
        Task {
            isPinActionInFlight = true
            do {
                try await pinService.pinPost(postId, type: type)
                await MainActor.run {
                    isPinned = true
                    isPinActionInFlight = false
                    showPinTypeSheet = false
                    dlog("PostPinOverflowMenu: pinned \(postId) as \(type.rawValue)")
                    dismiss()
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isPinActionInFlight = false
                    dlog("PostPinOverflowMenu: pin error — \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - MenuRow

private struct MenuRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let isDestructive: Bool
    var isMuted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .background(Circle().fill(.ultraThinMaterial))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                        )

                    Image(systemName: icon)
                        .font(.systemScaled(17, weight: .medium))
                        .foregroundColor(
                            isDestructive ? Color.red.opacity(0.85) :
                            isMuted ? Color.gray : .primary
                        )
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundColor(
                            isDestructive ? Color.red.opacity(0.85) :
                            isMuted ? Color.gray : .primary
                        )

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.systemScaled(13))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundColor(Color.gray.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PinTypePickerView

struct PinTypePickerView: View {
    @Binding var selectedType: PinnedPostRecord.PinType
    let onConfirm: (PinnedPostRecord.PinType) -> Void

    private let options: [(icon: String, label: String, type: PinnedPostRecord.PinType)] = [
        ("heart.text.square.fill", "Pinned Testimony", .testimony),
        ("text.book.closed.fill",  "Pinned Teaching",  .teaching),
        ("note.text",              "Pinned Church Note", .churchNote),
        ("pin.fill",               "Standard Pin",     .standard)
    ]

    var body: some View {
        VStack(spacing: 12) {
            // 2×2 chip grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(options, id: \.type.rawValue) { option in
                    PinTypeChip(
                        icon: option.icon,
                        label: option.label,
                        isSelected: selectedType == option.type
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedType = option.type
                        }
                        dlog("PinTypePickerView: selected \(option.type.rawValue)")
                    }
                }
            }
            .padding(.horizontal, 16)

            // Confirm button
            Button {
                dlog("PinTypePickerView: confirmed pin type \(selectedType.rawValue)")
                onConfirm(selectedType)
            } label: {
                HStack(spacing: 6) {
                    Text("Pin to profile")
                        .font(.systemScaled(15, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.systemScaled(14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule().fill(Color.black.opacity(0.88))
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - PinTypeChip

private struct PinTypeChip: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundColor(isSelected ? .black : .primary)

                Text(label)
                    .font(.systemScaled(13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .black : .primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.35))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.black.opacity(0.25) : Color.white.opacity(0.5),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PreviewProvider

struct PostPinOverflowMenu_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PostPinOverflowMenu(
                postId: "preview-post-123",
                postAuthorId: "user-abc",
                isCurrentUserPost: true,
                onDismiss: {}
            )
            .previewDisplayName("Own Post")

            PostPinOverflowMenu(
                postId: "preview-post-456",
                postAuthorId: "user-xyz",
                isCurrentUserPost: false,
                onDismiss: {}
            )
            .previewDisplayName("Other Post")
        }
    }
}
