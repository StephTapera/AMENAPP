import SwiftUI
import FirebaseFunctions

// MARK: - Media Attachment Picker

/// Composer sheet for attaching media to a post.
/// Tabs: Paste Link · Recent · Saved Songs · Search (feature-gated).
struct AmenMediaAttachmentPickerView: View {
    let currentState: AmenAttachmentComposerState
    let onAttach: (AmenSmartAttachment) -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared

    @State private var selectedTab: PickerTab = .pasteLink
    @State private var pastedURL = ""
    @State private var resolveState: ResolveState = .idle
    @State private var recentAttachments: [AmenSmartAttachment] = []
    @State private var savedSongs: [AmenSmartAttachment] = []
    @State private var isLoadingRecent = false

    private let resolver = AmenSmartAttachmentResolverService.shared
    private let mediaGraph = AmenMediaGraphService.shared

    enum PickerTab: String, CaseIterable {
        case pasteLink = "Paste Link"
        case recent = "Recent"
        case saved = "Saved Songs"
    }

    enum ResolveState: Equatable {
        case idle
        case resolving
        case resolved(AmenSmartAttachment)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                tabContent
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Add Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await loadRecentsAndSaved() }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(PickerTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.systemScaled(13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch selectedTab {
                case .pasteLink:
                    pasteLinkContent
                case .recent:
                    recentContent
                case .saved:
                    savedContent
                }
            }
            .padding(16)
        }
    }

    // MARK: - Paste Link

    private var pasteLinkContent: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Paste a YouTube, Spotify, Apple Music, or web link", text: $pastedURL)
                    .font(.systemScaled(14))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    .accessibilityLabel("Paste link")
                    .onChange(of: pastedURL) { _, newValue in
                        if case .failed = resolveState { resolveState = .idle }
                        if case .resolved = resolveState { resolveState = .idle }
                    }

                if !pastedURL.isEmpty {
                    Button {
                        pastedURL = ""
                        resolveState = .idle
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear link")
                }
            }

            switch resolveState {
            case .idle:
                if !pastedURL.isEmpty {
                    Button {
                        resolveURL()
                    } label: {
                        Text("Preview Link")
                            .font(.systemScaled(14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Preview link")
                }

            case .resolving:
                AmenSmartAttachmentSkeletonCard()

            case .resolved(let attachment):
                VStack(spacing: 10) {
                    AmenSmartAttachmentCard(
                        attachment: attachment,
                        smartAction: nil,
                        onTap: {}
                    )

                    if attachment.type == .song || attachment.type == .album {
                        attachButton(for: attachment, label: "Attach \(attachment.type == .song ? "Song" : "Album")")
                    } else if attachment.type == .video {
                        attachButton(for: attachment, label: "Attach Video")
                    } else {
                        attachButton(for: attachment, label: "Attach Link")
                    }
                }

            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            }

            supportedProviderHint
        }
    }

    private var supportedProviderHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Supported links")
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                ForEach(["YouTube", "Spotify", "Apple Music", "Web Articles"], id: \.self) { provider in
                    Text(provider)
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.tertiarySystemBackground)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attachButton(for attachment: AmenSmartAttachment, label: String) -> some View {
        Button {
            onAttach(attachment)
        } label: {
            Text(label)
                .font(.systemScaled(14, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(label)
    }

    // MARK: - Recent Attachments

    @ViewBuilder
    private var recentContent: some View {
        if isLoadingRecent {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if recentAttachments.isEmpty {
            emptyState(
                icon: "clock",
                title: "No recent attachments",
                subtitle: "Links you attach to posts will appear here."
            )
        } else {
            ForEach(recentAttachments) { attachment in
                AmenSmartAttachmentCard(
                    attachment: attachment,
                    smartAction: nil,
                    onTap: { onAttach(attachment) }
                )
                .accessibilityHint("Double tap to attach")
            }
        }
    }

    // MARK: - Saved Songs

    @ViewBuilder
    private var savedContent: some View {
        if isLoadingRecent {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if savedSongs.isEmpty {
            emptyState(
                icon: "music.note",
                title: "No saved songs",
                subtitle: "Songs you save to your media graph will appear here."
            )
        } else {
            ForEach(savedSongs) { attachment in
                AmenSmartAttachmentCard(
                    attachment: attachment,
                    smartAction: nil,
                    onTap: { onAttach(attachment) }
                )
                .accessibilityHint("Double tap to attach")
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func resolveURL() {
        guard let url = URL(string: pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" else {
            resolveState = .failed("Please enter a valid https link.")
            return
        }
        resolveState = .resolving
        Task {
            do {
                let attachment = try await resolver.resolve(url: url, source: "musicPicker")
                await MainActor.run {
                    if attachment.safetyStatus == .blocked {
                        resolveState = .failed("This link was blocked for safety reasons.")
                    } else {
                        resolveState = .resolved(attachment)
                    }
                }
            } catch {
                await MainActor.run {
                    resolveState = .failed("Could not load link. Please check the URL and try again.")
                }
            }
        }
    }

    private func loadRecentsAndSaved() async {
        guard featureFlags.smartAttachmentMediaGraphEnabled else { return }
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        // Recent and saved are stored by the media graph service.
        // The callable returns raw dictionaries; we do a best-effort parse here.
        // Full post-attached attachments are surfaced through the normal feed.
        do {
            let rawSaved = try await mediaGraph.getSavedSongs()
            let parsed = rawSaved.compactMap { try? AmenSmartAttachmentResolverService.parseAttachment($0) }
            await MainActor.run { savedSongs = parsed }
        } catch {
            dlog("[AmenMediaAttachmentPickerView] loadSaved failed: \(error)")
        }
    }
}
