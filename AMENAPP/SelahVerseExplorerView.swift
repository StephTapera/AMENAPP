//
//  SelahVerseExplorerView.swift
//  AMENAPP
//
//  Deep YouVersion integration — lets users expand a verse reference into
//  multiple translations, see cross-references, and take action.
//

import SwiftUI

struct SelahVerseExplorerView: View {
    let reference: String
    var onAskFollowUp: ((String) -> Void)? = nil

    @ObservedObject private var selahService = SelahService.shared
    @State private var expansion: VerseExpansion?
    @State private var crossRefs: [CrossReference] = []
    @State private var selectedVersion: ScripturePassage.BibleVersion = .esv
    @State private var isLoadingExpansion = false
    @State private var isLoadingCrossRefs = false
    @State private var showAllTranslations = false

    private let versions: [ScripturePassage.BibleVersion] = [.esv, .niv, .kjv, .nkjv, .nlt, .nasb]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Reference header
                    referenceHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Version switcher
                    versionSwitcher
                        .padding(.horizontal, 20)

                    // Primary verse text
                    primaryVerseSection
                        .padding(.horizontal, 20)

                    // Translation comparison
                    if showAllTranslations, let exp = expansion, exp.passages.count > 1 {
                        translationComparison(passages: exp.passages)
                            .padding(.horizontal, 20)
                    }

                    // Cross references
                    crossReferencesSection
                        .padding(.horizontal, 20)

                    // Actions
                    actionsSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle(reference)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { loadData() }
    }

    // MARK: - Reference Header

    private var referenceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VERSE EXPLORER")
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            Text(reference)
                .font(.systemScaled(24, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Version Switcher

    private var versionSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(versions, id: \.rawValue) { version in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.8))) {
                            selectedVersion = version
                        }
                    } label: {
                        Text(version.rawValue)
                            .font(.systemScaled(12, weight: selectedVersion == version ? .bold : .medium))
                            .foregroundStyle(selectedVersion == version ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if selectedVersion == version {
                                    Capsule()
                                        .fill(.regularMaterial)
                                        .overlay(
                                            Capsule().strokeBorder(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.70), Color.white.opacity(0.15)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                        )
                                        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Primary Verse

    private var primaryVerseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoadingExpansion {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if let exp = expansion,
                      let passage = exp.passages.first(where: { $0.version == selectedVersion }) ?? exp.passages.first {
                Text(passage.text)
                    .font(.systemScaled(17, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack {
                    Text("— \(passage.reference)")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation { showAllTranslations.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "translate")
                                .font(.systemScaled(11))
                            Text(showAllTranslations ? "Hide Translations" : "Compare Translations")
                                .font(.systemScaled(11, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Unable to load verse text.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
        )
    }

    // MARK: - Translation Comparison

    private func translationComparison(passages: [ScripturePassage]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRANSLATIONS")
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            ForEach(passages, id: \.id) { passage in
                VStack(alignment: .leading, spacing: 4) {
                    Text(passage.version.rawValue)
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundStyle(Color.accentColor)

                    Text(passage.text)
                        .font(.systemScaled(14))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Cross References

    private var crossReferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CROSS REFERENCES")
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                if isLoadingCrossRefs {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            if crossRefs.isEmpty && !isLoadingCrossRefs {
                Text("No cross references loaded.")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(crossRefs) { ref in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "link")
                            .font(.systemScaled(11))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(ref.targetRef)
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(ref.relationship.capitalized)
                                .font(.systemScaled(10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05), in: Capsule())

                            if let snippet = ref.snippet, !snippet.isEmpty {
                                Text(snippet)
                                    .font(.systemScaled(12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.02))
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = expansion?.passages.first?.text ?? reference
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Verse")
                }
                .font(.systemScaled(14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(Color.accentColor)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                onAskFollowUp?("Tell me more about \(reference)")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                    Text("Ask Selah About This")
                }
                .font(.systemScaled(14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoadingExpansion = true
        isLoadingCrossRefs = true

        Task {
            do {
                expansion = try await selahService.expandVerse(reference: reference)
            } catch {}
            isLoadingExpansion = false
        }

        Task {
            crossRefs = await selahService.fetchCrossReferences(for: reference)
            isLoadingCrossRefs = false
        }
    }
}
