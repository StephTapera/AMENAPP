import SwiftUI

struct AmenRelationshipOSView: View {
    @State private var selectedThreadID = AmenRelationshipOSSampleData.threads.first?.id ?? ""
    @State private var composerText = ""
    @State private var isContextBeforeReplyVisible = true
    @State private var isDrivingModeEnabled = false
    @State private var selectedPreviewAction: HumanPreviewAction?
    @State private var confirmedActionIDs: Set<String> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let threads = AmenRelationshipOSSampleData.threads
    private let familySignals = AmenRelationshipOSSampleData.familySignals
    private let drivingBrief = AmenRelationshipOSSampleData.drivingBrief

    private var selectedThread: AmenRelationshipThread {
        threads.first { $0.id == selectedThreadID } ?? threads[0]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AmenTheme.Colors.backgroundPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        relationshipChrome

                        if isDrivingModeEnabled {
                            drivingModePanel
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        threadPicker
                        conversationMemoryRecall
                        smartFollowUpDetection
                        familyIntelligence

                        if isContextBeforeReplyVisible {
                            contextBeforeReplyPanel
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }

                        replyComposer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Relationship OS")
            .navigationBarTitleDisplayMode(.inline)
            .animation(Motion.adaptive(Motion.appearEase), value: isContextBeforeReplyVisible)
            .animation(Motion.adaptive(Motion.appearEase), value: isDrivingModeEnabled)
            .sheet(item: $selectedPreviewAction) { action in
                AmenRelationshipActionPreviewSheet(
                    action: action,
                    isConfirmed: confirmedActionIDs.contains(action.id),
                    onCancel: { selectedPreviewAction = nil },
                    onConfirm: {
                        confirmedActionIDs.insert(action.id)
                        selectedPreviewAction = nil
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }

    private var relationshipChrome: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lane B")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text("Reply with context")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }

            Spacer()

            Button {
                withAnimation(Motion.adaptive(Motion.popToggle)) {
                    isContextBeforeReplyVisible.toggle()
                }
            } label: {
                Image(systemName: isContextBeforeReplyVisible ? "rectangle.stack.fill" : "rectangle.stack")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Context Before Reply")

            Button {
                withAnimation(Motion.adaptive(Motion.popToggle)) {
                    isDrivingModeEnabled.toggle()
                }
            } label: {
                Image(systemName: isDrivingModeEnabled ? "car.fill" : "car")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Driving Mode")
        }
        .padding(12)
        .amenRelationshipGlassChrome(cornerRadius: 24)
    }

    private var threadPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active conversations")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(threads) { thread in
                        Button {
                            withAnimation(Motion.adaptive(Motion.appearEase)) {
                                selectedThreadID = thread.id
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(thread.personName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                                Text(thread.relationshipLabel)
                                    .font(.caption)
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.seal.fill")
                                    Text(thread.trustBoundaryID.rawValue)
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                            }
                            .frame(width: 164, alignment: .leading)
                            .padding(12)
                            .background(selectedThread.id == thread.id ? AmenTheme.Colors.selectedFill : AmenTheme.Colors.surfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var conversationMemoryRecall: some View {
        AmenRelationshipSectionCard(title: "Conversation Memory Recall", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedThread.recallQuery)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                ForEach(selectedThread.memoryResults) { result in
                    AmenMemoryRecallRow(result: result)
                }
            }
        }
    }

    private var smartFollowUpDetection: some View {
        AmenRelationshipSectionCard(title: "Smart Follow-up Detection", systemImage: "bell.badge") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(selectedThread.detectedNeeds) { need in
                    AmenDetectedNeedRow(need: need) { action in
                        selectedPreviewAction = action
                    }
                }
            }
        }
    }

    private var familyIntelligence: some View {
        AmenRelationshipSectionCard(title: "Family Intelligence", systemImage: "figure.2.and.child.holdinghands") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(familySignals) { signal in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: signal.systemImage)
                            .foregroundStyle(AmenTheme.Colors.iconSecondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(signal.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                            Text(signal.detail)
                                .font(.footnote)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                            AmenProvenanceLine(provenance: signal.provenance)
                        }
                    }
                }
            }
        }
    }

    private var contextBeforeReplyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                Text("Context Before Reply")
                    .font(.headline)
                Spacer()
                Text("Preview only")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Text(selectedThread.contextBeforeReply.summary)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(selectedThread.contextBeforeReply.claims) { claim in
                    AmenContextClaimRow(claim: claim)
                }
            }

            HStack(spacing: 10) {
                ForEach(selectedThread.contextBeforeReply.actions) { action in
                    Button {
                        selectedPreviewAction = action
                    } label: {
                        Label(action.title, systemImage: action.kind.systemImage)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .amenRelationshipGlassChrome(cornerRadius: 22)
    }

    private var replyComposer: some View {
        AmenRelationshipSectionCard(title: "Reply Draft", systemImage: "square.and.pencil") {
            VStack(alignment: .leading, spacing: 12) {
                if isDrivingModeEnabled {
                    Text("Typing is unavailable in Driving Mode. Use voice, Berean, or navigation controls only.")
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                } else {
                    TextEditor(text: $composerText)
                        .frame(minHeight: 96)
                        .padding(8)
                        .background(AmenTheme.Colors.surfaceInput, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if composerText.isEmpty {
                                Text("Draft a reply after reviewing the context and provenance.")
                                    .font(.subheadline)
                                    .foregroundStyle(AmenTheme.Colors.textPlaceholder)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                HStack(spacing: 10) {
                    ForEach(selectedThread.composerActions) { action in
                        if action.kind == .sendMessage {
                            Button {
                                selectedPreviewAction = action
                            } label: {
                                Label(action.kind.shortTitle, systemImage: action.kind.systemImage)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                selectedPreviewAction = action
                            } label: {
                                Label(action.kind.shortTitle, systemImage: action.kind.systemImage)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var drivingModePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "car.front.waves.up.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driving Mode")
                        .font(.headline)
                    Text("Voice, Berean, and navigation only")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                Spacer()
            }

            Text(drivingBrief.voiceBrief)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            HStack(spacing: 10) {
                Button { } label: {
                    Label("Voice", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)

                Button { } label: {
                    Label("Berean", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)

                Button {
                    selectedPreviewAction = drivingBrief.navigationAction
                } label: {
                    Label("Navigate", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)
            }

            AmenProvenanceLine(provenance: drivingBrief.provenance)
        }
        .padding(14)
        .amenRelationshipGlassChrome(cornerRadius: 22)
    }
}

private struct AmenRelationshipSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            content()
        }
        .padding(14)
        .amenIntelligenceMatteContent(cornerRadius: 12)
    }
}

private struct AmenMemoryRecallRow: View {
    let result: MemoryRecallResult

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(result.memory.claimText)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            HStack(spacing: 8) {
                Text(result.memory.tags.joined(separator: " · "))
                Text("Relevance \(Int(result.relevanceScore * 100))%")
            }
            .font(.caption)
            .foregroundStyle(AmenTheme.Colors.textSecondary)

            AmenProvenanceLine(provenance: result.provenance)
        }
        .padding(10)
        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct AmenDetectedNeedRow: View {
    let need: DetectedNeed
    let onPreview: (HumanPreviewAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: need.kind.systemImage)
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 5) {
                    Text(need.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text(need.explanation)
                        .font(.footnote)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }

            AmenProvenanceLine(provenance: need.provenance)

            if let action = need.suggestedAction {
                Button {
                    onPreview(action)
                } label: {
                    Label(action.title, systemImage: action.kind.systemImage)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct AmenContextClaimRow: View {
    let claim: AmenContextClaim

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
                    .frame(width: 22)
                Text(claim.text)
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            AmenProvenanceLine(provenance: claim.provenance)
        }
        .padding(10)
        .background(AmenTheme.Colors.surfaceCard.opacity(0.76), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct AmenProvenanceLine: View {
    let provenance: ProvenanceChain

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: provenance.isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            Text("Claim \(provenance.claimID)")
            Text("•")
            Text(provenance.layers.originalSource?.title ?? "Source pending")
            Text("•")
            Text(provenance.layers.retrievalRecord?.namespace.rawValue ?? "namespace pending")
        }
        .font(.caption2)
        .foregroundStyle(AmenTheme.Colors.textTertiary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Provenance claim \(provenance.claimID)")
    }
}

private struct AmenRelationshipActionPreviewSheet: View {
    let action: HumanPreviewAction
    let isConfirmed: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label(action.kind.previewTitle, systemImage: action.kind.systemImage)
                    .font(.title3.weight(.semibold))

                Text(action.title)
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Text(action.diffPreview)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .amenIntelligenceMatteContent(cornerRadius: 12)

                Label("Nothing is sent, scheduled, shared, or opened until you confirm.", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                Spacer()

                Button(isConfirmed ? "Confirmed" : "Confirm") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConfirmed && action.requiresExplicitConfirmation)
                .frame(maxWidth: .infinity)
            }
            .padding(18)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

private struct AmenRelationshipThread: Identifiable, Hashable {
    let id: String
    let personName: String
    let relationshipLabel: String
    let trustBoundaryID: AmenTrustBoundaryID
    let recallQuery: String
    let memoryResults: [MemoryRecallResult]
    let detectedNeeds: [DetectedNeed]
    let contextBeforeReply: AmenContextBeforeReply
    let composerActions: [HumanPreviewAction]
}

private struct AmenContextBeforeReply: Hashable {
    let summary: String
    let claims: [AmenContextClaim]
    let actions: [HumanPreviewAction]
}

private struct AmenContextClaim: Identifiable, Hashable {
    let id: String
    let text: String
    let provenance: ProvenanceChain
}

private struct AmenFamilySignal: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let provenance: ProvenanceChain
}

private struct AmenDrivingBrief: Hashable {
    let voiceBrief: String
    let navigationAction: HumanPreviewAction
    let provenance: ProvenanceChain
}

private extension View {
    func amenRelationshipGlassChrome(cornerRadius: CGFloat) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.8)
            }
            .shadow(color: AmenTheme.Colors.glassDepth.opacity(0.32), radius: 18, x: 0, y: 10)
    }
}

private extension HumanPreviewActionKind {
    var shortTitle: String {
        switch self {
        case .sendMessage: "Send"
        case .postToSpace: "Post"
        case .scheduleReminder: "Schedule"
        case .shareDocument: "Share"
        case .mergeNotes: "Merge"
        case .createContextEdge: "Link"
        case .startNavigation: "Navigate"
        case .dismiss: "Dismiss"
        }
    }

    var previewTitle: String {
        switch self {
        case .sendMessage: "Message preview"
        case .scheduleReminder: "Reminder preview"
        case .shareDocument: "Share preview"
        case .startNavigation: "Navigation preview"
        default: "Action preview"
        }
    }

    var systemImage: String {
        switch self {
        case .sendMessage: "paperplane.fill"
        case .postToSpace: "person.3.fill"
        case .scheduleReminder: "calendar.badge.clock"
        case .shareDocument: "square.and.arrow.up"
        case .mergeNotes: "arrow.triangle.merge"
        case .createContextEdge: "link"
        case .startNavigation: "location.fill"
        case .dismiss: "xmark.circle"
        }
    }
}

private extension DetectedNeedKind {
    var title: String {
        switch self {
        case .unansweredQuestion: "Unanswered question"
        case .driftingMember: "Drifting member"
        case .potentialMentor: "Potential mentor"
        case .newMemberConfusion: "New member confusion"
        case .reminderCandidate: "Reminder candidate"
        case .sourceVerificationNeeded: "Source verification needed"
        case .leaveNowTravelNudge: "Leave-now travel nudge"
        case .duplicateThought: "Duplicate thought"
        }
    }

    var systemImage: String {
        switch self {
        case .unansweredQuestion: "questionmark.bubble"
        case .driftingMember: "person.crop.circle.badge.exclamationmark"
        case .potentialMentor: "person.2.badge.gearshape"
        case .newMemberConfusion: "person.crop.circle.badge.questionmark"
        case .reminderCandidate: "bell.badge"
        case .sourceVerificationNeeded: "checkmark.shield"
        case .leaveNowTravelNudge: "car.fill"
        case .duplicateThought: "doc.on.doc"
        }
    }
}

private enum AmenRelationshipOSSampleData {
    static let trustBoundary = AmenTrustBoundaryID(rawValue: "family-thread")
    static let conversationNodeID = ContextGraphNodeID(rawValue: "conversation-family-001")
    static let mariaNodeID = ContextGraphNodeID(rawValue: "person-maria")
    static let danielNodeID = ContextGraphNodeID(rawValue: "person-daniel")

    static let threads: [AmenRelationshipThread] = [
        AmenRelationshipThread(
            id: "maria",
            personName: "Maria",
            relationshipLabel: "Sister · family thread",
            trustBoundaryID: trustBoundary,
            recallQuery: "Recall: last three care notes before replying to Maria.",
            memoryResults: [
                memoryResult(
                    id: "mem-maria-visit",
                    nodeID: mariaNodeID,
                    claim: "Maria said Tuesday evenings are easiest for a short call after her shift.",
                    tags: ["availability", "family", "call"],
                    score: 0.94,
                    sourceTitle: "Family thread message",
                    claimID: "REL-MARIA-001"
                ),
                memoryResult(
                    id: "mem-maria-prayer",
                    nodeID: mariaNodeID,
                    claim: "She asked the family to pray for patience around the school transition.",
                    tags: ["prayer", "school"],
                    score: 0.89,
                    sourceTitle: "Prayer note",
                    claimID: "REL-MARIA-002"
                )
            ],
            detectedNeeds: [
                DetectedNeed(
                    id: "need-maria-follow-up",
                    kind: .reminderCandidate,
                    explanation: "A reply would be more useful if it includes a Tuesday check-in reminder and acknowledges the school transition.",
                    suggestedAction: action(
                        id: "schedule-maria-call",
                        kind: .scheduleReminder,
                        title: "Schedule Tuesday check-in",
                        diff: "+ Reminder: Call Maria Tuesday at 7:00 PM\n+ Note: Ask about school transition",
                        target: mariaNodeID
                    ),
                    provenance: provenance(claimID: "REL-NEED-001", sourceTitle: "Follow-up detector", namespace: .conversation(conversationID: "family", trustBoundaryID: trustBoundary))
                )
            ],
            contextBeforeReply: AmenContextBeforeReply(
                summary: "Maria likely needs a short, specific response: acknowledge the school transition, offer Tuesday evening, and avoid promising a time before confirming.",
                claims: [
                    AmenContextClaim(
                        id: "claim-maria-1",
                        text: "Tuesday evening has been the least disruptive time for Maria.",
                        provenance: provenance(claimID: "REL-MARIA-001", sourceTitle: "Family thread message", namespace: .conversation(conversationID: "family", trustBoundaryID: trustBoundary))
                    ),
                    AmenContextClaim(
                        id: "claim-maria-2",
                        text: "The school transition is the current pastoral care context.",
                        provenance: provenance(claimID: "REL-MARIA-002", sourceTitle: "Prayer note", namespace: .personal(userID: "current-user"))
                    )
                ],
                actions: [
                    action(
                        id: "send-maria-reply",
                        kind: .sendMessage,
                        title: "Send thoughtful reply",
                        diff: "Hey Maria, I remembered Tuesdays are usually best. I can check in then, and I am praying for patience and peace with the school transition.",
                        target: mariaNodeID
                    ),
                    action(
                        id: "share-maria-note",
                        kind: .shareDocument,
                        title: "Share care note",
                        diff: "+ Share a private family care note with explicit participants only.",
                        target: mariaNodeID
                    )
                ]
            ),
            composerActions: [
                action(id: "composer-send-maria", kind: .sendMessage, title: "Preview send", diff: "Preview the drafted reply before sending.", target: mariaNodeID),
                action(id: "composer-schedule-maria", kind: .scheduleReminder, title: "Preview reminder", diff: "Preview a reminder connected to this conversation.", target: mariaNodeID),
                action(id: "composer-share-maria", kind: .shareDocument, title: "Preview share", diff: "Preview sharing the selected context with explicit participants.", target: mariaNodeID)
            ]
        ),
        AmenRelationshipThread(
            id: "daniel",
            personName: "Daniel",
            relationshipLabel: "Dad · appointment prep",
            trustBoundaryID: trustBoundary,
            recallQuery: "Recall: recent appointment and driving context before replying to Daniel.",
            memoryResults: [
                memoryResult(
                    id: "mem-daniel-appointment",
                    nodeID: danielNodeID,
                    claim: "Daniel asked for a reminder before the Thursday appointment and prefers voice calls while driving.",
                    tags: ["appointment", "voice", "family"],
                    score: 0.91,
                    sourceTitle: "Appointment thread",
                    claimID: "REL-DANIEL-001"
                )
            ],
            detectedNeeds: [
                DetectedNeed(
                    id: "need-daniel-nav",
                    kind: .leaveNowTravelNudge,
                    explanation: "The next helpful action is navigation, not a typed message, because the user is in Driving Mode.",
                    suggestedAction: action(
                        id: "navigate-daniel",
                        kind: .startNavigation,
                        title: "Start route preview",
                        diff: "+ Open route to Daniel's appointment location after confirmation.",
                        target: danielNodeID
                    ),
                    provenance: provenance(claimID: "REL-NEED-002", sourceTitle: "Driving Mode detector", namespace: .conversation(conversationID: "family", trustBoundaryID: trustBoundary))
                )
            ],
            contextBeforeReply: AmenContextBeforeReply(
                summary: "Daniel needs a quick voice-first response and a navigation preview; the app should not send or open routes without confirmation.",
                claims: [
                    AmenContextClaim(
                        id: "claim-daniel-1",
                        text: "Daniel prefers voice calls while driving.",
                        provenance: provenance(claimID: "REL-DANIEL-001", sourceTitle: "Appointment thread", namespace: .conversation(conversationID: "family", trustBoundaryID: trustBoundary))
                    )
                ],
                actions: [
                    action(id: "call-daniel", kind: .sendMessage, title: "Preview voice reply", diff: "Prepare a short voice-first reply. Nothing is sent until confirmation.", target: danielNodeID),
                    action(id: "route-daniel", kind: .startNavigation, title: "Preview route", diff: "Open route preview after explicit confirmation.", target: danielNodeID)
                ]
            ),
            composerActions: [
                action(id: "composer-call-daniel", kind: .sendMessage, title: "Preview voice reply", diff: "Preview a short voice-first reply before sending.", target: danielNodeID),
                action(id: "composer-route-daniel", kind: .startNavigation, title: "Preview route", diff: "Preview navigation without opening Maps automatically.", target: danielNodeID)
            ]
        )
    ]

    static let familySignals: [AmenFamilySignal] = [
        AmenFamilySignal(
            id: "family-boundary",
            title: "Family boundary active",
            detail: "Relationship context remains scoped to the explicit family thread.",
            systemImage: "person.2.badge.shield.checkmark",
            provenance: provenance(claimID: "REL-FAMILY-001", sourceTitle: "Trust boundary policy", namespace: .conversation(conversationID: "family", trustBoundaryID: trustBoundary))
        ),
        AmenFamilySignal(
            id: "care-follow-up",
            title: "Care follow-up",
            detail: "Suggested actions stay in preview until a person confirms them.",
            systemImage: "hand.raised.fill",
            provenance: provenance(claimID: "REL-FAMILY-002", sourceTitle: "Human confirmation policy", namespace: .personal(userID: "current-user"))
        )
    ]

    static let drivingBrief = AmenDrivingBrief(
        voiceBrief: "Driving Mode detected. Berean can prepare a brief reply or route preview, but nothing happens without confirmation.",
        navigationAction: action(
            id: "driving-route-preview",
            kind: .startNavigation,
            title: "Preview route",
            diff: "Show route preview for the next appointment after explicit confirmation.",
            target: danielNodeID
        ),
        provenance: provenance(claimID: "REL-DRIVE-001", sourceTitle: "Driving Mode detector", namespace: .conversation(conversationID: "family", trustBoundaryID: trustBoundary))
    )

    static func memoryResult(
        id: String,
        nodeID: ContextGraphNodeID,
        claim: String,
        tags: [String],
        score: Double,
        sourceTitle: String,
        claimID: String
    ) -> MemoryRecallResult {
        MemoryRecallResult(
            id: id,
            memory: MemoryNode(
                id: nodeID,
                claimText: claim,
                tags: tags
            ),
            relevanceScore: score,
            provenance: provenance(claimID: claimID, sourceTitle: sourceTitle, namespace: .conversation(conversationID: "family", trustBoundaryID: trustBoundary))
        )
    }

    static func action(
        id: String,
        kind: HumanPreviewActionKind,
        title: String,
        diff: String,
        target: ContextGraphNodeID
    ) -> HumanPreviewAction {
        HumanPreviewAction(
            id: id,
            kind: kind,
            title: title,
            diffPreview: diff,
            targetNodeID: target,
            requiresExplicitConfirmation: true
        )
    }

    static func provenance(
        claimID: String,
        sourceTitle: String,
        namespace: PineconeNamespace
    ) -> ProvenanceChain {
        ProvenanceChain(
            claimID: claimID,
            layers: FourLayerProvenance(
                originalSource: ProvenanceOriginalSource(
                    sourceID: "source-\(claimID)",
                    sourceKind: .conversationMessage,
                    title: sourceTitle,
                    authorNodeID: ContextGraphNodeID(rawValue: "person-current-user"),
                    sourceURL: nil,
                    sourceTimestamp: Date()
                ),
                captureRecord: ProvenanceCaptureRecord(
                    capturedByUserID: "current-user",
                    capturedAt: Date(),
                    deviceID: nil,
                    appVersion: nil,
                    trustBoundaryID: trustBoundary
                ),
                processingRecord: ProvenanceProcessingRecord(
                    processor: .deterministicParser,
                    callableProxyName: nil,
                    modelName: nil,
                    transform: .contextLinking,
                    processedAt: Date(),
                    humanReviewed: true
                ),
                retrievalRecord: ProvenanceRetrievalRecord(
                    retrievedAt: Date(),
                    queryID: "relationship-\(claimID)",
                    namespace: namespace,
                    rankingSignals: [MemoryRankingSignal(name: "relationshipContext", weight: 1, value: "sample")],
                    confidence: 0.84
                )
            ),
            generatedAt: Date()
        )
    }
}

#Preview {
    AmenRelationshipOSView()
}
