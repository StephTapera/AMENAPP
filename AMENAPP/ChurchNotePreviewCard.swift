//
//  ChurchNotePreviewCard.swift
//  AMENAPP
//
//  Liquid glass pill views for Church Notes and Find a Church shares in the OpenTable feed.
//  All share sheets match the AmenOptionsSheet design language.
//

import SwiftUI
import FirebaseFirestore
import UIKit

// MARK: - Church Note Pill (Feed)

/// Compact liquid glass pill shown in the OpenTable feed for church note shares.
struct ChurchNotePreviewCard: View {
    let note: ChurchNote
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            onTap()
        }) {
            HStack(spacing: 10) {
                // Icon well
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "book.closed.fill")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Group {
                        if let churchName = note.churchName {
                            Text(churchName)
                        } else if let sermon = note.sermonTitle {
                            Text(sermon)
                        } else {
                            Text(note.date.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                if !note.worshipSongs.isEmpty {
                    Image(systemName: "music.note")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(liquidGlassPill)
        }
        .buttonStyle(.plain)
        .pressableButton()
    }
}

// MARK: - Find Church Pill (Feed)

/// Compact liquid glass pill shown in the OpenTable feed for Find a Church shares.
struct FindChurchPill: View {
    let churchName: String
    let denomination: String?
    let serviceTime: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            onTap()
        }) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "building.columns.fill")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(churchName)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let denom = denomination {
                        Text(denom)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if let time = serviceTime, !time.isEmpty {
                    Text(time)
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(liquidGlassPill)
        }
        .buttonStyle(.plain)
        .pressableButton()
    }
}

// MARK: - Name-Only Church Capsule (Feed/Post Attachment)

/// Minimal name-only capsule used for post attachments (no denomination/time).
struct ChurchNameCapsulePill: View {
    let churchName: String
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            onTap()
        }) {
            Text(churchName)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(liquidGlassPill)
        }
        .buttonStyle(.plain)
        .pressableButton()
    }
}

// MARK: - Church Event Capsule (Feed/Post Attachment)

/// Compact event capsule attached to posts/notes when a specific church event is referenced.
struct ChurchEventCapsulePill: View {
    let eventName: String
    let eventTime: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.impact(style: .light)
            onTap()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(eventName)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let eventTime, !eventTime.isEmpty {
                    Text("· \(eventTime)")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(liquidGlassPill)
        }
        .buttonStyle(.plain)
        .pressableButton()
    }
}

// MARK: - Worship Music Pill

/// Tappable music pill for a worship song reference — opens Spotify or Apple Music.
struct WorshipMusicPill: View {
    let song: WorshipSongReference
    @Environment(\.openURL) private var openURL
    @State private var showUnavailableAlert = false

    var body: some View {
        Button(action: openMusic) {
            HStack(spacing: 10) {
                artworkView

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(statusLine)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(song.providerBadgeText)
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.56))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                            )
                    )

                Image(systemName: trailingIcon)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(song.availabilityState == .unavailable ? .secondary : .tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(musicCapsuleBackground)
        }
        .buttonStyle(.plain)
        .pressableButton()
        .contextMenu {
            if let url = preferredURL {
                Button("Open in \(song.provider.displayName)") {
                    openURL(url)
                }
            }

            if let url = webFallbackURL, url != preferredURL {
                Button("View on \(song.provider.displayName)") {
                    openURL(url)
                }
            }

            if let link = (webFallbackURL ?? preferredURL)?.absoluteString {
                Button("Copy Link") {
                    UIPasteboard.general.string = link
                }
            }
        }
        .alert("Music Unavailable", isPresented: $showUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This attachment can’t be opened right now. Try updating the link or reopening it later.")
        }
    }

    private var preferredURL: URL? {
        guard let deepLinkURL = song.deepLinkURL, let url = URL(string: deepLinkURL) else {
            return nil
        }
        return UIApplication.shared.canOpenURL(url) ? url : nil
    }

    private var webFallbackURL: URL? {
        guard let webURL = song.webURL else { return nil }
        return URL(string: webURL)
    }

    private var trailingIcon: String {
        switch song.availabilityState {
        case .unavailable:
            return "exclamationmark.circle"
        case .accountRequired:
            return "lock.circle"
        case .viewOnly:
            return "arrow.up.right.circle"
        case .readyToOpen:
            return "chevron.right"
        }
    }

    private var statusLine: String {
        let base = song.subtitle ?? song.artist
        let helper = song.availabilityState.helperText
        return base.isEmpty ? helper : "\(base) · \(helper)"
    }

    private var artworkView: some View {
        Group {
            if let artworkURL = song.artworkURL, let url = URL(string: artworkURL) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.08))
            .overlay(
                Image(systemName: "music.note")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
            )
    }

    private var musicCapsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.62))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    private func openMusic() {
        if let preferredURL {
            openURL(preferredURL)
            return
        }

        if let webFallbackURL {
            openURL(webFallbackURL)
            return
        }

        HapticManager.notification(type: .warning)
        showUnavailableAlert = true
    }
}

// MARK: - Shared Background

private var liquidGlassPill: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.07), lineWidth: 0.8)
        )
}

// MARK: - Church Note Detail Modal

/// Full-screen church note detail view (modal presentation from feed pill tap).
struct ChurchNoteDetailModal: View {
    let note: ChurchNote
    @Environment(\.dismiss) var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Category badge + title
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "book.closed.fill")
                                .font(.systemScaled(11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Church Note")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().stroke(Color(.separator).opacity(0.5), lineWidth: 0.6))
                        )

                        Text(note.title)
                            .font(.systemScaled(28, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                    // Metadata
                    VStack(alignment: .leading, spacing: 10) {
                        if let sermonTitle = note.sermonTitle {
                            NoteMetadataRow(label: "Sermon", value: sermonTitle)
                        }
                        if let pastor = note.pastor {
                            NoteMetadataRow(label: "Pastor", value: pastor)
                        }
                        if let churchName = note.churchName {
                            NoteMetadataRow(label: "Church", value: churchName)
                        }
                        NoteMetadataRow(label: "Date", value: note.date.formatted(date: .long, time: .omitted))
                        if !note.scriptureReferences.isEmpty {
                            NoteMetadataRow(label: "Scripture", value: note.scriptureReferences.joined(separator: ", "))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // Worship songs
                    if !note.worshipSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WORSHIP")
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.8)
                                .padding(.horizontal, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(note.worshipSongs) { song in
                                        WorshipMusicPill(song: song)
                                            .frame(width: min(280, UIScreen.main.bounds.width - 40))
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.bottom, 24)
                    }

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Note body
                    Text(note.content)
                        .font(.systemScaled(16))
                        .foregroundStyle(.primary)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Key Points
                    if !note.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("KEY POINTS")
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.8)
                                .padding(.bottom, 4)

                            ForEach(Array(note.keyPoints.enumerated()), id: \.offset) { _, point in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Color.primary.opacity(0.25))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text(point)
                                        .font(.systemScaled(15))
                                        .foregroundStyle(.primary)
                                        .lineSpacing(4)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    // Tags
                    if !note.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TAGS")
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.8)
                                .padding(.bottom, 4)

                            AMENFlowLayout(spacing: 8) {
                                ForEach(note.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.systemScaled(13))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(.ultraThinMaterial))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.systemScaled(16, weight: .medium))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showShareSheet = true }) {
                        Image(systemName: "ellipsis")
                            .font(.systemScaled(16, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ChurchNoteShareOptionsSheet(note: note)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
    }
}

// MARK: - Note Metadata Row

private struct NoteMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.systemScaled(14))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Church Note Share Options Sheet

/// AmenOptionsSheet-style share sheet for church notes — matches the OpenTable 3-dot sheet design.
struct ChurchNoteShareOptionsSheet: View {
    let note: ChurchNote
    @Environment(\.dismiss) var dismiss
    @State private var isSharingToOpenTable = false
    @State private var showInstagramStory = false

    var body: some View {
        AmenOptionsSheet(
            isPresented: .constant(true),
            title: "Share Note",
            subtitle: note.title,
            quickActions: [
                AmenQuickAction(title: "Copy Link", systemImage: "link") {
                    copyLink()
                    dismiss()
                },
                AmenQuickAction(title: "Share Text", systemImage: "doc.text") {
                    ChurchNotesShareHelper.shareNote(note, from: nil)
                    dismiss()
                },
                AmenQuickAction(title: "Instagram", systemImage: "camera.fill") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showInstagramStory = true
                    }
                }
            ],
            sections: [
                AmenOptionsSectionModel(title: "Community", actions: [
                    AmenOptionAction(
                        title: isSharingToOpenTable ? "Sharing…" : "Share to #OPENTABLE",
                        subtitle: "Post this note to your feed",
                        systemImage: "bubble.left.and.bubble.right",
                        isEnabled: !isSharingToOpenTable,
                        action: {
                            guard !isSharingToOpenTable else { return }
                            isSharingToOpenTable = true
                            shareToOpenTable()
                        }
                    ),
                    AmenOptionAction(
                        title: "Send in Message",
                        subtitle: "Share with someone on AMEN",
                        systemImage: "message",
                        action: { dismiss() }
                    ),
                    AmenOptionAction(
                        title: "Export PDF",
                        subtitle: "Save as a PDF document",
                        systemImage: "doc.richtext",
                        action: {
                            ChurchNotesShareHelper.sharePDF(for: note, from: nil)
                            dismiss()
                        }
                    )
                ])
            ]
        )
        .fullScreenCover(isPresented: $showInstagramStory) {
            AmenStoryShareView(content: .from(churchNote: note))
        }
    }

    private func shareToOpenTable() {
        ChurchNotesShareHelper.shareToCommunit(note) { success in
            let haptic = UINotificationFeedbackGenerator()
            if success {
                haptic.notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { dismiss() }
            } else {
                haptic.notificationOccurred(.error)
                isSharingToOpenTable = false
            }
        }
    }

    private func copyLink() {
        guard let linkId = note.shareLinkId else { return }
        UIPasteboard.general.string = "amenapp://note/\(linkId)"
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}

// MARK: - Find Church Share Options Sheet

/// AmenOptionsSheet-style share sheet for Find a Church — matches the OpenTable 3-dot sheet design.
struct FindChurchShareOptionsSheet: View {
    let church: Church
    @Environment(\.dismiss) var dismiss
    @State private var isSharingToOpenTable = false
    @State private var showInstagramStory = false

    var body: some View {
        AmenOptionsSheet(
            isPresented: .constant(true),
            title: "Share Church",
            subtitle: church.name,
            quickActions: [
                AmenQuickAction(title: "Copy Info", systemImage: "doc.on.clipboard") {
                    UIPasteboard.general.string = church.shareText
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                },
                AmenQuickAction(title: "Directions", systemImage: "map") {
                    openDirections()
                    dismiss()
                },
                AmenQuickAction(title: "Instagram", systemImage: "camera.fill") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showInstagramStory = true
                    }
                }
            ],
            sections: [
                AmenOptionsSectionModel(title: "Community", actions: [
                    AmenOptionAction(
                        title: isSharingToOpenTable ? "Sharing…" : "Share to #OPENTABLE",
                        subtitle: "Post this church to your feed",
                        systemImage: "bubble.left.and.bubble.right",
                        isEnabled: !isSharingToOpenTable,
                        action: {
                            guard !isSharingToOpenTable else { return }
                            isSharingToOpenTable = true
                            shareChurchToOpenTable()
                        }
                    )
                ]),
                AmenOptionsSectionModel(title: "More", actions: [
                    AmenOptionAction(
                        title: "Share Externally",
                        subtitle: "Send outside of AMEN",
                        systemImage: "square.and.arrow.up",
                        action: { shareExternally() }
                    )
                ])
            ]
        )
        .fullScreenCover(isPresented: $showInstagramStory) {
            AmenStoryShareView(content: .init(
                label: church.denomination.isEmpty ? "Find a Church" : church.denomination,
                bodyText: church.name,
                metadata: church.shortServiceTime.isEmpty ? "" : "Service: \(church.shortServiceTime)",
                showLogo: true
            ))
        }
    }

    private func shareChurchToOpenTable() {
        Task {
            do {
                let city = church.address
                    .components(separatedBy: ",")
                    .dropFirst()
                    .first?
                    .trimmingCharacters(in: .whitespaces) ?? church.address
                let content = "Check out \(church.name) — \(church.denomination) in \(city). Service: \(church.serviceTime) 🙏"
                try await FirebasePostService.shared.createPost(
                    content: content,
                    category: .openTable,
                    topicTag: "Find a Church",
                    visibility: .everyone,
                    allowComments: true,
                    isChurchShare: true,
                    sharedChurchName: church.name,
                    sharedChurchDenomination: church.denomination,
                    sharedChurchServiceTime: church.shortServiceTime
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    isSharingToOpenTable = false
                    dlog("❌ Failed to share church to #OPENTABLE: \(error)")
                }
            }
        }
    }

    private func openDirections() {
        let urlString = "maps://?daddr=\(church.latitude),\(church.longitude)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private func shareExternally() {
        let text = church.shareText
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        ChurchNotePreviewCard(note: ChurchNote.preview) {
            dlog("Tapped note")
        }
        FindChurchPill(
            churchName: "Elevation Church",
            denomination: "Non-Denominational",
            serviceTime: "9:00 AM"
        ) {
            dlog("Tapped church")
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
