import SwiftUI

struct AmenIntelligenceLayerShellView: View {
    @State private var selectedLane: AmenIntelligenceLane = .personalMemory
    @State private var selectedContext: AmenShellContextSummary.ID?
    @State private var previewAction: HumanPreviewAction?
    @State private var confirmedActionIDs: Set<String> = []

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trustBoundaryID = AmenTrustBoundaryID(rawValue: "lane-f-glass-shell")
    private let contextSummaries = AmenShellContextSummary.samples
    private let nudges = AmenShellBereanNudge.samples
    private let previewActions = AmenShellActionPreview.samples

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AmenTheme.Colors.backgroundPrimary
                    .ignoresSafeArea()

                mainContent
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 132)

                glassChrome
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            .navigationTitle("AMEN Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .animation(Motion.adaptive(Motion.appearEase), value: selectedLane)
            .sheet(item: $previewAction) { action in
                AmenShellActionConfirmationSheet(
                    action: action,
                    isConfirmed: confirmedActionIDs.contains(action.id),
                    onCancel: { previewAction = nil },
                    onConfirm: {
                        confirmedActionIDs.insert(action.id)
                        previewAction = nil
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }

    private var mainContent: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    laneWorkspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ambientBereanPanel
                        .frame(width: 340)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        laneWorkspace
                        ambientBereanPanel
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var laneWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            laneHeader
            laneBridge
            laneSurfacePlaceholder
        }
    }

    private var laneHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedLane.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AmenTheme.Colors.surfaceChip, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedLane.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text(selectedLane.roleDescription)
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                AmenShellProvenancePill(title: "Trust", value: trustBoundaryID.rawValue)
                AmenShellProvenancePill(title: "Surface", value: selectedLane.surface.rawValue)
            }
        }
    }

    private var laneBridge: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connective context")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            ForEach(contextSummaries.filter { $0.lanes.contains(selectedLane) }) { summary in
                Button {
                    withAnimation(Motion.adaptive(Motion.appearEase)) {
                        selectedContext = selectedContext == summary.id ? nil : summary.id
                    }
                } label: {
                    AmenShellContextRow(summary: summary, isExpanded: selectedContext == summary.id)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .amenShellMatteContent(cornerRadius: 14)
    }

    private var laneSurfacePlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedLane.destinationTypeName)
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Text(selectedLane.integrationNote)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label("Matte content", systemImage: "rectangle.inset.filled")
                Label("No private model call", systemImage: "lock.shield")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .amenShellMatteContent(cornerRadius: 14)
    }

    private var ambientBereanPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ambient Berean")
                        .font(.headline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("Contextual, cited, opt-in")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                Spacer()
            }

            Text(activeSummary)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ForEach(nudges.filter { $0.surface == selectedLane.surface || $0.surface == .glassShell }) { nudge in
                AmenShellNudgeRow(nudge: nudge)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Preview actions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                ForEach(previewActions.filter { $0.lane == selectedLane }) { item in
                    AmenShellPreviewActionRow(
                        item: item,
                        isConfirmed: confirmedActionIDs.contains(item.action.id),
                        onPreview: { previewAction = item.action }
                    )
                }
            }
        }
        .padding(16)
        .amenShellGlassChrome(cornerRadius: 24, interactive: true)
    }

    private var glassChrome: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AmenIntelligenceLane.allCases) { lane in
                        Button {
                            withAnimation(Motion.adaptive(Motion.popToggle)) {
                                selectedLane = lane
                                selectedContext = nil
                            }
                        } label: {
                            Label(lane.shortTitle, systemImage: lane.symbolName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedLane == lane ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textSecondary)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(selectedLane == lane ? AmenTheme.Colors.selectedFill : Color.clear, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedLane == lane ? .isSelected : [])
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 8) {
                Label("Provenance visible", systemImage: "checkmark.seal")
                Spacer(minLength: 8)
                Label("Preview before confirm", systemImage: "eye")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
        }
        .amenShellGlassChrome(cornerRadius: 28, interactive: true)
    }

    private var activeSummary: String {
        if let selectedContext, let summary = contextSummaries.first(where: { $0.id == selectedContext }) {
            return summary.detail
        }
        return selectedLane.ambientSummary
    }
}

private enum AmenIntelligenceLane: String, CaseIterable, Identifiable, Hashable {
    case personalMemory
    case relationship
    case creator
    case lifeNavigation
    case collaborative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personalMemory: "Personal Memory OS"
        case .relationship: "Relationship OS"
        case .creator: "Creator OS"
        case .lifeNavigation: "Life Navigation OS"
        case .collaborative: "Collaborative Intelligence"
        }
    }

    var shortTitle: String {
        switch self {
        case .personalMemory: "Memory"
        case .relationship: "People"
        case .creator: "Creator"
        case .lifeNavigation: "Life"
        case .collaborative: "Shared"
        }
    }

    var symbolName: String {
        switch self {
        case .personalMemory: "brain.head.profile"
        case .relationship: "person.2"
        case .creator: "wand.and.sparkles"
        case .lifeNavigation: "location.north.line"
        case .collaborative: "doc.text.magnifyingglass"
        }
    }

    var surface: AmenIntelligenceSurface {
        switch self {
        case .personalMemory: .personalMemory
        case .relationship: .relationship
        case .creator: .creatorSpace
        case .lifeNavigation: .lifeNavigation
        case .collaborative: .collaborativeDocument
        }
    }

    var destinationTypeName: String {
        switch self {
        case .personalMemory: "AmenPersonalMemoryOSView"
        case .relationship: "AmenRelationshipOSView"
        case .creator: "AmenCreatorOSView"
        case .lifeNavigation: "AmenLifeNavigationOSView"
        case .collaborative: "AmenCollaborativeIntelligenceView"
        }
    }

    var roleDescription: String {
        switch self {
        case .personalMemory: "Recall personal notes, decisions, and remembered claims with four-layer provenance."
        case .relationship: "Keep relational context present without auto-sending messages or creating edges."
        case .creator: "Surface creator-space health and source-aware content preparation."
        case .lifeNavigation: "Hold travel, calendar, and decision context in one confirmable surface."
        case .collaborative: "Coordinate shared documents, decision trails, and source packets."
        }
    }

    var ambientSummary: String {
        switch self {
        case .personalMemory: "Berean is watching for duplicate thoughts, source gaps, and useful recall, but waits for preview before writing memory."
        case .relationship: "Berean can suggest follow-up language and relationship context; sending remains explicit."
        case .creator: "Berean summarizes creator-space signals and flags source verification needs before publishing."
        case .lifeNavigation: "Berean can raise travel and reminder nudges from visible context; starting navigation requires confirmation."
        case .collaborative: "Berean links shared notes to cited claims and shows proposed document changes as previews."
        }
    }

    var integrationNote: String {
        "Lane F shell reserves this matte area for \(destinationTypeName) while keeping Liquid Glass on chrome and ambient controls only."
    }
}

private struct AmenShellContextSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let citedClaimIDs: [String]
    let lanes: Set<AmenIntelligenceLane>

    static let samples: [AmenShellContextSummary] = [
        AmenShellContextSummary(
            id: "decision-trail",
            title: "Decision trail linked to current notes",
            detail: "Three recent notes and one shared draft point to the same decision trail. Berean should cite the remembered claim before proposing a merge.",
            citedClaimIDs: ["claim_decision_184", "claim_note_552"],
            lanes: [.personalMemory, .collaborative]
        ),
        AmenShellContextSummary(
            id: "relationship-follow-up",
            title: "Follow-up context is available",
            detail: "A recent conversation contains an unanswered question and a possible reminder candidate. No message will be drafted or sent without preview.",
            citedClaimIDs: ["claim_conversation_088"],
            lanes: [.relationship, .personalMemory]
        ),
        AmenShellContextSummary(
            id: "creator-source",
            title: "Creator source packet needs review",
            detail: "The creator lane has a source packet with partial verification. Berean should keep the unsupported claim visible until a human confirms the source.",
            citedClaimIDs: ["claim_source_315", "claim_packet_041"],
            lanes: [.creator, .collaborative]
        ),
        AmenShellContextSummary(
            id: "travel-prep",
            title: "Calendar and place context aligned",
            detail: "Life navigation has an event and place node ready for a leave-now nudge. Navigation starts only after explicit confirmation.",
            citedClaimIDs: ["claim_event_207"],
            lanes: [.lifeNavigation, .relationship]
        )
    ]
}

private struct AmenShellBereanNudge: Identifiable, Hashable {
    let id: String
    let surface: AmenIntelligenceSurface
    let kind: DetectedNeedKind
    let explanation: String
    let provenance: ProvenanceChain

    static let samples: [AmenShellBereanNudge] = [
        AmenShellBereanNudge(id: "shell-source", surface: .glassShell, kind: .sourceVerificationNeeded, explanation: "Keep source status visible before accepting suggested changes.", provenance: .shellSample(claimID: "claim_shell_001", confidence: 0.74)),
        AmenShellBereanNudge(id: "memory-duplicate", surface: .personalMemory, kind: .duplicateThought, explanation: "A similar note already exists in personal memory.", provenance: .shellSample(claimID: "claim_note_552", confidence: 0.81)),
        AmenShellBereanNudge(id: "relationship-question", surface: .relationship, kind: .unansweredQuestion, explanation: "A question in the last thread has not been answered.", provenance: .shellSample(claimID: "claim_conversation_088", confidence: 0.78)),
        AmenShellBereanNudge(id: "creator-verify", surface: .creatorSpace, kind: .sourceVerificationNeeded, explanation: "One creator claim has partial source support.", provenance: .shellSample(claimID: "claim_source_315", confidence: 0.69)),
        AmenShellBereanNudge(id: "life-leave", surface: .lifeNavigation, kind: .leaveNowTravelNudge, explanation: "Calendar and place context support a leave-now preview.", provenance: .shellSample(claimID: "claim_event_207", confidence: 0.84)),
        AmenShellBereanNudge(id: "shared-edge", surface: .collaborativeDocument, kind: .duplicateThought, explanation: "Two shared notes may belong to the same decision trail.", provenance: .shellSample(claimID: "claim_decision_184", confidence: 0.76))
    ]
}

private struct AmenShellActionPreview: Identifiable, Hashable {
    let id: String
    let lane: AmenIntelligenceLane
    let action: HumanPreviewAction

    static let samples: [AmenShellActionPreview] = [
        AmenShellActionPreview(id: "memory-merge", lane: .personalMemory, action: HumanPreviewAction(id: "action_memory_merge", kind: .mergeNotes, title: "Preview note merge", diffPreview: "Merge duplicate thought into Personal Memory with claim_note_552 retained as cited provenance.", targetNodeID: ContextGraphNodeID(rawValue: "node_note_552"), requiresExplicitConfirmation: true)),
        AmenShellActionPreview(id: "relationship-send", lane: .relationship, action: HumanPreviewAction(id: "action_relationship_reply", kind: .sendMessage, title: "Preview follow-up", diffPreview: "Draft a short reply that answers the open question. Nothing sends until Confirm is tapped.", targetNodeID: ContextGraphNodeID(rawValue: "node_conversation_088"), requiresExplicitConfirmation: true)),
        AmenShellActionPreview(id: "creator-verify", lane: .creator, action: HumanPreviewAction(id: "action_creator_verify", kind: .postToSpace, title: "Preview creator update", diffPreview: "Add source caveat to the creator draft and keep unsupported claim flagged.", targetNodeID: ContextGraphNodeID(rawValue: "node_source_315"), requiresExplicitConfirmation: true)),
        AmenShellActionPreview(id: "life-nav", lane: .lifeNavigation, action: HumanPreviewAction(id: "action_life_navigation", kind: .startNavigation, title: "Preview navigation", diffPreview: "Open navigation for the calendar event location after confirmation.", targetNodeID: ContextGraphNodeID(rawValue: "node_event_207"), requiresExplicitConfirmation: true)),
        AmenShellActionPreview(id: "shared-edge", lane: .collaborative, action: HumanPreviewAction(id: "action_shared_edge", kind: .createContextEdge, title: "Preview context edge", diffPreview: "Create a proposed relatedTo edge between shared notes. Human confirmation is required before writing.", targetNodeID: ContextGraphNodeID(rawValue: "node_decision_184"), requiresExplicitConfirmation: true))
    ]
}

private struct AmenShellContextRow: View {
    let summary: AmenShellContextSummary
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            if isExpanded {
                Text(summary.detail)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                AmenShellClaimList(claimIDs: summary.citedClaimIDs)
            }
        }
        .padding(12)
        .background(AmenTheme.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        }
    }
}

private struct AmenShellNudgeRow: View {
    let nudge: AmenShellBereanNudge

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(nudge.kind.rawValue.shellTitleCased)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                Text("\(Int(nudge.provenance.retrievalConfidence * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }

            Text(nudge.explanation)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AmenShellProvenanceLine(provenance: nudge.provenance)
        }
        .padding(10)
        .background(AmenTheme.Colors.surfaceCard.opacity(0.76), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AmenShellPreviewActionRow: View {
    let item: AmenShellActionPreview
    let isConfirmed: Bool
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isConfirmed ? "checkmark.circle.fill" : "eye")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .frame(width: 28, height: 28)
                .background(AmenTheme.Colors.surfaceChip, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.action.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(isConfirmed ? "Confirmed" : "Requires preview")
                    .font(.caption2)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Spacer()

            Button(isConfirmed ? "Done" : "Preview", action: onPreview)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(isConfirmed)
        }
    }
}

private struct AmenShellActionConfirmationSheet: View {
    let action: HumanPreviewAction
    let isConfirmed: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(AmenTheme.Colors.borderSoft)
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(action.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(action.kind.rawValue.shellTitleCased)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Text(action.diffPreview)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .amenShellMatteContent(cornerRadius: 12)

            AmenShellProvenancePill(title: "Target node", value: action.targetNodeID.rawValue)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button(isConfirmed ? "Confirmed" : "Confirm") {
                    guard action.requiresExplicitConfirmation else { return }
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConfirmed)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .amenShellGlassChrome(cornerRadius: 24, interactive: true)
        .padding(12)
    }
}

private struct AmenShellClaimList: View {
    let claimIDs: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(claimIDs, id: \.self) { claimID in
                Text(claimID)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AmenTheme.Colors.surfaceChip, in: Capsule(style: .continuous))
            }
        }
    }
}

private struct AmenShellProvenancePill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AmenTheme.Colors.surfaceChip, in: Capsule(style: .continuous))
    }
}

private struct AmenShellProvenanceLine: View {
    let provenance: ProvenanceChain

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: provenance.isComplete ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.caption2.weight(.semibold))
            Text(provenance.claimID)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(provenance.isComplete ? "complete" : "incomplete")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(AmenTheme.Colors.textTertiary)
    }
}

private struct AmenShellMatteContentModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            }
    }
}

private struct AmenShellGlassChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceElevated)
                } else if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: .rect(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: contrast == .increased ? 1.1 : 0.7)
            }
            .shadow(color: AmenTheme.Colors.shadowCard, radius: 18, x: 0, y: 10)
    }
}

private extension View {
    func amenShellMatteContent(cornerRadius: CGFloat) -> some View {
        modifier(AmenShellMatteContentModifier(cornerRadius: cornerRadius))
    }

    func amenShellGlassChrome(cornerRadius: CGFloat, interactive: Bool) -> some View {
        modifier(AmenShellGlassChromeModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

private extension ProvenanceChain {
    static func shellSample(claimID: String, confidence: Double) -> ProvenanceChain {
        ProvenanceChain(
            claimID: claimID,
            layers: FourLayerProvenance(
                originalSource: ProvenanceOriginalSource(
                    sourceID: "source_\(claimID)",
                    sourceKind: .humanNote,
                    title: "Lane F visible context",
                    authorNodeID: ContextGraphNodeID(rawValue: "node_shell_author"),
                    sourceURL: nil,
                    sourceTimestamp: Date()
                ),
                captureRecord: ProvenanceCaptureRecord(
                    capturedByUserID: "lane-f-preview",
                    capturedAt: Date(),
                    deviceID: nil,
                    appVersion: nil,
                    trustBoundaryID: AmenTrustBoundaryID(rawValue: "lane-f-glass-shell")
                ),
                processingRecord: ProvenanceProcessingRecord(
                    processor: .deterministicParser,
                    callableProxyName: nil,
                    modelName: nil,
                    transform: .contextLinking,
                    processedAt: Date(),
                    humanReviewed: false
                ),
                retrievalRecord: ProvenanceRetrievalRecord(
                    retrievedAt: Date(),
                    queryID: "lane-f-shell-preview",
                    namespace: PineconeNamespace.personal(userID: "lane-f-preview"),
                    rankingSignals: [MemoryRankingSignal(name: "visibleContext", weight: 1, value: "shell")],
                    confidence: confidence
                )
            ),
            generatedAt: Date()
        )
    }

    var retrievalConfidence: Double {
        layers.retrievalRecord?.confidence ?? 0
    }
}

private extension String {
    var shellTitleCased: String {
        reduce("") { partialResult, character in
            if character.isUppercase {
                return partialResult + " " + String(character)
            }
            return partialResult + String(character)
        }
        .trimmingCharacters(in: .whitespaces)
        .capitalized
    }
}

#Preview {
    AmenIntelligenceLayerShellView()
}
