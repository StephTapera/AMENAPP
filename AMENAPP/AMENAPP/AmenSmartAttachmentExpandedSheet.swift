import SwiftUI

struct AmenSmartAttachmentExpandedSheet: View {
    let attachment: AmenSmartAttachment
    let postText: String
    let onOpenProvider: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    private var actionDecision: AmenSmartAttachmentActionDecision {
        AmenSmartAttachmentActionEngine.decide(attachment: attachment, postText: postText, surface: .expandedSheet)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AmenUniversalLinkCard(attachment: attachment, mode: .expandedDetail, onTap: onOpenProvider)
                    Text(attachment.title).font(.systemScaled(20, weight: .bold))
                    if let creatorName = attachment.creatorName {
                        Text(creatorName).font(.systemScaled(15)).foregroundStyle(.secondary)
                    }
                    if let description = attachment.description, !description.isEmpty {
                        Text(description).font(.systemScaled(14)).foregroundStyle(.secondary)
                    }

                    Button(action: onOpenProvider) {
                        Text(primaryCTA).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    VStack(spacing: 10) {
                        actionButton("Save to Selah") {
                            await save(.saveToSelah)
                        }
                        actionButton("Add to Church Notes") {
                            await save(.addToChurchNotes)
                        }
                        actionButton("Save for Later") {
                            await save(.saveForLater)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Media")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }

    private var primaryCTA: String {
        switch attachment.provider {
        case .appleMusic: return "Listen on Apple Music"
        case .spotify: return "Listen on Spotify"
        case .youtube: return "Watch on YouTube"
        case .applePodcasts: return "Listen on Apple Podcasts"
        case .instagram: return "Open on Instagram"
        case .threads: return "Open on Threads"
        case .tikTok: return "Open on TikTok"
        case .x: return "Open on X"
        case .facebook: return "Open on Facebook"
        case .linkedIn: return "Open on LinkedIn"
        case .medium: return "Open on Medium"
        case .substack: return "Open on Substack"
        case .rss: return "Open Feed"
        case .bibleGateway: return "Open on Bible Gateway"
        case .youVersion: return "Open on YouVersion"
        case .eventbrite: return "Open on Eventbrite"
        case .generic: return "Open Link"
        }
    }

    private func actionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack { Text(title); Spacer() }
        }
        .buttonStyle(.bordered)
        .disabled(isSaving)
    }

    private func save(_ action: AmenSmartAttachmentAction) async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch action {
            case .saveToSelah:
                try await AmenMediaGraphService.shared.saveToSelah(attachment, sourcePostId: attachment.postId)
            case .addToChurchNotes:
                try await AmenMediaGraphService.shared.addToChurchNotes(attachment, sourcePostId: attachment.postId)
            case .saveForLater:
                try await AmenMediaGraphService.shared.saveForLater(attachment, sourcePostId: attachment.postId)
            default:
                break
            }
        } catch {
            dlog("AmenSmartAttachment save action failed: \(error)")
        }
    }
}
