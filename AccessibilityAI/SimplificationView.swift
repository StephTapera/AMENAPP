// SimplificationView.swift
// AMEN Universal Accessibility Engine — A5 Comprehension & Simplification UI

import SwiftUI

// MARK: - SimplifyButton

/// Compact inline button that triggers simplification of nearby text content.
/// Only visible when the a11ySimplify feature flag is enabled.
struct SimplifyButton: View {
    let text: String
    let level: ReadingLevel
    var struggleTerms: [String] = []

    @State private var isLoading = false
    @State private var result: SimplificationResult?
    @State private var showSimplified = false
    @State private var errorMessage: String?

    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared

    var body: some View {
        if flags.a11ySimplifyEnabled {
            VStack(alignment: .leading, spacing: 8) {
                // Toggle button
                Button {
                    Task { await handleTap() }
                } label: {
                    Label("Simplify", systemImage: "textformat.size")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .overlay {
                            if isLoading {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                ProgressView()
                                    .scaleEffect(0.65)
                            }
                        }
                }
                .disabled(isLoading)
                .accessibilityLabel(showSimplified ? "Show original text" : "Simplify text")
                .accessibilityHint("Rewrites content at an easier reading level")

                // Error banner
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                // Simplified content
                if showSimplified, let result {
                    SimplifiedTextView(result: result) {
                        withAnimation { showSimplified = false }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func handleTap() async {
        guard !isLoading else { return }

        // If we already have a result, just toggle visibility
        if result != nil {
            withAnimation { showSimplified.toggle() }
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let simplified = try await SimplificationService.shared.simplify(
                text: text,
                to: level,
                struggleTerms: struggleTerms
            )
            result = simplified
            withAnimation { showSimplified = true }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - SimplifiedTextView

/// Displays a `SimplificationResult` with AI badge, reading level pill,
/// glossary disclosure group, and the ability to reveal the original text.
struct SimplifiedTextView: View {
    let result: SimplificationResult
    var onDismiss: (() -> Void)?

    @State private var glossaryExpanded = false
    @State private var originalExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // AI Assisted badge
            AIAssistedBadge()

            // Reading level pill
            HStack(spacing: 6) {
                Text(readingLevelLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.amenPurple.opacity(0.8), in: Capsule())

                Spacer()

                if let onDismiss {
                    Button("Done", action: onDismiss)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Simplified text
            Text(result.simplifiedText)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Simplified text: \(result.simplifiedText)")

            // Glossary
            if !result.glossary.isEmpty {
                DisclosureGroup(
                    isExpanded: $glossaryExpanded,
                    content: {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(result.glossary, id: \.term) { entry in
                                HStack(alignment: .top, spacing: 4) {
                                    Text(entry.term)
                                        .font(.caption.weight(.semibold))
                                    Text("—")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(entry.simplifiedDefinition)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    },
                    label: {
                        Text("Glossary (\(result.glossary.count) terms)")
                            .font(.subheadline.weight(.medium))
                    }
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: glossaryExpanded)
            }

            // Original text collapse/expand
            DisclosureGroup(
                isExpanded: $originalExpanded,
                content: {
                    Text(result.originalText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .accessibilityLabel("Original text: \(result.originalText)")
                },
                label: {
                    Text("Show original")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: originalExpanded)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var readingLevelLabel: String {
        switch result.targetLevel {
        case .elementary:   return "Elementary"
        case .middleSchool: return "Middle School"
        case .plain:        return "Plain Language"
        case .standard:     return "Standard"
        case .academic:     return "Academic"
        case .esl:          return "ESL Friendly"
        }
    }
}

// MARK: - AIAssistedBadge (shared)

struct AIAssistedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle")
                .font(.caption2.weight(.semibold))
            Text("AI Assisted")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.amenPurple, in: Capsule())
        .accessibilityLabel("AI Assisted content")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Color Extension

private extension Color {
    static let amenPurple = Color("amenPurple")
}
