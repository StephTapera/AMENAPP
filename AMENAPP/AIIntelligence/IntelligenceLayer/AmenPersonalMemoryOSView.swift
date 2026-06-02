import SwiftUI

struct AmenPersonalMemoryOSView: View {
    @State private var selectedSection: MemorySection = .notebooks
    @State private var selectedAction: HumanPreviewAction?
    @State private var confirmedActionIDs: Set<String> = []
    @State private var livingDocumentSuggestionsEnabled = false
    @State private var expandedProvenanceIDs: Set<String> = []

    private let notebooks = PersonalMemorySeed.notebooks
    private let thoughtConnections = PersonalMemorySeed.thoughtConnections
    private let relationshipNotes = PersonalMemorySeed.relationshipNotes
    private let livingDocumentActions = PersonalMemorySeed.livingDocumentActions

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AmenTheme.Colors.backgroundGrouped
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerChrome
                        sectionChrome

                        switch selectedSection {
                        case .notebooks:
                            notebooksSection
                        case .connections:
                            thoughtConnectionsSection
                        case .documents:
                            livingDocumentsSection
                        case .relationships:
                            relationshipNotesSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, selectedAction == nil ? 24 : 190)
                }

                if let selectedAction {
                    ActionConfirmationPreview(
                        action: selectedAction,
                        isConfirmed: confirmedActionIDs.contains(selectedAction.id),
                        onConfirm: {
                            withAnimation(Motion.adaptive(Motion.springRelease)) {
                                _ = confirmedActionIDs.insert(selectedAction.id)
                            }
                        },
                        onDismiss: {
                            withAnimation(Motion.adaptive(Motion.appearEase)) {
                                self.selectedAction = nil
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Personal Memory")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var headerChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .frame(width: 38, height: 38)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Berean Notebooks")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("Living Memory organized by context, people, documents, and source-backed connections.")
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                ContractBadge(title: AmenIntelligenceSurface.personalMemory.rawValue, icon: "person.crop.circle.badge.checkmark")
                ContractBadge(title: "linkThoughts", icon: "point.3.connected.trianglepath.dotted")
            }
        }
        .padding(16)
        .glassChrome(cornerRadius: 24)
    }

    private var sectionChrome: some View {
        HStack(spacing: 6) {
            ForEach(MemorySection.allCases) { section in
                Button {
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        selectedSection = section
                    }
                } label: {
                    Image(systemName: section.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedSection == section ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            selectedSection == section ? AmenTheme.Colors.surfaceCard : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .padding(6)
        .glassChrome(cornerRadius: 20)
        .animation(Motion.adaptive(Motion.appearEase), value: selectedSection)
    }

    private var notebooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Living Memory", subtitle: "Auto organization only. No manual folders or vanity counters.")

            ForEach(notebooks) { notebook in
                NotebookCard(
                    notebook: notebook,
                    isProvenanceExpanded: expandedProvenanceIDs.contains(notebook.id),
                    onToggleProvenance: { toggleProvenance(notebook.id) },
                    onPreviewAction: { selectedAction = notebook.previewAction }
                )
            }
        }
    }

    private var thoughtConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Thought Connections", subtitle: "Proposed context graph edges stay pending until you confirm them.")

            ForEach(thoughtConnections) { connection in
                ConnectionCard(
                    connection: connection,
                    isProvenanceExpanded: expandedProvenanceIDs.contains(connection.id),
                    onToggleProvenance: { toggleProvenance(connection.id) },
                    onPreviewAction: { selectedAction = connection.previewAction }
                )
            }
        }
    }

    private var livingDocumentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Living Documents", subtitle: "Suggestions are opt-in and previewed before any document change.")

            HStack(spacing: 12) {
                Image(systemName: livingDocumentSuggestionsEnabled ? "checkmark.shield.fill" : "shield")
                    .foregroundStyle(livingDocumentSuggestionsEnabled ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textSecondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Opt in to document suggestions")
                        .font(.headline)
                    Text("When off, document memory is read-only on this surface.")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $livingDocumentSuggestionsEnabled)
                    .labelsHidden()
                    .tint(AmenTheme.Colors.amenGold)
                    .onChange(of: livingDocumentSuggestionsEnabled) { _ in
                        withAnimation(Motion.adaptive(Motion.springRelease)) {}
                    }
            }
            .padding(14)
            .matteContent(cornerRadius: 16)

            ForEach(livingDocumentActions) { suggestion in
                LivingDocumentSuggestionCard(
                    suggestion: suggestion,
                    isEnabled: livingDocumentSuggestionsEnabled,
                    isProvenanceExpanded: expandedProvenanceIDs.contains(suggestion.id),
                    onToggleProvenance: { toggleProvenance(suggestion.id) },
                    onPreviewAction: { selectedAction = suggestion.previewAction }
                )
            }
        }
    }

    private var relationshipNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Relationship Notes", subtitle: "People memory remains private unless an explicit preview says otherwise.")

            ForEach(relationshipNotes) { note in
                RelationshipNoteCard(
                    note: note,
                    isProvenanceExpanded: expandedProvenanceIDs.contains(note.id),
                    onToggleProvenance: { toggleProvenance(note.id) },
                    onPreviewAction: { selectedAction = note.previewAction }
                )
            }
        }
    }

    private func toggleProvenance(_ id: String) {
        withAnimation(Motion.adaptive(Motion.appearEase)) {
            if expandedProvenanceIDs.contains(id) {
                expandedProvenanceIDs.remove(id)
            } else {
                expandedProvenanceIDs.insert(id)
            }
        }
    }
}

private enum MemorySection: String, CaseIterable, Identifiable {
    case notebooks
    case connections
    case documents
    case relationships

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notebooks: "Notebooks"
        case .connections: "Connections"
        case .documents: "Documents"
        case .relationships: "Relationships"
        }
    }

    var systemImage: String {
        switch self {
        case .notebooks: "books.vertical"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .documents: "doc.text.magnifyingglass"
        case .relationships: "person.2.wave.2"
        }
    }
}

private struct PersonalNotebook: Identifiable, Hashable {
    let id: String
    let title: String
    let autoContext: String
    let claim: String
    let noteKind: NoteNotebookHint
    let nodeKind: ContextGraphNodeKind
    let provenance: ProvenanceSummary
    let previewAction: HumanPreviewAction
}

private struct ThoughtConnection: Identifiable, Hashable {
    let id: String
    let sourceTitle: String
    let targetTitle: String
    let claim: String
    let edgeKind: ContextGraphEdgeKind
    let provenance: ProvenanceSummary
    let previewAction: HumanPreviewAction
}

private struct LivingDocumentSuggestion: Identifiable, Hashable {
    let id: String
    let documentTitle: String
    let claim: String
    let documentKind: DocumentNodeKind
    let provenance: ProvenanceSummary
    let previewAction: HumanPreviewAction
}

private struct RelationshipNote: Identifiable, Hashable {
    let id: String
    let personName: String
    let claim: String
    let labels: [String]
    let provenance: ProvenanceSummary
    let previewAction: HumanPreviewAction
}

private struct ProvenanceSummary: Hashable {
    let claimID: String
    let sourceTitle: String
    let sourceKind: ProvenanceSourceKind
    let capture: String
    let processing: IntelligenceProcessorKind
    let transform: ProvenanceTransformKind
    let retrievalNamespace: PineconeNamespace
    let confidence: Double
    let reviewed: Bool

    var statusText: String {
        reviewed ? "Human reviewed" : "Needs review"
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

private struct NotebookCard: View {
    let notebook: PersonalNotebook
    let isProvenanceExpanded: Bool
    let onToggleProvenance: () -> Void
    let onPreviewAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "books.vertical", title: notebook.title, detail: "Auto: \(notebook.noteKind.rawValue) / \(notebook.nodeKind.rawValue)")
            AIClaimText(text: notebook.claim)
            ProvenanceDisclosure(provenance: notebook.provenance, isExpanded: isProvenanceExpanded, onToggle: onToggleProvenance)
            PreviewButton(title: notebook.previewAction.title, action: onPreviewAction)
        }
        .padding(14)
        .matteContent(cornerRadius: 16)
    }
}

private struct ConnectionCard: View {
    let connection: ThoughtConnection
    let isProvenanceExpanded: Bool
    let onToggleProvenance: () -> Void
    let onPreviewAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "point.3.connected.trianglepath.dotted", title: connection.sourceTitle, detail: "\(connection.edgeKind.rawValue) -> \(connection.targetTitle)")
            AIClaimText(text: connection.claim)
            ProvenanceDisclosure(provenance: connection.provenance, isExpanded: isProvenanceExpanded, onToggle: onToggleProvenance)
            PreviewButton(title: connection.previewAction.title, action: onPreviewAction)
        }
        .padding(14)
        .matteContent(cornerRadius: 16)
    }
}

private struct LivingDocumentSuggestionCard: View {
    let suggestion: LivingDocumentSuggestion
    let isEnabled: Bool
    let isProvenanceExpanded: Bool
    let onToggleProvenance: () -> Void
    let onPreviewAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "doc.text", title: suggestion.documentTitle, detail: "Document: \(suggestion.documentKind.rawValue)")
            AIClaimText(text: suggestion.claim)
            ProvenanceDisclosure(provenance: suggestion.provenance, isExpanded: isProvenanceExpanded, onToggle: onToggleProvenance)
            PreviewButton(title: suggestion.previewAction.title, isEnabled: isEnabled, action: onPreviewAction)
        }
        .padding(14)
        .matteContent(cornerRadius: 16)
        .opacity(isEnabled ? 1 : 0.62)
    }
}

private struct RelationshipNoteCard: View {
    let note: RelationshipNote
    let isProvenanceExpanded: Bool
    let onToggleProvenance: () -> Void
    let onPreviewAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "person.crop.circle", title: note.personName, detail: note.labels.joined(separator: " / "))
            AIClaimText(text: note.claim)
            ProvenanceDisclosure(provenance: note.provenance, isExpanded: isProvenanceExpanded, onToggle: onToggleProvenance)
            PreviewButton(title: note.previewAction.title, action: onPreviewAction)
        }
        .padding(14)
        .matteContent(cornerRadius: 16)
    }
}

private struct CardHeader: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .frame(width: 28, height: 28)
                .background(AmenTheme.Colors.surfaceChip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AIClaimText: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.amenPurple)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(AmenTheme.Colors.surfaceInput, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI claim. \(text)")
    }
}

private struct ProvenanceDisclosure: View {
    let provenance: ProvenanceSummary
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: provenance.reviewed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(provenance.reviewed ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.amenGold)
                    Text("Provenance: \(provenance.sourceTitle)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ProvenanceRow(label: "Claim", value: provenance.claimID)
                    ProvenanceRow(label: "Original", value: "\(provenance.sourceKind.rawValue) - \(provenance.sourceTitle)")
                    ProvenanceRow(label: "Capture", value: provenance.capture)
                    ProvenanceRow(label: "Processing", value: "\(provenance.processing.rawValue) / \(provenance.transform.rawValue) / \(provenance.statusText)")
                    ProvenanceRow(label: "Retrieval", value: "\(provenance.retrievalNamespace.rawValue), confidence \(Int(provenance.confidence * 100))%")
                }
                .padding(10)
                .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct ProvenanceRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PreviewButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityHint("Opens a preview before confirmation.")
    }
}

private struct ActionConfirmationPreview: View {
    let action: HumanPreviewAction
    let isConfirmed: Bool
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isConfirmed ? "checkmark.circle.fill" : "hand.tap")
                    .font(.headline)
                    .foregroundStyle(isConfirmed ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.amenGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline)
                    Text(action.requiresExplicitConfirmation ? "Preview required before write" : "Preview available")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(AmenTheme.Colors.surfaceChip, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text(action.diffPreview)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                Button(isConfirmed ? "Confirmed" : "Confirm") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConfirmed)
            }
        }
        .padding(14)
        .glassChrome(cornerRadius: 22)
    }
}

private struct ContractBadge: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AmenTheme.Colors.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(AmenTheme.Colors.surfaceCard, in: Capsule(style: .continuous))
    }
}

private extension View {
    func matteContent(cornerRadius: CGFloat) -> some View {
        background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            }
    }

    func glassChrome(cornerRadius: CGFloat) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

private enum PersonalMemorySeed {
    static let userID = "lane-a-user"
    static let trustBoundaryID = AmenTrustBoundaryID(rawValue: "private-user-memory")
    static let namespace = PineconeNamespace.personal(userID: userID)

    static let notebooks: [PersonalNotebook] = [
        PersonalNotebook(
            id: "notebook-sabbath",
            title: "Sabbath prep",
            autoContext: "journal",
            claim: "Berean found a repeated planning thread around Sunday hospitality, menu notes, and prayer prompts.",
            noteKind: .journal,
            nodeKind: .note,
            provenance: provenance("claim-sabbath", source: "Saturday reflection", kind: .humanNote, transform: .summary, confidence: 0.86, reviewed: true),
            previewAction: action("action-merge-sabbath", kind: .mergeNotes, title: "Preview notebook merge", diff: "+ Merge three related notes into Living Memory: Sabbath prep\n+ Preserve originals and source chain\n+ Add auto tags: hospitality, prayer, recipe")
        ),
        PersonalNotebook(
            id: "notebook-work",
            title: "Work decision trail",
            autoContext: "meeting",
            claim: "Berean grouped meeting notes with a decision trail about launch responsibilities and follow-up timing.",
            noteKind: .meeting,
            nodeKind: .document,
            provenance: provenance("claim-work-decision", source: "Launch sync notes", kind: .document, transform: .contextLinking, confidence: 0.79, reviewed: false),
            previewAction: action("action-create-decision-edge", kind: .createContextEdge, title: "Preview decision links", diff: "+ Link launch sync notes to decision trail\n+ Mark as pending human confirmation\n+ Keep workspace boundary private")
        )
    ]

    static let thoughtConnections: [ThoughtConnection] = [
        ThoughtConnection(
            id: "connection-prayer-hospitality",
            sourceTitle: "Prayer prompt",
            targetTitle: "Sunday hospitality",
            claim: "These thoughts appear related because both mention welcoming a new family and preparing follow-up care.",
            edgeKind: .relatedTo,
            provenance: provenance("claim-link-prayer-hospitality", source: "Prayer prompt", kind: .humanNote, transform: .contextLinking, confidence: 0.82, reviewed: false),
            previewAction: action("action-link-prayer-hospitality", kind: .createContextEdge, title: "Preview thought connection", diff: "+ Create pending ContextGraphEdge.relatedTo\n+ Source: Prayer prompt\n+ Target: Sunday hospitality\n+ Requires explicit confirmation")
        ),
        ThoughtConnection(
            id: "connection-recipe-event",
            sourceTitle: "Recipe note",
            targetTitle: "Community dinner",
            claim: "The recipe note likely belongs with the community dinner event because the serving count and date align.",
            edgeKind: .scheduledFor,
            provenance: provenance("claim-link-recipe-event", source: "Recipe note", kind: .humanNote, transform: .contextLinking, confidence: 0.74, reviewed: false),
            previewAction: action("action-link-recipe-event", kind: .createContextEdge, title: "Preview event link", diff: "+ Link recipe note to Community dinner\n+ Keep recipe private to user\n+ Do not share without a later preview")
        )
    ]

    static let livingDocumentActions: [LivingDocumentSuggestion] = [
        LivingDocumentSuggestion(
            id: "doc-lesson-plan",
            documentTitle: "Small group lesson plan",
            claim: "Berean can suggest inserting a short unanswered-question section from recent group notes.",
            documentKind: .lessonPlan,
            provenance: provenance("claim-doc-lesson", source: "Group note packet", kind: .document, transform: .summary, confidence: 0.81, reviewed: false),
            previewAction: action("action-doc-lesson", kind: .shareDocument, title: "Preview document suggestion", diff: "+ Add section: Questions to revisit\n+ Cite source note packet\n+ Keep suggestion as draft until confirmed")
        )
    ]

    static let relationshipNotes: [RelationshipNote] = [
        RelationshipNote(
            id: "relationship-maya",
            personName: "Maya Johnson",
            claim: "Maya mentioned preferring text follow-ups after evening meetings; this note should stay private to the user.",
            labels: ["mentor", "follow-up preference"],
            provenance: provenance("claim-maya-followup", source: "Evening meeting note", kind: .conversationMessage, transform: .summary, confidence: 0.88, reviewed: true),
            previewAction: action("action-maya-reminder", kind: .scheduleReminder, title: "Preview private reminder", diff: "+ Schedule private reminder: text Maya tomorrow afternoon\n+ No message will be sent automatically\n+ Provenance remains attached")
        ),
        RelationshipNote(
            id: "relationship-daniel",
            personName: "Daniel Reyes",
            claim: "Daniel may be a useful mentor candidate for a new member based on shared ministry interests.",
            labels: ["potential mentor", "music team"],
            provenance: provenance("claim-daniel-mentor", source: "Connect conversation", kind: .conversationMessage, transform: .contextLinking, confidence: 0.68, reviewed: false),
            previewAction: action("action-daniel-note", kind: .createContextEdge, title: "Preview relationship note", diff: "+ Add pending relationship note\n+ Do not notify Daniel or the new member\n+ Ask for human confirmation before surfacing elsewhere")
        )
    ]

    static func provenance(_ claimID: String, source: String, kind: ProvenanceSourceKind, transform: ProvenanceTransformKind, confidence: Double, reviewed: Bool) -> ProvenanceSummary {
        ProvenanceSummary(
            claimID: claimID,
            sourceTitle: source,
            sourceKind: kind,
            capture: "Captured in trust boundary \(trustBoundaryID.rawValue)",
            processing: .deterministicParser,
            transform: transform,
            retrievalNamespace: namespace,
            confidence: confidence,
            reviewed: reviewed
        )
    }

    static func action(_ id: String, kind: HumanPreviewActionKind, title: String, diff: String) -> HumanPreviewAction {
        HumanPreviewAction(
            id: id,
            kind: kind,
            title: title,
            diffPreview: diff,
            targetNodeID: ContextGraphNodeID(rawValue: "target-\(id)"),
            requiresExplicitConfirmation: true
        )
    }
}

#Preview {
    AmenPersonalMemoryOSView()
}
