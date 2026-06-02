import SwiftUI

struct AmenCreatorOSView: View {
    @State private var selectedPathID = AmenCreatorOSSampleData.learningPaths[0].id
    @State private var selectedAction: HumanPreviewAction?
    @State private var confirmedActionID: String?

    private let learningPaths = AmenCreatorOSSampleData.learningPaths
    private let healthScore = AmenCreatorOSSampleData.healthScore
    private let managerBrief = AmenCreatorOSSampleData.managerBrief
    private let dashboard = AmenCreatorOSSampleData.dashboard
    private let spaceMembers = AmenCreatorOSSampleData.spaceMembers
    private let provenance = AmenCreatorOSSampleData.provenance

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerChrome
                    learningPathSection
                    communityHealthSection
                    communityManagerSection
                    privateDashboardSection
                    residentMembersSection
                    provenanceSection
                }
                .padding(16)
            }
            .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Creator OS")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedAction) { action in
            AmenCreatorOSActionPreviewSheet(
                action: action,
                provenance: provenance,
                confirmedActionID: $confirmedActionID
            )
            .presentationDetents([.medium])
        }
    }

    private var selectedPath: AmenLearningPath {
        learningPaths.first { $0.id == selectedPathID } ?? learningPaths[0]
    }

    private var headerChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AmenTheme.Colors.surfaceChip))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Creator OS")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("AMEN Spaces intelligence for learning, care, and creator stewardship.")
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                contextCapsule("Private dashboard", systemImage: "lock.shield.fill")
                contextCapsule("No public counts", systemImage: "eye.slash.fill")
            }
        }
        .padding(16)
        .amenCreatorOSChrome(.chromeBar)
    }

    private var learningPathSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Learning Paths", systemImage: "map.fill")

            Picker("Learning Path", selection: $selectedPathID) {
                ForEach(learningPaths) { path in
                    Text(path.title).tag(path.id)
                }
            }
            .pickerStyle(.segmented)
            .animation(Motion.adaptive(Motion.appearEase), value: selectedPathID)

            VStack(alignment: .leading, spacing: 10) {
                Text(selectedPath.title)
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(selectedPath.focus)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedPath.steps) { step in
                        AmenLearningPathStepRow(step: step)
                    }
                }
            }
            .padding(14)
            .amenIntelligenceMatteContent(cornerRadius: 12)
        }
    }

    private var communityHealthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Community Health Score", systemImage: "heart.text.square.fill")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(healthScore.overall)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("/ 100")
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Spacer(minLength: 0)
                Text(healthScore.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AmenTheme.Colors.surfaceChip))
            }

            VStack(spacing: 10) {
                ForEach(healthScore.metrics) { metric in
                    AmenHealthMetricRow(metric: metric)
                }
            }
        }
        .padding(14)
        .amenIntelligenceMatteContent(cornerRadius: 12)
    }

    private var communityManagerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("AI Community Manager", systemImage: "person.2.wave.2.fill")

            Text(managerBrief.summary)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(managerBrief.actions) { action in
                    AmenCreatorOSActionRow(
                        action: action,
                        isConfirmed: confirmedActionID == action.id
                    ) {
                        selectedAction = action
                    }
                }
            }
        }
        .padding(14)
        .amenCreatorOSChrome(.floatingBereanPanel)
    }

    private var privateDashboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Private Creator Intelligence Dashboard", systemImage: "chart.xyaxis.line")

            Text("Only the creator and explicitly delegated stewards can see this dashboard.")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 10)], spacing: 10) {
                ForEach(dashboard.cards) { card in
                    AmenCreatorDashboardCard(card: card)
                }
            }
        }
        .padding(14)
        .amenIntelligenceMatteContent(cornerRadius: 12)
    }

    private var residentMembersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Space Members", systemImage: "person.3.sequence.fill")

            ForEach(spaceMembers) { member in
                HStack(spacing: 10) {
                    Image(systemName: member.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(member.isBereanResident ? AmenTheme.Colors.amenGold : AmenTheme.Colors.iconSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(AmenTheme.Colors.surfaceChip))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Text(member.role)
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    if member.isBereanResident {
                        Text("Resident")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.amenPurple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AmenTheme.Colors.surfaceChip))
                    }
                }
            }
        }
        .padding(14)
        .amenIntelligenceMatteContent(cornerRadius: 12)
    }

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Provenance", systemImage: "checkmark.seal.text.page.fill")

            AmenCreatorOSProvenanceView(provenance: provenance)
        }
        .padding(14)
        .amenIntelligenceMatteContent(cornerRadius: 12)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.iconSecondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func contextCapsule(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .amenCreatorOSChrome(.contextCapsule)
    }
}

private struct AmenLearningPathStepRow: View {
    let step: AmenLearningStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(step.isComplete ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.iconSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(step.outcome)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AmenHealthMetricRow: View {
    let metric: AmenHealthMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text(metric.valueLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            ProgressView(value: metric.value)
                .tint(metric.tint)

            Text(metric.description)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AmenCreatorOSActionRow: View {
    let action: HumanPreviewAction
    let isConfirmed: Bool
    let onPreview: () -> Void

    var body: some View {
        Button(action: onPreview) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isConfirmed ? "checkmark.circle.fill" : "doc.text.magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isConfirmed ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.iconSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AmenTheme.Colors.surfaceChip))

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text(action.diffPreview)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Preview required before confirmation")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
            }
            .padding(12)
            .amenIntelligenceMatteContent(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .animation(Motion.adaptive(Motion.popToggle), value: isConfirmed)
    }
}

private struct AmenCreatorDashboardCard: View {
    let card: AmenDashboardCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: card.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.iconSecondary)
            Text(card.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text(card.value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(card.context)
                .font(.caption2)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .amenIntelligenceMatteContent(cornerRadius: 10)
    }
}

private struct AmenCreatorOSProvenanceView: View {
    let provenance: ProvenanceChain

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            provenanceRow("Claim", value: provenance.claimID)
            provenanceRow("Original source", value: provenance.layers.originalSource?.title ?? "Missing")
            provenanceRow("Capture", value: provenance.layers.captureRecord?.trustBoundaryID.rawValue ?? "Missing")
            provenanceRow("Processing", value: provenance.layers.processingRecord?.processor.rawValue ?? "Missing")
            provenanceRow("Retrieval", value: provenance.layers.retrievalRecord?.namespace.rawValue ?? "Missing")

            Label(provenance.isComplete ? "Four-layer provenance complete" : "Provenance incomplete", systemImage: provenance.isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(provenance.isComplete ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.amenGold)
        }
    }

    private func provenanceRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct AmenCreatorOSActionPreviewSheet: View {
    let action: HumanPreviewAction
    let provenance: ProvenanceChain
    @Binding var confirmedActionID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Opt-in preview", systemImage: "hand.tap.fill")
                    .font(.headline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Text(action.diffPreview)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .amenIntelligenceMatteContent(cornerRadius: 12)

                AmenCreatorOSProvenanceView(provenance: provenance)
                    .padding(14)
                    .amenIntelligenceMatteContent(cornerRadius: 12)

                Spacer(minLength: 0)

                Button {
                    confirmedActionID = action.id
                    dismiss()
                } label: {
                    Label("Confirm action", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Dismiss without changes") {
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension View {
    @ViewBuilder
    func amenCreatorOSChrome(_ style: AmenIntelligenceGlassStyle) -> some View {
        if #available(iOS 26.0, *) {
            self.amenIntelligenceGlassChrome(style)
        } else {
            self
                .background(AmenTheme.Colors.glassFill, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                }
        }
    }
}

private struct AmenLearningPath: Identifiable, Hashable {
    let id: String
    var title: String
    var focus: String
    var steps: [AmenLearningStep]
}

private struct AmenLearningStep: Identifiable, Hashable {
    let id: String
    var title: String
    var outcome: String
    var isComplete: Bool
}

private struct AmenCommunityHealthScore: Hashable {
    var overall: Int
    var status: String
    var metrics: [AmenHealthMetric]
}

private struct AmenHealthMetric: Identifiable, Hashable {
    let id: String
    var title: String
    var value: Double
    var valueLabel: String
    var description: String
    var tint: Color
}

private struct AmenCommunityManagerBrief: Hashable {
    var summary: String
    var actions: [HumanPreviewAction]
}

private struct AmenCreatorDashboard: Hashable {
    var cards: [AmenDashboardCard]
}

private struct AmenDashboardCard: Identifiable, Hashable {
    let id: String
    var title: String
    var value: String
    var context: String
    var systemImage: String
}

private struct AmenSpaceMember: Identifiable, Hashable {
    let id: String
    var name: String
    var role: String
    var systemImage: String
    var isBereanResident: Bool
}

private enum AmenCreatorOSSampleData {
    static let trustBoundaryID = AmenTrustBoundaryID(rawValue: "creator-space-rooted-discipleship")
    static let creatorNodeID = ContextGraphNodeID(rawValue: "person.creator.mara")
    static let spaceNodeID = ContextGraphNodeID(rawValue: "community.space.rooted-discipleship")

    static let learningPaths: [AmenLearningPath] = [
        AmenLearningPath(
            id: "path-foundations",
            title: "Foundations",
            focus: "Move new members from orientation into a repeatable rhythm of scripture, questions, and shared practice.",
            steps: [
                AmenLearningStep(id: "foundations-1", title: "Start here guide", outcome: "Members understand the purpose and covenant of the Space.", isComplete: true),
                AmenLearningStep(id: "foundations-2", title: "First reflection", outcome: "Each learner responds privately before discussion opens.", isComplete: true),
                AmenLearningStep(id: "foundations-3", title: "Mentor pairing", outcome: "Newer members receive a named guide for their first two weeks.", isComplete: false)
            ]
        ),
        AmenLearningPath(
            id: "path-practice",
            title: "Practice",
            focus: "Turn teaching into lived obedience with small group prompts and weekly check-ins.",
            steps: [
                AmenLearningStep(id: "practice-1", title: "Weekly application", outcome: "Members choose one concrete practice before the next gathering.", isComplete: true),
                AmenLearningStep(id: "practice-2", title: "Peer encouragement", outcome: "Mentors notice quiet members and invite private follow-up.", isComplete: false),
                AmenLearningStep(id: "practice-3", title: "Resolution review", outcome: "Open questions are answered or routed to a teacher.", isComplete: false)
            ]
        ),
        AmenLearningPath(
            id: "path-leadership",
            title: "Leadership",
            focus: "Prepare faithful contributors for service without ranking them by attention metrics.",
            steps: [
                AmenLearningStep(id: "leadership-1", title: "Care pattern review", outcome: "Potential mentors are surfaced by consistency and humility signals.", isComplete: false),
                AmenLearningStep(id: "leadership-2", title: "Teaching source packet", outcome: "Leaders review cited source trails before posting guidance.", isComplete: false),
                AmenLearningStep(id: "leadership-3", title: "Commissioning preview", outcome: "The creator confirms stewardship roles before any member sees them.", isComplete: false)
            ]
        )
    ]

    static let healthScore = AmenCommunityHealthScore(
        overall: 84,
        status: "Healthy with follow-up",
        metrics: [
            AmenHealthMetric(id: "retention-quality", title: "Retention quality", value: 0.86, valueLabel: "86%", description: "Members remain active through learning milestones, not attention spikes.", tint: AmenTheme.Colors.amenBlue),
            AmenHealthMetric(id: "learning-outcomes", title: "Learning outcomes", value: 0.81, valueLabel: "81%", description: "Reflections show comprehension, application, and source-aware discussion.", tint: AmenTheme.Colors.amenPurple),
            AmenHealthMetric(id: "mentorship", title: "Mentorship", value: 0.74, valueLabel: "74%", description: "New members have a named mentor or a pending pairing recommendation.", tint: AmenTheme.Colors.amenGold),
            AmenHealthMetric(id: "question-resolution", title: "Unanswered-question resolution", value: 0.91, valueLabel: "91%", description: "Open questions are resolved, assigned, or carried into the next lesson plan.", tint: AmenTheme.Colors.textPrimary)
        ]
    )

    static let managerBrief = AmenCommunityManagerBrief(
        summary: "Berean prepared three steward-facing actions. Nothing is posted, messaged, assigned, or stored until the creator previews and confirms it.",
        actions: [
            HumanPreviewAction(
                id: "preview-mentor-pairing",
                kind: .createContextEdge,
                title: "Preview mentor pairing",
                diffPreview: "Create a private mentor relationship suggestion between Naomi and Eli for the Foundations path. No member-facing notification will be sent yet.",
                targetNodeID: ContextGraphNodeID(rawValue: "person.member.eli"),
                requiresExplicitConfirmation: true
            ),
            HumanPreviewAction(
                id: "preview-question-reply",
                kind: .sendMessage,
                title: "Draft unanswered-question reply",
                diffPreview: "Prepare a creator-approved response to the Romans 8 question with cited source trail and a prompt for continued discussion.",
                targetNodeID: ContextGraphNodeID(rawValue: "conversation.questions.romans8"),
                requiresExplicitConfirmation: true
            ),
            HumanPreviewAction(
                id: "preview-learning-path-update",
                kind: .postToSpace,
                title: "Preview Learning Path update",
                diffPreview: "Add a Practice path checkpoint asking members to name one act of obedience before the next gathering.",
                targetNodeID: spaceNodeID,
                requiresExplicitConfirmation: true
            )
        ]
    )

    static let dashboard = AmenCreatorDashboard(cards: [
        AmenDashboardCard(id: "care-load", title: "Care load", value: "Balanced", context: "Two members need creator review this week.", systemImage: "scalemass.fill"),
        AmenDashboardCard(id: "source-integrity", title: "Source integrity", value: "Complete", context: "Recent teaching notes include visible provenance.", systemImage: "books.vertical.fill"),
        AmenDashboardCard(id: "member-progress", title: "Path progress", value: "On track", context: "Most active learners are moving through Foundations.", systemImage: "figure.walk.motion"),
        AmenDashboardCard(id: "resolution-queue", title: "Resolution queue", value: "3 items", context: "Finite queue for creator preview and confirmation.", systemImage: "tray.full.fill")
    ])

    static let spaceMembers: [AmenSpaceMember] = [
        AmenSpaceMember(id: "creator", name: "Mara", role: "Creator and steward", systemImage: "person.crop.circle.badge.checkmark", isBereanResident: false),
        AmenSpaceMember(id: "berean", name: "Berean", role: "Resident Space member for source-aware assistance", systemImage: "sparkles", isBereanResident: true),
        AmenSpaceMember(id: "mentor", name: "Naomi", role: "Mentor candidate", systemImage: "person.crop.circle", isBereanResident: false)
    ]

    static let provenance = ProvenanceChain(
        claimID: "claim.creator-space.health.rooted-discipleship",
        layers: FourLayerProvenance(
            originalSource: ProvenanceOriginalSource(
                sourceID: "space-rooted-discipleship-week-4",
                sourceKind: .document,
                title: "Rooted Discipleship Week 4 steward notes",
                authorNodeID: creatorNodeID,
                sourceURL: nil,
                sourceTimestamp: Date(timeIntervalSince1970: 1_797_465_600),
                scriptureReference: ScriptureReferenceNodePayload(translation: "ESV", book: "Romans", chapter: 8, startVerse: 1, endVerse: 11)
            ),
            captureRecord: ProvenanceCaptureRecord(
                capturedByUserID: "creator.mara",
                capturedAt: Date(timeIntervalSince1970: 1_797_552_000),
                deviceID: nil,
                appVersion: "Phase 2 Lane C",
                trustBoundaryID: trustBoundaryID
            ),
            processingRecord: ProvenanceProcessingRecord(
                processor: .deterministicParser,
                callableProxyName: BereanCallableName.summarizeContext.rawValue,
                modelName: nil,
                transform: .summary,
                processedAt: Date(timeIntervalSince1970: 1_797_555_600),
                humanReviewed: true
            ),
            retrievalRecord: ProvenanceRetrievalRecord(
                retrievedAt: Date(timeIntervalSince1970: 1_797_559_200),
                queryID: "creator-space-health-dashboard",
                namespace: .creatorPrivate(spaceID: "rooted-discipleship", creatorUserID: "creator.mara"),
                rankingSignals: [
                    MemoryRankingSignal(name: "learning_outcome_match", weight: 0.42, value: "high"),
                    MemoryRankingSignal(name: "unanswered_question_resolution", weight: 0.36, value: "high"),
                    MemoryRankingSignal(name: "mentor_signal", weight: 0.22, value: "medium")
                ],
                confidence: 0.88
            )
        ),
        generatedAt: Date(timeIntervalSince1970: 1_797_559_200)
    )
}

#Preview {
    AmenCreatorOSView()
}
