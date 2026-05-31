// AuthenticityScoreView.swift
// AMEN Trust Layer — T2 Authenticity Scoring
// Compact pill and full detail sheet for surfacing authenticity signals.
// Flag-gated behind TrustAccessibilityFeatureFlags.authenticityScoresEnabled.

import SwiftUI

// MARK: - Score Pill

/// A compact oval badge displaying the composite score (e.g. "85%") with a
/// thin arc ring background. Tapping it presents AuthenticityScoreSheet.
struct AuthenticityScorePill: View {

    let score: AuthenticityScore
    @State private var showSheet = false
    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared

    private var accentColor: Color {
        switch score.composite {
        case 80...: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        if flags.authenticityScoresEnabled {
            Button {
                showSheet = true
            } label: {
                ZStack {
                    // Background ring
                    Circle()
                        .trim(from: 0, to: 1)
                        .stroke(.secondary.opacity(0.25), lineWidth: 2.5)
                        .frame(width: 36, height: 36)

                    // Filled arc proportional to score
                    Circle()
                        .trim(from: 0, to: CGFloat(score.composite) / 100.0)
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                        .animation(.easeOut(duration: 0.4), value: score.composite)

                    Text("\(score.composite)%")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Authenticity score \(score.composite) percent. Tap for details.")
            .sheet(isPresented: $showSheet) {
                AuthenticityScoreSheet(score: score)
            }
        }
    }
}

// MARK: - Score Sheet

/// Full sheet listing the five authenticity signals with pass/fail indicators.
struct AuthenticityScoreSheet: View {

    let score: AuthenticityScore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    scoreRow(
                        symbol: score.originalCapture ? "checkmark.seal.fill" : "xmark.circle.fill",
                        label: "Original Capture",
                        pass: score.originalCapture
                    )
                    scoreRow(
                        symbol: score.provenanceIntact ? "shield.fill" : "xmark.circle.fill",
                        label: "Provenance Intact",
                        pass: score.provenanceIntact
                    )
                    scoreRow(
                        symbol: score.sourceVerified ? "doc.text.magnifyingglass" : "xmark.circle.fill",
                        label: "Source Verified",
                        pass: score.sourceVerified
                    )
                    scoreRow(
                        symbol: score.metadataIntact ? "doc.badge.checkmark" : "xmark.circle.fill",
                        label: "Metadata Intact",
                        pass: score.metadataIntact
                    )
                    scoreRow(
                        symbol: score.editsDisclosed ? "pencil.circle.fill" : "xmark.circle.fill",
                        label: "Edits Disclosed",
                        pass: score.editsDisclosed
                    )
                } header: {
                    compositeBanner
                }

                Section {
                    Text("Score based on content signals only. Engagement is not a factor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .accessibilityHint("This score reflects technical content signals — likes, shares, and views do not influence it.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Authenticity Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Private Views

    private var compositeBanner: some View {
        VStack(spacing: 6) {
            Text("\(score.composite)%")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(bannerAccent)
            Text("Authenticity Score")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
    }

    private var bannerAccent: Color {
        switch score.composite {
        case 80...: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    @ViewBuilder
    private func scoreRow(symbol: String, label: String, pass: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(pass ? Color.green : Color.red)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(label)
                .font(.body)

            Spacer()

            Image(systemName: pass ? "checkmark" : "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pass ? Color.green : Color.red)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(pass ? "passed" : "failed")")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Pill — High Score") {
    let score = AuthenticityScore(
        originalCapture: true,
        provenanceIntact: true,
        sourceVerified: true,
        metadataIntact: true,
        editsDisclosed: false
    )
    AuthenticityScorePill(score: score)
        .padding()
}

#Preview("Sheet — Mixed Score") {
    let score = AuthenticityScore(
        originalCapture: true,
        provenanceIntact: true,
        sourceVerified: false,
        metadataIntact: true,
        editsDisclosed: false
    )
    AuthenticityScoreSheet(score: score)
}
#endif
