import SwiftUI

struct VaultNotesHomeView: View {
    private let collections = VaultNotesSampleData.collections
    private let notes = VaultNotesSampleData.contextNotes

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                collectionsSection
                notesSection
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("Knowledge Vault")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Knowledge Vault")
                .font(.title2.weight(.semibold))
            Text("Saved posts, sermons, podcasts, resources, notes, and events grouped into calm collections.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Collections")
                .font(.headline)

            ForEach(collections) { collection in
                SocialV2GlassCard(tintContext: .interactive) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: collection.systemImage)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(collection.title)
                                .font(.headline)
                            Text(collection.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(collection.itemCount) saved items")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context Notes")
                .font(.headline)

            ForEach(notes) { note in
                SocialV2GlassCard(tintContext: note.isDisplayable ? .state : .alert, isActive: note.isDisplayable) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title)
                            .font(.headline)
                        Text(note.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            SocialV2GlassPill(tintContext: note.isDisplayable ? .state : .alert, isSelected: true) {
                                Label(note.displayStatus, systemImage: note.isDisplayable ? "checkmark.seal" : "clock")
                            }
                            SocialV2GlassPill(tintContext: .neutral) {
                                Label(note.credibility.label, systemImage: "doc.text.magnifyingglass")
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct VaultCollection: Identifiable {
    let id: String
    let title: String
    let summary: String
    let itemCount: Int
    let systemImage: String
}

private struct VaultContextNote: Identifiable {
    let id: String
    let title: String
    let summary: String
    let moderationDecision: SocialV2ModerationDecision
    let credibility: ContentCredibility

    var isDisplayable: Bool {
        moderationDecision.isReadable && credibility != .unreviewed
    }

    var displayStatus: String {
        isDisplayable ? "Reviewed" : "Hidden Pending Review"
    }
}

private enum ContentCredibility {
    case sourceBacked
    case consensusSupported
    case needsMoreSources
    case unreviewed

    var label: String {
        switch self {
        case .sourceBacked:
            return "Source-backed"
        case .consensusSupported:
            return "Consensus-supported"
        case .needsMoreSources:
            return "Needs sources"
        case .unreviewed:
            return "Unreviewed"
        }
    }
}

private enum VaultNotesSampleData {
    static let collections = [
        VaultCollection(id: "leadership", title: "Leadership", summary: "Saved teaching and notes for team formation.", itemCount: 18, systemImage: "person.3"),
        VaultCollection(id: "parenting", title: "Parenting", summary: "Resources and discussions for family discipleship.", itemCount: 12, systemImage: "figure.2.and.child.holdinghands"),
        VaultCollection(id: "business", title: "Business", summary: "Ethical work, stewardship, and vocation.", itemCount: 9, systemImage: "briefcase")
    ]

    static let contextNotes = [
        VaultContextNote(
            id: "note-1",
            title: "Source added for quoted statistic",
            summary: "A context note can display because moderation and source validation both passed.",
            moderationDecision: SocialV2ModerationDecision(
                id: "vault-mod-1",
                status: .approved,
                policyReference: "context-note-source-quality",
                explanation: "Sources are relevant and non-abusive.",
                decidedAt: Date()
            ),
            credibility: .sourceBacked
        ),
        VaultContextNote(
            id: "note-2",
            title: "Correction pending",
            summary: "This note stays hidden until review completes.",
            moderationDecision: SocialV2ModerationDecision(
                id: "vault-mod-2",
                status: .pending,
                policyReference: "context-note-review",
                explanation: "Awaiting consensus and source validation.",
                decidedAt: Date()
            ),
            credibility: .unreviewed
        )
    ]
}
