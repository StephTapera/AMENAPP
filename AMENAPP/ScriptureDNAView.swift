//
//  ScriptureDNAView.swift
//  AMENAPP
//
//  Scripture DNA expander — cross-refs, original language words, and themes.
//

import SwiftUI

struct ScriptureDNAView: View {
    @ObservedObject var viewModel: ScriptureDNAViewModel
    @Binding var reference: String

    @State private var selectedCrossRef: CrossRef? = nil
    @State private var appearScale: CGFloat = 0.95
    @State private var appearOpacity: Double = 0

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.cnGold.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    var body: some View {
        bodyContent
    }

    @ViewBuilder
    private var bodyContent: some View {
        if reference.count > 4 {
            VStack(alignment: .leading, spacing: 0) {
                // Collapsed header — always visible
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7))) {
                        viewModel.isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("📖 \(reference.isEmpty ? "Scripture" : reference)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.85))
                        Text("· Tap to \(viewModel.isExpanded ? "collapse" : "expand")")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.35))
                        Spacer()
                        Image(systemName: viewModel.isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)

                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.cnGold)
                            .scaleEffect(0.8)
                        Text("Looking up \(reference)…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }

                if let result = viewModel.result, viewModel.isExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        Divider().background(Color.white.opacity(0.08))

                        // Verse text
                        Text(result.verseText)
                            .font(.systemScaled(14))
                            .italic()
                            .foregroundColor(.white.opacity(0.80))
                            .padding(.horizontal, 16)

                        // Cross references
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("CROSS REFERENCES")
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(result.crossReferences) { xref in
                                        Button {
                                            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                                                selectedCrossRef = selectedCrossRef?.id == xref.id ? nil : xref
                                            }
                                        } label: {
                                            Text(xref.reference)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.cnGold)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                                                        .strokeBorder(Color.cnGold.opacity(selectedCrossRef?.id == xref.id ? 0.8 : 0.4), lineWidth: 1)
                                                        .background(Capsule().fill(Color.cnGold.opacity(selectedCrossRef?.id == xref.id ? 0.15 : 0.06)))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            if let selected = selectedCrossRef {
                                Text(selected.snippet)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.65))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.cnGold.opacity(0.08))
                                            .padding(.horizontal, 12)
                                    )
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }

                        // Original language words
                        if !result.originalLanguageWords.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("ORIGINAL LANGUAGE")
                                    .padding(.horizontal, 16)

                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    spacing: 8
                                ) {
                                    ForEach(result.originalLanguageWords) { word in
                                        OriginalWordCard(word: word)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Key themes
                        if !result.keyThemes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("THEMES")
                                    .padding(.horizontal, 16)

                                AMENFlowLayout(spacing: 6) {
                                    ForEach(result.keyThemes, id: \.self) { theme in
                                        Text(theme)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white.opacity(0.7))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                Capsule()
                                                    .fill(Color.white.opacity(0.08))
                                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                                            )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Word map button
                        Button {
                            viewModel.showWordMap = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.hexagongrid.fill")
                                    .font(.caption)
                                Text("Word Map")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.amenBlue)
                        }
                        .buttonStyle(GlassPillButtonStyle())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                    .padding(.bottom, 16)
                    .scaleEffect(appearScale)
                    .opacity(appearOpacity)
                    .onAppear {
                        withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7))) {
                            appearScale = 1.0
                            appearOpacity = 1.0
                        }
                    }
                }
            }
            .background(cardBackground)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.isExpanded)
            .onChange(of: reference) { _, newValue in
                viewModel.lookupScripture(newValue)
            }
            .onAppear {
                if reference.count > 4 {
                    viewModel.lookupScripture(reference)
                }
            }
            .sheet(isPresented: $viewModel.showWordMap) {
                WordMapPlaceholderSheet(reference: reference, result: viewModel.result)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .tracking(2)
            .foregroundColor(.white.opacity(0.4))
    }
}

// MARK: - OriginalWordCard

private struct OriginalWordCard: View {
    let word: OriginalWord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(word.original)
                .font(.systemScaled(15, weight: .semibold))
                .foregroundColor(.cnGold)
            Text(word.english)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.7))
            Text(word.language)
                .font(.caption2)
                .foregroundColor(.amenPurple.opacity(0.9))
            Text(word.definition)
                .font(.systemScaled(10))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        )
    }
}

// MARK: - Word Map Placeholder Sheet

private struct WordMapPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reference: String
    let result: ScriptureDNAResult?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "050508").ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.systemScaled(60))
                        .foregroundStyle(
                            LinearGradient(colors: [.amenPurple, .amenBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )

                    Text("Word Map")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Visual semantic map for \(reference) — concept clustering coming soon.")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 32)

                    if let result {
                        AMENFlowLayout(spacing: 8) {
                            ForEach(result.keyThemes, id: \.self) { theme in
                                Text(theme)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.cnGold)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.cnGold.opacity(0.15)))
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                }
            }
            .navigationTitle("Word Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cnGold)
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
    }
}
