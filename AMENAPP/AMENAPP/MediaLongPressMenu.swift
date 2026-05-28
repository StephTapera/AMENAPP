import SwiftUI
import UIKit

struct MediaLongPressMenu: View {
    @Binding var isPresented: Bool

    let isOwnPost: Bool
    let postPreviewImageURL: URL?
    let postAuthorName: String

    var onLike: () -> Void = {}
    var onRepost: () -> Void = {}
    var onShare: () -> Void = {}
    var onViewProfile: () -> Void = {}
    var onNotInterested: () -> Void = {}
    var onReport: () -> Void = {}

    var onDelete: () -> Void = {}
    var onEdit: () -> Void = {}
    var onPin: () -> Void = {}

    var onDismiss: () -> Void = {}

    @State private var cardOffset: CGFloat = 400

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop
            card
                .offset(y: cardOffset)
        }
        .ignoresSafeArea()
        .onAppear {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                cardOffset = 0
            }
        }
        .onChange(of: isPresented) { presented in
            if !presented {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    cardOffset = 400
                }
            }
        }
    }

    private var backdrop: some View {
        Color.clear
            .background(.ultraThinMaterial.opacity(0.6))
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .accessibilityLabel("Dismiss menu")
            .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        VStack(spacing: 0) {
            previewStrip
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()
                .foregroundStyle(.secondary.opacity(0.5))

            if isOwnPost {
                ownerActions
            } else {
                viewerActions
            }

            Color.clear.frame(height: 34)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 8)
    }

    private var previewStrip: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(
                url: postPreviewImageURL,
                size: CGSize(width: 100, height: 100)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.systemGray5)
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(postAuthorName)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
    }

    private var viewerActions: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "heart",
                label: "Like",
                hint: "Like this post"
            ) {
                onLike()
                dismiss()
            }
            rowDivider
            actionRow(
                icon: "arrow.2.squarepath",
                label: "Repost",
                hint: "Repost to your followers"
            ) {
                onRepost()
                dismiss()
            }
            rowDivider
            actionRow(
                icon: "square.and.arrow.up",
                label: "Share",
                hint: "Share this post"
            ) {
                onShare()
                dismiss()
            }
            rowDivider
            actionRow(
                icon: "person.circle",
                label: "View profile",
                hint: "View the author's profile"
            ) {
                onViewProfile()
                dismiss()
            }
            rowDivider
            actionRow(
                icon: "hand.thumbsdown",
                label: "Not interested",
                hint: "Hide posts like this from your feed"
            ) {
                onNotInterested()
                dismiss()
            }
            rowDivider
            actionRow(
                icon: "flag",
                label: "Report",
                hint: "Report this post",
                tint: .red
            ) {
                onReport()
                dismiss()
            }
        }
    }

    private var ownerActions: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "trash",
                label: "Delete",
                hint: "Permanently delete this post",
                tint: .red
            ) {
                onDelete()
                dismiss()
            }
            rowDivider
            actionRow(
                icon: "pencil",
                label: "Edit",
                hint: "Edit this post"
            ) {
                onEdit()
                dismiss()
            }
            rowDivider
            actionRow(
                icon: "pin",
                label: "Pin",
                hint: "Pin this post to the top of your profile"
            ) {
                onPin()
                dismiss()
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .foregroundStyle(.secondary.opacity(0.5))
            .padding(.leading, 60)
    }

    private func actionRow(
        icon: String,
        label: String,
        hint: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)

                Text(label)
                    .font(.body)
                    .foregroundStyle(tint == .red ? tint : .primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            cardOffset = 400
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
            onDismiss()
        }
    }
}

extension View {
    func mediaLongPressMenu(
        isPresented: Binding<Bool>,
        isOwnPost: Bool,
        postPreviewImageURL: URL?,
        postAuthorName: String,
        onLike: @escaping () -> Void = {},
        onRepost: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {},
        onViewProfile: @escaping () -> Void = {},
        onNotInterested: @escaping () -> Void = {},
        onReport: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onEdit: @escaping () -> Void = {},
        onPin: @escaping () -> Void = {}
    ) -> some View {
        ZStack(alignment: .bottom) {
            self

            if isPresented.wrappedValue {
                MediaLongPressMenu(
                    isPresented: isPresented,
                    isOwnPost: isOwnPost,
                    postPreviewImageURL: postPreviewImageURL,
                    postAuthorName: postAuthorName,
                    onLike: onLike,
                    onRepost: onRepost,
                    onShare: onShare,
                    onViewProfile: onViewProfile,
                    onNotInterested: onNotInterested,
                    onReport: onReport,
                    onDelete: onDelete,
                    onEdit: onEdit,
                    onPin: onPin
                )
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented.wrappedValue)
    }
}
