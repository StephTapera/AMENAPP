// BereanAgentSharedWorkspacesView.swift
// AMEN — Berean Agent Surface · Wave 3 Lane G
//
// Content for BASWorkspaceTab.sharedWithYou — shared sermon planning,
// group studies, and prayer rooms.
//
// Design §2: Liquid Glass (.glassEffect), warm paper bg, tan surface,
//            wine-red accent (one element per screen max), 24pt corners,
//            soft shadows (shadowRadius 12, opacity 0.12).
// §7 blockers: giving/finances read-only only; safety advisory default;
//              E2EE isEncrypted=false, "E2EE: Coming Soon" label only.
// Role enforcement is UI-only in this build. Full enforcement in Firestore rules.

import SwiftUI

// MARK: - Section Tab

private enum BASWorkspaceSectionTab: String, CaseIterable, Identifiable {
    case sermon    = "Sermon"
    case study     = "Study"
    case prayer    = "Prayer"
    case devotional = "Devotional"

    var id: String { rawValue }

    var label: String { rawValue }

    var iconName: String {
        switch self {
        case .sermon:     return "waveform.and.mic"
        case .study:      return "book.fill"
        case .prayer:     return "hands.and.sparkles.fill"
        case .devotional: return "sunrise.fill"
        }
    }
}

// MARK: - Main View

@MainActor
struct BereanAgentSharedWorkspacesView: View {

    let workspace: BASWorkspace?
    var onStartStudy: () -> Void
    var onImportNotes: () -> Void
    var onInviteGroup: () -> Void
    var onBrowseTemplates: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection: BASWorkspaceSectionTab = .sermon

    var body: some View {
        ZStack {
            Color.basWarmPaper
                .ignoresSafeArea()

            if let workspace = workspace {
                workspaceContent(workspace)
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 48)

                // Icon — wine-red, one accent element for this screen
                Image(systemName: "hands.and.sparkles.fill")
                    .font(.system(.largeTitle, design: .default).weight(.regular))
                    .imageScale(.large)
                    .foregroundStyle(Color.basWineRed)
                    .accessibilityHidden(true)

                // Heading
                Text("No shared studies yet")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.basInk)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                // Subheading
                Text("Start or join a faith study with your church, small group, or study partner.")
                    .font(.body)
                    .foregroundStyle(Color.basInk.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Action buttons
                VStack(spacing: 12) {
                    // Primary — wine-red filled
                    Button(action: onStartStudy) {
                        Text("Start a study")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.basWineRed, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Start a study")
                    .accessibilityHint("Creates a new shared Bible study workspace")

                    // Secondary — tan filled
                    Button(action: onImportNotes) {
                        Text("Import sermon notes")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.basTan, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .foregroundStyle(Color.basInk)
                    }
                    .accessibilityLabel("Import sermon notes")
                    .accessibilityHint("Imports existing sermon notes into a workspace")

                    // Tertiary — outlined
                    Button(action: onInviteGroup) {
                        Text("Invite group")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Color.basInk.opacity(0.3), lineWidth: 1.5)
                            )
                            .foregroundStyle(Color.basInk)
                    }
                    .accessibilityLabel("Invite group")
                    .accessibilityHint("Sends an invitation to join this workspace")

                    // Quaternary — text link style
                    Button(action: onBrowseTemplates) {
                        Text("Browse templates")
                            .font(.body)
                            .underline()
                            .foregroundStyle(Color.basInk.opacity(0.6))
                    }
                    .accessibilityLabel("Browse templates")
                    .accessibilityHint("Opens a library of study and sermon templates")
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 48)
            }
        }
    }

    // MARK: - Workspace Content

    @ViewBuilder
    private func workspaceContent(_ ws: BASWorkspace) -> some View {
        switch ws.role {
        case .prayerOnly:
            prayerOnlyView(ws)
        case .viewer:
            viewerView(ws)
        case .contributor, .pastorAdmin, .owner:
            fullAccessView(ws)
        }
    }

    // MARK: - Prayer-Only View

    private func prayerOnlyView(_ ws: BASWorkspace) -> some View {
        VStack(spacing: 0) {
            // Access banner
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text("You have prayer-only access. Contact the workspace owner to request full access.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.basTan.opacity(0.85))
            .foregroundStyle(Color.basInk)
            .accessibilityLabel("Access restricted to prayer only")
            .accessibilityAddTraits(.isStaticText)

            ScrollView {
                VStack(spacing: 16) {
                    prayerRequestsSection(ws, editable: false)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Viewer View (read-only)

    private func viewerView(_ ws: BASWorkspace) -> some View {
        NavigationStack {
            ZStack {
                Color.basWarmPaper.ignoresSafeArea()
                ScrollView {
                    sectionTabBar(ws)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    sectionContent(ws)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle(ws.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("Read Only")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.basTan, in: Capsule())
                        .foregroundStyle(Color.basInk.opacity(0.7))
                        .accessibilityLabel("Read Only workspace")
                }
            }
        }
    }

    // MARK: - Full Access View (contributor / pastorAdmin / owner)

    private func fullAccessView(_ ws: BASWorkspace) -> some View {
        NavigationStack {
            ZStack {
                Color.basWarmPaper.ignoresSafeArea()
                ScrollView {
                    sectionTabBar(ws)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    sectionContent(ws)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle(ws.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if ws.role.canManageMembers {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: onInviteGroup) {
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(Color.basWineRed)
                        }
                        .accessibilityLabel("Invite group members")
                    }
                }
            }
        }
    }

    // MARK: - Section Tab Bar

    private func sectionTabBar(_ ws: BASWorkspace) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BASWorkspaceSectionTab.allCases) { tab in
                    Button {
                        withAnimation(
                            reduceMotion
                                ? .none
                                : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                        ) {
                            selectedSection = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.caption)
                                .accessibilityHidden(true)
                            Text(tab.label)
                                .font(.subheadline.weight(selectedSection == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedSection == tab
                                ? Color.basWineRed
                                : Color.basTan.opacity(0.7),
                            in: Capsule()
                        )
                        .foregroundStyle(
                            selectedSection == tab ? .white : Color.basInk
                        )
                    }
                    .accessibilityLabel("\(tab.label) section")
                    .accessibilityAddTraits(selectedSection == tab ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Section Content Router

    @ViewBuilder
    private func sectionContent(_ ws: BASWorkspace) -> some View {
        switch selectedSection {
        case .sermon:
            sermonSection(ws)
        case .study:
            studySection(ws)
        case .prayer:
            prayerRequestsSection(ws, editable: ws.role.canCreateContent)
        case .devotional:
            devotionalSection(ws)
        }
    }

    // MARK: - Sermon Section

    private func sermonSection(_ ws: BASWorkspace) -> some View {
        BASWorkspaceCard(title: "Sermon Outline", iconName: "waveform.and.mic") {
            VStack(alignment: .leading, spacing: 16) {
                BASLabeledField(
                    label: "Scripture Reference",
                    placeholder: "e.g. John 3:16",
                    isEditable: ws.role.canEditStudyNotes
                )
                BASLabeledTextArea(
                    label: "Outline",
                    placeholder: "Main points, transitions, illustrations…",
                    isEditable: ws.role.canEditStudyNotes,
                    minHeight: 100
                )
                BASLabeledTextArea(
                    label: "Speaker Notes",
                    placeholder: "Personal notes for the speaker…",
                    isEditable: ws.role.canEditStudyNotes,
                    minHeight: 80
                )
            }
        }
    }

    // MARK: - Study Section

    private func studySection(_ ws: BASWorkspace) -> some View {
        BASWorkspaceCard(title: "Bible Study", iconName: "book.fill") {
            VStack(alignment: .leading, spacing: 16) {
                BASLabeledTextArea(
                    label: "Lesson Plan",
                    placeholder: "Describe the lesson structure…",
                    isEditable: ws.role.canEditStudyNotes,
                    minHeight: 80
                )
                BASDiscussionQuestionsStub(isEditable: ws.role.canEditStudyNotes)
                BASLabeledTextArea(
                    label: "Group Notes",
                    placeholder: "Shared notes from the study…",
                    isEditable: ws.role.canEditStudyNotes,
                    minHeight: 80
                )
            }
        }
    }

    // MARK: - Prayer Requests Section

    private func prayerRequestsSection(_ ws: BASWorkspace, editable: Bool) -> some View {
        BASWorkspaceCard(title: "Prayer Requests", iconName: "hands.and.sparkles.fill") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(BASPrayerRequestStub.sampleStubs) { stub in
                    BASPrayerRequestRow(stub: stub)
                }

                if editable {
                    Button {
                        // Add prayer request — stub; real action wired in Wave 4+
                    } label: {
                        Label("Add prayer request", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.basWineRed)
                    }
                    .accessibilityLabel("Add a prayer request")
                    .accessibilityHint("Opens a form to submit a new prayer request")
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Devotional Section

    private func devotionalSection(_ ws: BASWorkspace) -> some View {
        BASWorkspaceCard(title: "Daily Reading Plan", iconName: "sunrise.fill") {
            VStack(alignment: .leading, spacing: 16) {
                BASLabeledField(
                    label: "Today's Reading",
                    placeholder: "e.g. Psalm 23",
                    isEditable: ws.role.canEditStudyNotes
                )
                BASLabeledTextArea(
                    label: "Reflection Notes",
                    placeholder: "What stood out to you today?",
                    isEditable: ws.role.canEditStudyNotes,
                    minHeight: 100
                )
            }
        }
    }
}

// MARK: - BASWorkspaceCard

private struct BASWorkspaceCard<Content: View>: View {
    let title: String
    let iconName: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.basInk.opacity(0.6))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.basInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            content()
        }
        .padding(20)
        .background(Color.basTan.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 4)
        .padding(.top, 12)
    }
}

// MARK: - BASLabeledField

private struct BASLabeledField: View {
    let label: String
    let placeholder: String
    let isEditable: Bool

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.basInk.opacity(0.55))

            if isEditable {
                TextField(placeholder, text: $text)
                    .font(.body)
                    .foregroundStyle(Color.basInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.basWarmPaper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(label)
            } else {
                Text(text.isEmpty ? placeholder : text)
                    .font(.body)
                    .foregroundStyle(text.isEmpty ? Color.basInk.opacity(0.35) : Color.basInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.basWarmPaper.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(label + (text.isEmpty ? ", empty" : ": \(text)"))
            }
        }
    }
}

// MARK: - BASLabeledTextArea

private struct BASLabeledTextArea: View {
    let label: String
    let placeholder: String
    let isEditable: Bool
    let minHeight: CGFloat

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.basInk.opacity(0.55))

            ZStack(alignment: .topLeading) {
                if isEditable {
                    TextEditor(text: $text)
                        .font(.body)
                        .foregroundStyle(Color.basInk)
                        .frame(minHeight: minHeight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(Color.basWarmPaper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(label)
                } else {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.body)
                        .foregroundStyle(text.isEmpty ? Color.basInk.opacity(0.35) : Color.basInk)
                        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.basWarmPaper.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(label + (text.isEmpty ? ", empty" : ": \(text)"))
                }
            }
        }
    }
}

// MARK: - BASDiscussionQuestionsStub

private struct BASDiscussionQuestionsStub: View {
    let isEditable: Bool

    @State private var questions: [String] = [
        "What does this passage reveal about God's character?",
        "How does this apply to our daily lives?",
        "What is one thing you will do differently this week?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discussion Questions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.basInk.opacity(0.55))

            ForEach(questions.indices, id: \.self) { idx in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(idx + 1).")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.basInk.opacity(0.5))
                        .frame(width: 18, alignment: .leading)
                        .accessibilityHidden(true)

                    Text(questions[idx])
                        .font(.subheadline)
                        .foregroundStyle(Color.basInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Question \(idx + 1): \(questions[idx])")
                }
            }

            if isEditable {
                Button {
                    // Add question — stub; real action wired in Wave 4+
                } label: {
                    Label("Add question", systemImage: "plus.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.basInk.opacity(0.6))
                }
                .accessibilityLabel("Add a discussion question")
                .accessibilityHint("Appends a new question to the discussion list")
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Prayer Request Stub Model

private struct BASPrayerRequestStub: Identifiable {
    let id: UUID
    let author: String
    let request: String

    static let sampleStubs: [BASPrayerRequestStub] = [
        BASPrayerRequestStub(id: UUID(), author: "Sarah M.", request: "Healing for my mother's surgery recovery."),
        BASPrayerRequestStub(id: UUID(), author: "James T.", request: "Wisdom for an important career decision."),
        BASPrayerRequestStub(id: UUID(), author: "Group", request: "Unity and growth for our small group.")
    ]
}

// MARK: - BASPrayerRequestRow

private struct BASPrayerRequestRow: View {
    let stub: BASPrayerRequestStub

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hands.and.sparkles.fill")
                .font(.footnote)
                .foregroundStyle(Color.basInk.opacity(0.4))
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(stub.author)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.basInk.opacity(0.55))
                Text(stub.request)
                    .font(.subheadline)
                    .foregroundStyle(Color.basInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prayer request from \(stub.author): \(stub.request)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Empty State") {
    BereanAgentSharedWorkspacesView(
        workspace: nil,
        onStartStudy: {},
        onImportNotes: {},
        onInviteGroup: {},
        onBrowseTemplates: {}
    )
}

#Preview("Prayer Only") {
    BereanAgentSharedWorkspacesView(
        workspace: BASWorkspace(
            id: "ws-1",
            name: "Sunday Prayer Room",
            role: .prayerOnly,
            tab: .sharedWithYou,
            isPrivate: false,
            createdBy: "pastor@church.org",
            memberCount: 12
        ),
        onStartStudy: {},
        onImportNotes: {},
        onInviteGroup: {},
        onBrowseTemplates: {}
    )
}

#Preview("Viewer") {
    BereanAgentSharedWorkspacesView(
        workspace: BASWorkspace(
            id: "ws-2",
            name: "Romans Study",
            role: .viewer,
            tab: .sharedWithYou,
            isPrivate: false,
            createdBy: "leader@church.org",
            memberCount: 8
        ),
        onStartStudy: {},
        onImportNotes: {},
        onInviteGroup: {},
        onBrowseTemplates: {}
    )
}

#Preview("Full Access — Owner") {
    BereanAgentSharedWorkspacesView(
        workspace: BASWorkspace(
            id: "ws-3",
            name: "Sermon Prep",
            role: .owner,
            tab: .sharedWithYou,
            isPrivate: true,
            createdBy: "me@church.org",
            memberCount: 3
        ),
        onStartStudy: {},
        onImportNotes: {},
        onInviteGroup: {},
        onBrowseTemplates: {}
    )
}
#endif
