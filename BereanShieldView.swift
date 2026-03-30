// BereanShieldView.swift
// AMENAPP
//
// Berean Shield — full-screen claim verification UI.
// Design language: AMEN Liquid Glass (dark glass cards, OpenSans fonts, coral/red accents).

import SwiftUI

// MARK: - BereanShieldView

struct BereanShieldView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = BereanShieldService.shared

    /// Called when user taps "Ask Berean more" — bridges back to the Berean chat.
    var onAskBerean: ((String) -> Void)? = nil

    // MARK: State
    @State private var claimText: String = ""
    @State private var analysis: ShieldAnalysis? = nil
    @State private var errorMessage: String? = nil
    @State private var showResults = false
    @FocusState private var inputFocused: Bool

    // MARK: Design tokens
    private let coralRed = Color(red: 0.88, green: 0.28, blue: 0.25)
    private let cardBackground = Color(white: 0.10)
    private let cardStroke = Color(white: 1, opacity: 0.08)
    private let labelPrimary = Color.white
    private let labelSecondary = Color(white: 0.65)
    private let pageBackground = Color(red: 0.06, green: 0.06, blue: 0.08)

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        inputSection
                            .padding(.top, 8)

                        if let errorMessage {
                            errorBanner(errorMessage)
                        }

                        if let analysis, showResults {
                            dimensionsSection(analysis)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))

                            verdictBanner(analysis)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))

                            askBereanButton(for: analysis.claim)
                                .transition(.opacity)
                        }

                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(coralRed)
                        Text("Berean Shield")
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundColor(labelPrimary)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(labelSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(white: 1, opacity: 0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a claim, headline, or quote to verify it across five truth dimensions.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(labelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Text area
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(inputFocused ? coralRed.opacity(0.5) : cardStroke, lineWidth: 1)
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: inputFocused)

                if claimText.isEmpty {
                    Text("Paste a claim, headline, or quote…")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(Color(white: 0.38))
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $claimText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(labelPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($inputFocused)
                    .frame(minHeight: 120, maxHeight: 220)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
            }
            .frame(minHeight: 120)

            // Character hint + Analyze button
            HStack {
                Text("\(claimText.count) chars")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(Color(white: 0.38))

                Spacer()

                analyzeButton
            }
        }
        .padding(18)
        .background(glassCard())
    }

    private var analyzeButton: some View {
        let isEmpty = claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button(action: runAnalysis) {
            HStack(spacing: 8) {
                if service.isAnalyzing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(service.isAnalyzing ? "Analyzing…" : "Analyze")
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isEmpty ? Color(white: 0.25) : coralRed)
            )
        }
        .buttonStyle(.plain)
        .disabled(isEmpty || service.isAnalyzing)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isEmpty)
    }

    // MARK: - Dimensions Section

    private func dimensionsSection(_ analysis: ShieldAnalysis) -> some View {
        VStack(spacing: 12) {
            Text("Analysis")
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundColor(Color(white: 0.45))
                .kerning(1.0)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

            ForEach(Array(analysis.dimensions.enumerated()), id: \.element.id) { idx, dim in
                DimensionCard(dimension: dim, index: idx)
            }
        }
    }

    // MARK: - Verdict Banner

    private func verdictBanner(_ analysis: ShieldAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: analysis.verdict.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(analysis.verdict.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verdict")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundColor(analysis.verdict.color.opacity(0.8))
                        .kerning(0.8)
                        .textCase(.uppercase)
                    Text(analysis.verdict.displayLabel)
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundColor(analysis.verdict.color)
                }

                Spacer()

                // Confidence pill
                Text("\(Int(analysis.confidence * 100))% confidence")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundColor(analysis.verdict.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(analysis.verdict.color.opacity(0.15))
                    )
            }

            Divider().overlay(analysis.verdict.color.opacity(0.2))

            Text(analysis.verdictExplanation)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(labelPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(analysis.verdict.color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(analysis.verdict.color.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - Ask Berean Button

    private func askBereanButton(for claim: String) -> some View {
        Button(action: {
            dismiss()
            onAskBerean?(claim)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "message.fill")
                    .font(.system(size: 14, weight: .medium))
                Text("Ask Berean more about this")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(coralRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(coralRed.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(coralRed.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.20))
            Text(message)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(labelPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.95, green: 0.60, blue: 0.20).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(red: 0.95, green: 0.60, blue: 0.20).opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func glassCard() -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1)
            )
    }

    private func runAnalysis() {
        guard !claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil
        showResults = false
        inputFocused = false

        Task {
            do {
                let result = try await BereanShieldService.shared.analyze(claim: claimText)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.80)) {
                    analysis = result
                    showResults = true
                }
            } catch {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - DimensionCard

private struct DimensionCard: View {
    let dimension: ShieldDimension
    let index: Int

    private let labelPrimary   = Color.white
    private let labelSecondary = Color(white: 0.65)
    private let cardBackground = Color(white: 0.10)
    private let cardStroke     = Color(white: 1, opacity: 0.08)
    private let accentColors: [Color] = [
        Color(red: 0.40, green: 0.65, blue: 0.98),
        Color(red: 0.56, green: 0.82, blue: 0.70),
        Color(red: 0.98, green: 0.72, blue: 0.35),
        Color(red: 0.85, green: 0.60, blue: 0.98),
    ]

    @State private var isExpanded = true

    var accent: Color { accentColors[index % accentColors.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.15))
                            .frame(width: 34, height: 34)
                        Image(systemName: dimension.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(accent)
                    }

                    Text(dimension.title.uppercased())
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundColor(accent)
                        .kerning(0.8)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.40))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if isExpanded {
                Divider()
                    .overlay(cardStroke)
                    .padding(.horizontal, 14)

                Text(dimension.content.isEmpty ? "No data available." : dimension.content)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundColor(dimension.content.isEmpty ? Color(white: 0.40) : labelPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(cardStroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Berean Shield") {
    BereanShieldView(onAskBerean: { _ in })
        .preferredColorScheme(.dark)
}
#endif
