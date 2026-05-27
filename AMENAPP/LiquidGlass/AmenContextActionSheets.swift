import SwiftUI

// MARK: - Button Style

enum AmenActionButtonStyle {
    case primary, secondary, destructive
}

// MARK: - Action Button

struct AmenSheetActionButton: View {
    let icon: String
    let label: String
    let style: AmenActionButtonStyle
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24, alignment: .center)
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background { buttonBackground }
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: 0.3, dampingFraction: 0.8),
                value: isPressed
            )
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private var labelColor: Color {
        switch style {
        case .primary: return .primary
        case .secondary: return .secondary
        case .destructive: return .red
        }
    }

    @ViewBuilder private var buttonBackground: some View {
        let radius: CGFloat = 12
        if reduceTransparency {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(buttonFill)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                }
        }
    }

    private var buttonFill: Color {
        switch style {
        case .primary: return Color.black.opacity(0.07)
        case .secondary: return Color.gray.opacity(0.10)
        case .destructive: return Color.red.opacity(0.10)
        }
    }
}

// MARK: - Sheet Container

struct AmenActionSheetContainer<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            dragIndicator
            header
            Divider().opacity(0.25).padding(.horizontal, 16)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    content()
                }
                .padding(16)
                .padding(.bottom, 8)
            }
        }
        .background { sheetBackground }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        }
    }

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.primary.opacity(0.18))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder private var sheetBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay { Color.white.opacity(0.04) }
        }
    }
}

// MARK: - 1. Prayer Request Action Sheet

struct PrayerRequestActionSheet: View {
    let postContent: String
    var onPrayNow: () -> Void = {}
    var onFavorite: () -> Void = {}
    var onShare: () -> Void = {}
    var onMute: () -> Void = {}
    var onReport: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AmenActionSheetContainer(
            title: "Prayer Request",
            subtitle: postContent.isEmpty ? nil : String(postContent.prefix(80))
        ) {
            AmenSheetActionButton(icon: "hands.sparkles.fill", label: "Pray Now", style: .primary) { onPrayNow(); dismiss() }
            AmenSheetActionButton(icon: "star.fill", label: "Add to Favorites", style: .secondary) { onFavorite(); dismiss() }
            AmenSheetActionButton(icon: "square.and.arrow.up", label: "Share Prayer", style: .secondary) { onShare(); dismiss() }
            AmenSheetActionButton(icon: "bell.slash.fill", label: "Mute Updates", style: .secondary) { onMute(); dismiss() }
            AmenSheetActionButton(icon: "flag.fill", label: "Report Prayer", style: .destructive) { onReport(); dismiss() }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

// MARK: - 2. Post / Testimony Action Sheet

struct PostActionSheet: View {
    let postContent: String
    let isOwner: Bool
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onSave: () -> Void = {}
    var onEdit: () -> Void = {}
    var onReport: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AmenActionSheetContainer(
            title: "Post",
            subtitle: postContent.isEmpty ? nil : String(postContent.prefix(80))
        ) {
            AmenSheetActionButton(icon: "heart.fill", label: "Like", style: .primary) { onLike(); dismiss() }
            AmenSheetActionButton(icon: "bubble.right.fill", label: "Comment", style: .secondary) { onComment(); dismiss() }
            AmenSheetActionButton(icon: "square.and.arrow.up", label: "Share Post", style: .secondary) { onShare(); dismiss() }
            AmenSheetActionButton(icon: "bookmark.fill", label: "Save Post", style: .secondary) { onSave(); dismiss() }
            if isOwner {
                AmenSheetActionButton(icon: "pencil", label: "Edit Post", style: .secondary) { onEdit(); dismiss() }
            } else {
                AmenSheetActionButton(icon: "flag.fill", label: "Report Post", style: .destructive) { onReport(); dismiss() }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

// MARK: - 3. Message / Conversation Action Sheet

struct MessageActionSheet: View {
    let conversationName: String
    var onReply: () -> Void = {}
    var onForward: () -> Void = {}
    var onStar: () -> Void = {}
    var onCopy: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AmenActionSheetContainer(title: "Message", subtitle: conversationName) {
            AmenSheetActionButton(icon: "arrowshape.turn.up.left.fill", label: "Reply", style: .primary) { onReply(); dismiss() }
            AmenSheetActionButton(icon: "arrowshape.turn.up.right.fill", label: "Forward", style: .secondary) { onForward(); dismiss() }
            AmenSheetActionButton(icon: "star.fill", label: "Star Message", style: .secondary) { onStar(); dismiss() }
            AmenSheetActionButton(icon: "doc.on.doc.fill", label: "Copy", style: .secondary) { onCopy(); dismiss() }
            AmenSheetActionButton(icon: "trash.fill", label: "Delete", style: .destructive) { onDelete(); dismiss() }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

// MARK: - 4. Church Event Action Sheet

struct ChurchEventActionSheet: View {
    let eventTitle: String
    var onRSVP: () -> Void = {}
    var onCalendar: () -> Void = {}
    var onDirections: () -> Void = {}
    var onShare: () -> Void = {}
    var onNotifications: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AmenActionSheetContainer(title: "Church Event", subtitle: eventTitle) {
            AmenSheetActionButton(icon: "checkmark.circle.fill", label: "RSVP Going", style: .primary) { onRSVP(); dismiss() }
            AmenSheetActionButton(icon: "calendar.badge.plus", label: "Add to Calendar", style: .secondary) { onCalendar(); dismiss() }
            AmenSheetActionButton(icon: "map.fill", label: "Get Directions", style: .secondary) { onDirections(); dismiss() }
            AmenSheetActionButton(icon: "square.and.arrow.up", label: "Share Event", style: .secondary) { onShare(); dismiss() }
            AmenSheetActionButton(icon: "bell.fill", label: "Manage Notifications", style: .secondary) { onNotifications(); dismiss() }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

// MARK: - 5. Church Note Action Sheet

struct ChurchNoteActionSheet: View {
    let noteTitle: String
    var onEdit: () -> Void = {}
    var onStar: () -> Void = {}
    var onShare: () -> Void = {}
    var onExport: () -> Void = {}
    var onMove: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AmenActionSheetContainer(title: "Church Note", subtitle: noteTitle) {
            AmenSheetActionButton(icon: "pencil", label: "Edit Note", style: .primary) { onEdit(); dismiss() }
            AmenSheetActionButton(icon: "star.fill", label: "Star Note", style: .secondary) { onStar(); dismiss() }
            AmenSheetActionButton(icon: "square.and.arrow.up", label: "Share", style: .secondary) { onShare(); dismiss() }
            AmenSheetActionButton(icon: "doc.richtext.fill", label: "Export PDF", style: .secondary) { onExport(); dismiss() }
            AmenSheetActionButton(icon: "folder.fill", label: "Move to Folder", style: .secondary) { onMove(); dismiss() }
            AmenSheetActionButton(icon: "trash.fill", label: "Delete Note", style: .destructive) { onDelete(); dismiss() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

// MARK: - 6. User Profile Action Sheet

struct UserProfileActionSheet: View {
    let username: String
    let isFollowing: Bool
    var onFollow: () -> Void = {}
    var onMessage: () -> Void = {}
    var onShare: () -> Void = {}
    var onMute: () -> Void = {}
    var onBlock: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AmenActionSheetContainer(title: "Profile", subtitle: username) {
            AmenSheetActionButton(
                icon: isFollowing ? "person.badge.minus.fill" : "person.badge.plus.fill",
                label: isFollowing ? "Unfollow" : "Follow",
                style: .primary
            ) { onFollow(); dismiss() }
            AmenSheetActionButton(icon: "paperplane.fill", label: "Send Message", style: .secondary) { onMessage(); dismiss() }
            AmenSheetActionButton(icon: "square.and.arrow.up", label: "Share Profile", style: .secondary) { onShare(); dismiss() }
            AmenSheetActionButton(icon: "bell.slash.fill", label: "Mute Notifications", style: .secondary) { onMute(); dismiss() }
            AmenSheetActionButton(icon: "hand.raised.fill", label: "Block User", style: .destructive) { onBlock(); dismiss() }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}

// MARK: - 7. Berean AI Chat Action Sheet

struct BereanChatActionSheet: View {
    let conversationTitle: String
    var onEdit: () -> Void = {}
    var onRegenerate: () -> Void = {}
    var onCopy: () -> Void = {}
    var onShare: () -> Void = {}
    var onBookmark: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AmenActionSheetContainer(
            title: "Berean Chat",
            subtitle: conversationTitle.isEmpty ? nil : String(conversationTitle.prefix(80))
        ) {
            AmenSheetActionButton(icon: "pencil.and.sparkles", label: "Edit Prompt", style: .primary) { onEdit(); dismiss() }
            AmenSheetActionButton(icon: "arrow.clockwise.circle.fill", label: "Regenerate", style: .secondary) { onRegenerate(); dismiss() }
            AmenSheetActionButton(icon: "doc.on.doc.fill", label: "Copy", style: .secondary) { onCopy(); dismiss() }
            AmenSheetActionButton(icon: "square.and.arrow.up", label: "Share", style: .secondary) { onShare(); dismiss() }
            AmenSheetActionButton(icon: "bookmark.fill", label: "Bookmark", style: .secondary) { onBookmark(); dismiss() }
            AmenSheetActionButton(icon: "trash.fill", label: "Delete Chat", style: .destructive) { onDelete(); dismiss() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
    }
}
