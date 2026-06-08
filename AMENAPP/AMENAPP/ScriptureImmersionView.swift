//
//  ScriptureImmersionView.swift
//  AMENAPP
//
//  Scripture Immersion Mode — full inductive study surface.
//  Presents a passage using the classic OIA structure:
//    Observation  → What does this passage say?
//    Interpretation → What did it mean in its original context?
//    Application   → What does it invite for my life today?
//
//  Also surfaces historical/cultural scene context, literary genre,
//  and any known interpretive debates — with appropriate humility markers.
//
//  Gated behind `scriptureImmersionEnabled`.
//
//  Design constraints:
//    - Interpretation must never claim certainty beyond the text
//    - Application is always invitational, never prescriptive
//    - Interpretive debates are surfaced transparently
//    - All content is from the `ScripturePassagePayload` fetched upstream
//

import SwiftUI

// MARK: - Scripture Immersion View

struct ScriptureImmersionView: View {
    let payload: ScripturePassagePayload

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: ImmersionSection = .observation
    @State private var showDebateNote = false
    @Namespace private var sectionNamespace

    enum ImmersionSection: String, CaseIterable {
        case observation    = "Observe"
        case interpretation = "Interpret"
        case application    = "Apply"

        var icon: String {
            switch self {
            case .observation:    return "eye"
            case .interpretation: return "book.pages"
            case .application:    return "heart"
            }
        }

        var description: String {
            switch self {
            case .observation:    return "What does the text say?"
            case .interpretation: return "What did it mean originally?"
            case .application:    return "What does it invite today?"
            }
        }

        var accentColor: Color {
            switch self {
            case .observation:    return .blue
            case .interpretation: return Color(red: 0.52, green: 0.26, blue: 0.73)
            case .application:    return .green
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Passage header
                    passageHeader

                    // OIA section picker
                    sectionPicker
                        .padding(.top, 20)

                    // Scene context strip
                    if let scene = payload.sceneContext {
                        sceneContextStrip(scene: scene)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    // Section content
                    sectionContent
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("Immersion Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Passage Header

    private var passageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(payload.reference.displayString)
                .font(AMENFont.bold(22))
                .foregroundStyle(.primary)

            Text(payload.text)
                .font(.custom("Georgia", size: 16))
                .foregroundStyle(.primary)
                .lineSpacing(6)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.98, green: 0.97, blue: 0.93))
                )

            if let scene = payload.sceneContext, let genre = scene.literaryGenre as String? {
                Text(genre.uppercased())
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ImmersionSection.allCases, id: \.self) { section in
                    ImmersionSectionTab(
                        section: section,
                        isSelected: selectedSection == section,
                        namespace: sectionNamespace
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Scene Context Strip

    private func sceneContextStrip(scene: ScriptureSceneContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Historical Setting", systemImage: "building.columns")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)

            Text(scene.historicalSetting)
                .font(AMENFont.regular(13))
                .foregroundStyle(.primary)
                .lineSpacing(3)

            if let period = scene.datePeriod {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                    Text(period)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
            }

            if let geo = scene.geographicalContext {
                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                    Text(geo)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
            }

            if !scene.culturalNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cultural Notes")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.secondary)
                    ForEach(scene.culturalNotes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(note)
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        if let structure = payload.sceneContext?.studyStructure {
            switch selectedSection {
        case .observation:
            ImmersionCard(
                title: "Observation",
                subtitle: "What does this passage say?",
                content: structure.observation,
                accentColor: ImmersionSection.observation.accentColor
            )

        case .interpretation:
            VStack(alignment: .leading, spacing: 16) {
                ImmersionCard(
                    title: "Interpretation",
                    subtitle: "What did it mean in its original context?",
                    content: structure.interpretation,
                    accentColor: ImmersionSection.interpretation.accentColor
                )

                if structure.hasInterpretiveDebate, let note = structure.interpretiveDebateNote {
                    InterpretiveDebateNote(note: note, isExpanded: $showDebateNote)
                }

                if let author = payload.sceneContext?.authorContext {
                    AuthorContextCard(content: author)
                }
            }

        case .application:
            VStack(alignment: .leading, spacing: 16) {
                ImmersionCard(
                    title: "Application",
                    subtitle: "What does this invite for your life today?",
                    content: structure.reflection,
                    accentColor: ImmersionSection.application.accentColor
                )

                if !payload.applicationPaths.isEmpty {
                    ApplicationPathsSection(paths: payload.applicationPaths)
                }
            }
        }
        } else {
            unavailableCard
        }
    }

    private var unavailableCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.systemScaled(36))
                .foregroundStyle(.secondary)

            Text("Immersion study not available for this passage yet.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Immersion Section Tab

private struct ImmersionSectionTab: View {
    let section: ScriptureImmersionView.ImmersionSection
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.systemScaled(16, weight: isSelected ? .semibold : .regular))

                Text(section.rawValue)
                    .font(AMENFont.semiBold(13))

                Text(section.description)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isSelected ? section.accentColor : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(section.accentColor.opacity(0.1))
                        .matchedGeometryEffect(id: "section_bg", in: namespace)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Immersion Card

private struct ImmersionCard: View {
    let title: String
    let subtitle: String
    let content: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AMENFont.bold(16))
                    .foregroundStyle(accentColor)

                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .overlay(accentColor.opacity(0.3))

            Text(content)
                .font(AMENFont.regular(15))
                .foregroundStyle(.primary)
                .lineSpacing(5)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accentColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Interpretive Debate Note

private struct InterpretiveDebateNote: View {
    let note: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.systemScaled(13))
                        .foregroundStyle(.orange)

                    Text("Interpretive Debate Noted")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.orange)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(note)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.07))
        )
    }
}

// MARK: - Author Context Card

private struct AuthorContextCard: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Author & Audience", systemImage: "person.text.rectangle")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)

            Text(content)
                .font(AMENFont.regular(13))
                .foregroundStyle(.primary)
                .lineSpacing(3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }
}

// MARK: - Application Paths Section

private struct ApplicationPathsSection: View {
    let paths: [ApplicationPath]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reflection Paths")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)

            Text("Choose one that resonates — these are invitations, not requirements.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)

            ForEach(paths) { path in
                ApplicationPathRow(path: path)
            }
        }
    }
}

private struct ApplicationPathRow: View {
    let path: ApplicationPath
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: path.relational ? "person.2" : "person")
                        .font(.systemScaled(14))
                        .foregroundStyle(.green)
                        .frame(width: 20)

                    Text(path.prompt)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)

                    Spacer(minLength: 0)

                    if path.actionStep != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded, let action = path.actionStep {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.4))
                        .frame(width: 3)
                    Text(action)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(.leading, 30)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.05))
        )
    }
}
