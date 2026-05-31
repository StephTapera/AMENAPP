// AmenTranslationComparisonCard.swift
// AMENAPP
// Reusable card that displays a multi-translation Bible verse comparison
// with AI commentary. Accepts a scripture reference string and fetches
// on first appear, with cache handled by BereanTranslationComparisonService.

import SwiftUI

struct AmenTranslationComparisonCard: View {
    let reference: String
    var translationOrder: [String] = ["ESV", "NIV", "KJV", "NLT"]
    var onDismiss: (() -> Void)? = nil

    @ObservedObject private var service = BereanTranslationComparisonService.shared
    @State private var comparison: TranslationComparison? = nil
    @State private var loadError: String? = nil
    @State private var selectedTranslation: String? = nil
    @State private var showCommentary = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            cardHeader

            if service.isLoading && comparison == nil {
                loadingState
            } else if let err = loadError {
                errorState(err)
            } else if let comp = comparison {
                translationContent(comp)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .task(id: reference) {
            await load()
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.pages")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("Translation Comparison")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reference)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Comparing translations…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Error

    private func errorState(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") {
                Task { await load() }
            }
            .font(.caption)
            .tint(.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Translation Content

    private func translationContent(_ comp: TranslationComparison) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            // Translation pills selector
            translationPills(comp)

            // Selected (or first) verse text
            verseText(comp)

            // Commentary toggle
            if !comp.commentary.isEmpty {
                commentarySection(comp)
            }
        }
    }

    private func translationPills(_ comp: TranslationComparison) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(orderedTranslations(comp), id: \.self) { key in
                    let isSelected = (selectedTranslation ?? orderedTranslations(comp).first) == key
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTranslation = key
                        }
                    } label: {
                        Text(key)
                            .font(.caption)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.secondary.opacity(0.08),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func verseText(_ comp: TranslationComparison) -> some View {
        let key = selectedTranslation ?? orderedTranslations(comp).first ?? ""
        let text = comp.translations[key] ?? ""
        return Group {
            if text.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: selectedTranslation)

                    Text("— \(reference) (\(key))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private func commentarySection(_ comp: TranslationComparison) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCommentary.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("Berean Commentary")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showCommentary ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if showCommentary {
                Text(comp.commentary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Helpers

    private func orderedTranslations(_ comp: TranslationComparison) -> [String] {
        let available = translationOrder.filter { comp.translations[$0] != nil }
        let rest = comp.translations.keys.filter { !available.contains($0) }.sorted()
        return available + rest
    }

    private func load() async {
        loadError = nil
        do {
            comparison = try await BereanTranslationComparisonService.shared.compare(
                reference: reference,
                translations: translationOrder
            )
        } catch {
            loadError = "Could not load comparison. Tap to retry."
        }
    }
}

// MARK: - Compact inline variant for chat bubbles

struct AmenTranslationComparisonInline: View {
    let reference: String

    @State private var showCard = false

    var body: some View {
        Button {
            showCard = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                    .font(.caption2)
                Text("Compare translations")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCard) {
            NavigationStack {
                ScrollView {
                    AmenTranslationComparisonCard(reference: reference) {
                        showCard = false
                    }
                    .padding()
                }
                .navigationTitle("Translation Comparison")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showCard = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
