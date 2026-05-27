import SwiftUI
import FirebaseFirestore

// MARK: - MuteSheet

/// Pull-up sheet that lets the user mute a person or topic for a chosen duration.
/// After muting, a `GlassToastView` with an "Undo" action is shown for 5 seconds.
@MainActor
struct MuteSheet: View {
    @Binding var isPresented: Bool
    var targetName: String       // user or topic display name
    var targetType: MuteTargetType
    var currentUserId: String    // ID of the user performing the mute
    var onMuted: (MuteEntry) -> Void

    @State private var isProcessing = false
    @State private var toastVisible = false
    @State private var toastMessage = ""
    @State private var lastMuteEntry: MuteEntry?

    private let db = Firestore.firestore()

    // MARK: - Duration options

    private struct DurationOption: Identifiable {
        let id: String
        let label: String
        let expiryOffset: TimeInterval?   // nil = indefinite
    }

    private let options: [DurationOption] = [
        DurationOption(id: "24h",  label: "24 hours",       expiryOffset: 60 * 60 * 24),
        DurationOption(id: "7d",   label: "7 days",         expiryOffset: 60 * 60 * 24 * 7),
        DurationOption(id: "30d",  label: "30 days",        expiryOffset: 60 * 60 * 24 * 30),
        DurationOption(id: "indef", label: "Until I unmute", expiryOffset: nil),
    ]

    // MARK: - Body

    var body: some View {
        EmptyView()
            .glassSheet(isPresented: $isPresented, detent: .small) {
                sheetContent
            }
            .glassToast(
                message: toastMessage,
                actionLabel: "Undo",
                onAction: undoMute,
                isVisible: $toastVisible
            )
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Mute \(targetName)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .background(AmenTheme.Colors.separatorSubtle)

            // Options list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(options) { option in
                        optionRow(option)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(AmenTheme.Colors.backgroundPrimary)
    }

    @ViewBuilder
    private func optionRow(_ option: DurationOption) -> some View {
        Button {
            Task { await performMute(option: option) }
        } label: {
            HStack {
                Text(option.label)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel("Mute \(targetName) for \(option.label)")
    }

    // MARK: - Actions

    private func performMute(option: DurationOption) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let expiry: Date? = option.expiryOffset.map { Date.now.addingTimeInterval($0) }

        var entry = MuteEntry(
            userId: currentUserId,
            mutedUserId: targetType == .user ? targetName : nil,
            mutedTopic: targetType == .topic ? targetName : nil,
            expiresAt: expiry,
            createdAt: .now
        )

        do {
            let ref = try db
                .collection("mutes")
                .document(currentUserId)
                .collection("entries")
                .addDocument(from: entry)
            entry.id = ref.documentID
            lastMuteEntry = entry
            toastMessage = option.expiryOffset == nil
                ? "Muted until you unmute"
                : "Muted for \(option.label)"
            isPresented = false
            withAnimation { toastVisible = true }
            onMuted(entry)
        } catch {
            // Silently fail — caller can add error handling
        }
    }

    private func undoMute() {
        guard let entry = lastMuteEntry, let docId = entry.id else { return }
        Task {
            try? await db
                .collection("mutes")
                .document(currentUserId)
                .collection("entries")
                .document(docId)
                .delete()
        }
    }
}
