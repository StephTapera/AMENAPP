//
//  ScriptureInsightView.swift
//  AMENAPP
//
//  The Living Scripture Graph view — displays the full hydrated payload
//  for a scripture passage: text, word studies, cross-references,
//  Christ connection, and immersion mode (observation/interpretation/reflection).
//
//  Gated behind `livingScriptureGraphEnabled`.
//

import SwiftUI

struct ScriptureInsightView: View {
    let reference: String
    @StateObject private var viewModel = ScriptureInsightViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    scriptureLoadingView
                } else if let payload = viewModel.payload {
                    scriptureContentView(payload: payload)
                } else if let error = viewModel.errorMessage {
                    scriptureErrorView(message: error)
                }
            }
            .navigationTitle(reference)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await viewModel.loadPassage(reference: reference) }
    }

    // MARK: - Loading

    private var scriptureLoadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.3)

            Text("Building scripture insight\nfor \(reference)…")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func scriptureErrorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Couldn't load insight")
                .font(AMENFont.semiBold(17))

            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task { await viewModel.loadPassage(reference: reference) }
            }
            .font(AMENFont.semiBold(15))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private func scriptureContentView(payload: ScripturePassagePayload) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {

                // Passage text
                if !payload.text.isEmpty {
                    passageTextSection(text: payload.text, reference: reference)
                }

                // Themes
                if !payload.themes.isEmpty {
                    themeChipsSection(themes: payload.themes)
                }

                // Immersion mode (observation / interpretation / reflection)
                if let context = payload.sceneContext,
                   let structure = context.studyStructure {
                    immersionSection(structure: structure, sceneContext: context)
                }

                // Christ connection
                if let christConnection = payload.christConnection,
                   christConnection.confidence >= 0.6 {
                    christConnectionSection(connection: christConnection)
                }

                // Word study
                if !payload.wordInsights.isEmpty {
                    wordStudySection(words: payload.wordInsights)
                }

                // Cross references
                if !payload.crossReferences.isEmpty {
                    crossReferencesSection(refs: payload.crossReferences)
                }

                // Application paths
                if !payload.applicationPaths.isEmpty {
                    applicationSection(paths: payload.applicationPaths)
                }

            }
            .padding(16)
        }
    }

    // MARK: - Sections

    private func passageTextSection(text: String, reference: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Scripture", icon: "book.fill", color: Color(red: 0.18, green: 0.44, blue: 0.80))

            Text(text)
                .font(AMENFont.regular(16))
                .foregroundStyle(.primary)
                .lineSpacing(4)

            Text(reference)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.18, green: 0.44, blue: 0.80).opacity(0.06))
        )
    }

    private func themeChipsSection(themes: [ScriptureTheme]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Themes", icon: "tag.fill", color: .secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(themes) { theme in
                        Text(theme.name)
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func immersionSection(
        structure: ImmersionStudyStructure,
        sceneContext: ScriptureSceneContext
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Immersion Study", icon: "magnifyingglass", color: Color(red: 0.70, green: 0.45, blue: 0.20))

            // Historical setting
            if !sceneContext.historicalSetting.isEmpty {
                immersionBlock(
                    label: "Context",
                    text: sceneContext.historicalSetting,
                    color: Color(red: 0.70, green: 0.45, blue: 0.20)
                )
            }

            immersionBlock(
                label: "Observation",
                text: structure.observation,
                color: Color(red: 0.18, green: 0.44, blue: 0.80)
            )
            immersionBlock(
                label: "Interpretation",
                text: structure.interpretation,
                color: Color(red: 0.52, green: 0.26, blue: 0.73)
            )
            immersionBlock(
                label: "Reflection",
                text: structure.reflection,
                color: Color(red: 0.85, green: 0.30, blue: 0.35)
            )

            if structure.hasInterpretiveDebate, let note = structure.interpretiveDebateNote {
                Text("Note: \(note)")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.yellow.opacity(0.08))
                    )
            }
        }
    }

    private func immersionBlock(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(AMENFont.semiBold(10))
                .foregroundStyle(color)
                .kerning(0.8)

            Text(text)
                .font(AMENFont.regular(14))
                .foregroundStyle(.primary)
                .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.06))
        )
    }

    private func christConnectionSection(connection: ChristConnectionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Christ Connection", icon: "cross.fill", color: Color(red: 0.85, green: 0.60, blue: 0.15))

            Text(connection.connectionStatement)
                .font(AMENFont.regular(14))
                .foregroundStyle(.primary)
                .lineSpacing(3)

            if let nt = connection.ntFulfillmentReference {
                Label(nt.displayString, systemImage: "arrow.right")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(Color(red: 0.85, green: 0.60, blue: 0.15))
            }

            Text(String(format: "Confidence: %.0f%%", connection.confidence * 100))
                .font(AMENFont.regular(11))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.85, green: 0.60, blue: 0.15).opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(red: 0.85, green: 0.60, blue: 0.15).opacity(0.22), lineWidth: 0.5)
        )
    }

    private func wordStudySection(words: [WordStudyItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Word Study", icon: "textformat.abc", color: Color(red: 0.52, green: 0.26, blue: 0.73))

            ForEach(words) { word in
                WordStudyRow(word: word)
            }
        }
    }

    private func crossReferencesSection(refs: [ScriptureCrossRef]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Cross References", icon: "arrow.left.arrow.right", color: Color(red: 0.18, green: 0.44, blue: 0.80))

            ForEach(refs) { ref in
                HStack(alignment: .top, spacing: 10) {
                    Text(ref.targetReference.displayString)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(Color(red: 0.18, green: 0.44, blue: 0.80))
                        .frame(minWidth: 100, alignment: .leading)

                    Text(ref.targetText)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)

                if ref.id != refs.last?.id {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func applicationSection(paths: [ApplicationPath]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Application", icon: "arrow.right.circle.fill", color: Color(red: 0.22, green: 0.62, blue: 0.28))

            ForEach(paths) { path in
                Text("• \(path.prompt)")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.22, green: 0.62, blue: 0.28).opacity(0.06))
        )
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(AMENFont.semiBold(13))
            .foregroundStyle(color)
    }
}

// MARK: - Word Study Row

private struct WordStudyRow: View {
    let word: WordStudyItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(word.surfaceWord)
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.primary)
                        Text(word.originalWord)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 0.52, green: 0.26, blue: 0.73))
                        if let strongs = word.strongsNumber {
                            Text(strongs)
                                .font(AMENFont.regular(11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(word.transliteration)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                Text(word.definition)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)

                if let note = word.devotionalNote {
                    Text(note)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.52, green: 0.26, blue: 0.73).opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
private final class ScriptureInsightViewModel: ObservableObject {
    @Published var payload: ScripturePassagePayload? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    func loadPassage(reference: String, translation: String = "ESV") async {
        guard AMENFeatureFlags.shared.livingScriptureGraphEnabled else {
            errorMessage = "Scripture insights are not available yet."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            payload = try await BereanAPIClient.shared.studyPassage(
                reference: reference,
                translation: translation,
                includeWordStudy: true,
                includeChristConnection: true,
                includeImmersionMode: true
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
