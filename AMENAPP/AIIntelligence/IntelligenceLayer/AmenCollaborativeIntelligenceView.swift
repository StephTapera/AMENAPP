import SwiftUI

struct AmenCollaborativeIntelligenceView: View {
    @State private var selectedMode: CollaborationMode = .coAuthor
    @State private var selectedAction: CollaborativePreviewAction?
    @State private var confirmedAction: CollaborativePreviewAction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let context = CollaborativeChurchContext.sample
    private let statements = CollaborativeStatement.sample
    private let decisions = CollaborativeDecisionTrail.sample
    private let actions = CollaborativePreviewAction.sample

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerChrome
                        modePicker
                        contentForSelectedMode
                    }
                    .padding(16)
                    .padding(.bottom, 92)
                }

                actionChrome
            }
            .navigationTitle("Smart Church Notes")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedAction) { action in
                CollaborativeActionConfirmationSheet(
                    action: action,
                    onCancel: { selectedAction = nil },
                    onConfirm: {
                        withAnimation(Motion.adaptive(.easeInOut(duration: 0.18))) {
                            confirmedAction = action
                            selectedAction = nil
                        }
                    }
                )
                .presentationDetents([.medium])
            }
            .overlay(alignment: .top) {
                if let confirmedAction {
                    ConfirmedActionBanner(action: confirmedAction) {
                        withAnimation(Motion.adaptive(.easeInOut(duration: 0.16))) {
                            self.confirmedAction = nil
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var headerChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.2.wave.2")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Collaborative intelligence")
                        .font(.headline)
                    Text("AI-assisted co-authoring grounded in project, decision, stakeholder, and provenance context.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ContextLine(label: "Project", value: context.project)
                ContextLine(label: "Decision", value: context.decision)
                ContextLine(label: "Stakeholders", value: context.stakeholders.joined(separator: ", "))
            }
        }
        .padding(14)
        .glassChrome(cornerRadius: 8)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(CollaborationMode.allCases) { mode in
                Button {
                    withAnimation(Motion.adaptive(.easeInOut(duration: 0.18))) {
                        selectedMode = mode
                    }
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selectedMode == mode ? .primary : .secondary)
                        .background(
                            selectedMode == mode ? Color(.systemBackground) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }
        }
        .padding(6)
        .glassChrome(cornerRadius: 8)
    }

    @ViewBuilder
    private var contentForSelectedMode: some View {
        switch selectedMode {
        case .coAuthor:
            coAuthorContent
        case .sources:
            sourceVerificationContent
        case .trail:
            decisionTrailContent
        }
    }

    private var coAuthorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            CollaborativeSectionHeader(title: "Co-author draft", subtitle: "Every sentence remains attached to a visible origin before anything can be posted or shared.")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(statements) { statement in
                    StatementCard(statement: statement)
                }
            }

            ProvenanceLedger(summary: "4 statements, 4 visible origins, 0 unsupported claims")
        }
    }

    private var sourceVerificationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            CollaborativeSectionHeader(title: "Source verification", subtitle: "Claims are grouped by verification state and original source before action preview.")

            ForEach(statements) { statement in
                SourceVerificationRow(statement: statement)
            }
        }
    }

    private var decisionTrailContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            CollaborativeSectionHeader(title: "Decision trails", subtitle: "Why, who, changed, and decided stay visible beside the church note.")

            ForEach(decisions) { decision in
                DecisionTrailCard(decision: decision)
            }
        }
    }

    private var actionChrome: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                Button {
                    withAnimation(Motion.adaptive(.easeInOut(duration: 0.18))) {
                        selectedAction = action
                    }
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHint("Opens a preview before confirming")
            }
        }
        .padding(10)
        .glassChrome(cornerRadius: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private enum CollaborationMode: String, CaseIterable, Identifiable {
    case coAuthor
    case sources
    case trail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coAuthor: "Draft"
        case .sources: "Sources"
        case .trail: "Trail"
        }
    }

    var systemImage: String {
        switch self {
        case .coAuthor: "square.and.pencil"
        case .sources: "checkmark.seal"
        case .trail: "point.topleft.down.curvedto.point.bottomright.up"
        }
    }
}

private struct CollaborativeChurchContext {
    var project: String
    var decision: String
    var stakeholders: [String]

    static let sample = CollaborativeChurchContext(
        project: "Hospitality relaunch for Sunday teams",
        decision: "Move newcomer follow-up from ad hoc texts to a shared notes workflow",
        stakeholders: ["Pastor Maya", "Hospitality leads", "Assimilation team"]
    )
}

private struct CollaborativeStatement: Identifiable {
    let id: String
    var text: String
    var origin: String
    var verification: SourceVerificationStatus
    var provenance: String
    var context: String

    static let sample: [CollaborativeStatement] = [
        CollaborativeStatement(
            id: "statement-1",
            text: "Newcomer cards should be reviewed before the Monday staff huddle.",
            origin: "Hospitality planning note, May 26",
            verification: .verified,
            provenance: "humanNote -> deterministicParser -> retrieval hospitality_2026",
            context: "Project: Hospitality relaunch"
        ),
        CollaborativeStatement(
            id: "statement-2",
            text: "Pastor Maya asked for one owner per follow-up so families do not receive duplicate messages.",
            origin: "Staff thread, May 28",
            verification: .verified,
            provenance: "conversationMessage -> contextLinking -> retrieval staff_thread",
            context: "Stakeholder: Pastor Maya"
        ),
        CollaborativeStatement(
            id: "statement-3",
            text: "The current volunteer roster has open coverage for the 11:00 welcome table.",
            origin: "Serving schedule import, May 29",
            verification: .partial,
            provenance: "importedFile -> sourceVerification -> retrieval serving_roster",
            context: "Decision: assign follow-up coverage"
        ),
        CollaborativeStatement(
            id: "statement-4",
            text: "No public post should include private pastoral care notes.",
            origin: "Trust boundary policy note",
            verification: .verified,
            provenance: "document -> humanReviewed -> retrieval policy_notes",
            context: "Boundary: explicit participant sharing"
        )
    ]
}

private struct CollaborativeDecisionTrail: Identifiable {
    let id: String
    var title: String
    var why: String
    var who: String
    var changed: String
    var decided: String
    var provenance: String

    static let sample: [CollaborativeDecisionTrail] = [
        CollaborativeDecisionTrail(
            id: "trail-1",
            title: "Follow-up ownership",
            why: "Duplicate messages were confusing new families.",
            who: "Pastor Maya and hospitality leads",
            changed: "Added one named owner to each newcomer note.",
            decided: "Use shared notes for team visibility after review.",
            provenance: "DecisionTrail document, claim DT-104"
        ),
        CollaborativeDecisionTrail(
            id: "trail-2",
            title: "Privacy boundary",
            why: "Pastoral care details belong in explicit participant spaces only.",
            who: "Assimilation coordinator",
            changed: "Public summaries now exclude private care context.",
            decided: "Post only attendance-neutral next steps.",
            provenance: "TrustBoundary policy, claim TB-042"
        )
    ]
}

private struct CollaborativePreviewAction: Identifiable {
    let id: String
    var title: String
    var systemImage: String
    var kind: HumanPreviewActionKind
    var preview: String
    var confirmation: String

    static let sample: [CollaborativePreviewAction] = [
        CollaborativePreviewAction(
            id: "coauthor",
            title: "Co-author",
            systemImage: "wand.and.stars",
            kind: .mergeNotes,
            preview: "Merge the verified statements into the draft note. Unsupported text remains excluded.",
            confirmation: "The draft will update locally for review. Nothing is posted."
        ),
        CollaborativePreviewAction(
            id: "post",
            title: "Post",
            systemImage: "paperplane",
            kind: .postToSpace,
            preview: "Post the reviewed church note to the hospitality workspace with provenance visible.",
            confirmation: "Requires explicit confirmation before posting to the selected space."
        ),
        CollaborativePreviewAction(
            id: "share",
            title: "Share",
            systemImage: "square.and.arrow.up",
            kind: .shareDocument,
            preview: "Share a read-only source packet with Pastor Maya and hospitality leads.",
            confirmation: "Recipients and source packet contents remain reviewable before sharing."
        )
    ]
}

private struct ContextLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CollaborativeSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatementCard: View {
    let statement: CollaborativeStatement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(statement.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                VerificationBadge(status: statement.verification)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Origin: \(statement.origin)")
                    Text(statement.context)
                    Text(statement.provenance)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .matteCard()
    }
}

private struct SourceVerificationRow: View {
    let statement: CollaborativeStatement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VerificationBadge(status: statement.verification)
                Spacer(minLength: 8)
                Text(statement.origin)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            Text(statement.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Label(statement.provenance, systemImage: "link")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .matteCard()
    }
}

private struct DecisionTrailCard: View {
    let decision: CollaborativeDecisionTrail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(decision.title)
                .font(.headline)

            DecisionTrailLine(label: "Why", value: decision.why)
            DecisionTrailLine(label: "Who", value: decision.who)
            DecisionTrailLine(label: "Changed", value: decision.changed)
            DecisionTrailLine(label: "Decided", value: decision.decided)

            Label(decision.provenance, systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .matteCard()
    }
}

private struct DecisionTrailLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProvenanceLedger: View {
    let summary: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.blue)
            Text(summary)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassChrome(cornerRadius: 8)
    }
}

private struct VerificationBadge: View {
    let status: SourceVerificationStatus

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: Capsule(style: .continuous))
    }

    private var title: String {
        switch status {
        case .verified: "Verified"
        case .partial: "Partial"
        case .unsupported: "Unsupported"
        case .conflicting: "Conflict"
        }
    }

    private var systemImage: String {
        switch status {
        case .verified: "checkmark.seal.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .unsupported: "questionmark.circle.fill"
        case .conflicting: "xmark.octagon.fill"
        }
    }

    private var foreground: Color {
        switch status {
        case .verified: .green
        case .partial: .orange
        case .unsupported: .secondary
        case .conflicting: .red
        }
    }

    private var background: Color {
        switch status {
        case .verified: Color.green.opacity(0.12)
        case .partial: Color.orange.opacity(0.14)
        case .unsupported: Color.secondary.opacity(0.12)
        case .conflicting: Color.red.opacity(0.12)
        }
    }
}

private struct CollaborativeActionConfirmationSheet: View {
    let action: CollaborativePreviewAction
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preview \(action.title)")
                        .font(.headline)
                    Text(action.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(action.preview)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .matteCard()

            Label(action.confirmation, systemImage: "hand.tap")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("Confirm", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .presentationBackground(.thinMaterial)
    }
}

private struct ConfirmedActionBanner: View {
    let action: CollaborativePreviewAction
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("\(action.title) confirmed for preview workflow")
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .glassChrome(cornerRadius: 8)
    }
}

private struct MatteCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

private struct GlassChromeModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency ? Color(.systemBackground) : Color(.secondarySystemBackground).opacity(0.72),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(reduceTransparency ? 0.12 : 0.32), lineWidth: 0.6)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

private extension View {
    func matteCard() -> some View {
        modifier(MatteCardModifier())
    }

    func glassChrome(cornerRadius: CGFloat) -> some View {
        modifier(GlassChromeModifier(cornerRadius: cornerRadius))
    }
}

#Preview {
    AmenCollaborativeIntelligenceView()
}
