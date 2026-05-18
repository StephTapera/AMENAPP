//
//  SelahScriptureAIResultViews.swift
//  AMENAPP
//
//  User-facing presentation for the three Selah AI surfaces (Berean Context
//  Mode, Reflection Rewriting, Scripture Companion). EVERY response is
//  shown with a clearly visible "AI-generated" badge — this is the host-side
//  requirement to keep us aligned with Apple's AI transparency guidance.
//
//  Nothing here invents content; all three views render real
//  `SelahScriptureAIResult` outputs that come back from `ClaudeService`
//  via the services in `SelahScriptureAIServices.swift`.
//

import SwiftUI

// MARK: - Transparency Badge

/// Always-visible badge that labels content as AI generated. Use this
/// whenever you display a `SelahScriptureAIResult`.
struct SelahAIGeneratedBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text("AI Generated")
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            Capsule().strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI generated content")
    }
}

// MARK: - Shared Result Body

private struct SelahAIResultBody: View {
    let result: SelahScriptureAIResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Visible disclosure line
            HStack(spacing: 8) {
                SelahAIGeneratedBadge()
                Spacer(minLength: 0)
                Text(result.generatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Text(result.content)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !result.citations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CITATIONS")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    ForEach(result.citations, id: \.self) { ref in
                        HStack(spacing: 4) {
                            Image(systemName: "book.fill").font(.system(size: 9))
                            Text(ref).font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Text("AI can make mistakes. Verify against scripture.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Berean Context Sheet

struct SelahBereanContextSheet: View {
    let reference: SelahScriptureReference
    let translationAbbreviation: String
    let verseText: String?

    @Environment(\.dismiss) private var dismiss
    @State private var result: SelahScriptureAIResult?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if isLoading {
                        loadingState
                    } else if let result {
                        SelahAIResultBody(result: result)
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else {
                        idleState
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Deeper Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { await runIfNeeded() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reference.displayString)
                .font(.system(size: 22, weight: .semibold, design: .serif))
            Text(translationAbbreviation)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var idleState: some View {
        Button {
            Task { await runIfNeeded(force: true) }
        } label: {
            Text("Generate deeper study")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Thinking…").foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 14)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't generate")
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await runIfNeeded(force: true) }
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func runIfNeeded(force: Bool = false) async {
        guard !isLoading else { return }
        if result != nil && !force { return }
        isLoading = true
        errorMessage = nil
        do {
            let r = try await SelahBereanContextService.shared.deeperStudy(
                for: reference,
                translationAbbreviation: translationAbbreviation,
                verseText: verseText
            )
            result = r
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Reflection Rewriting Sheet

struct SelahReflectionRewriteSheet: View {
    @State private var originalText: String = ""
    @State private var mode: SelahReflectionRewriteMode = .simplify
    @State private var result: SelahScriptureAIResult?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    modePicker
                    inputField
                    if isLoading {
                        HStack { ProgressView(); Text("Rewriting…").foregroundStyle(.secondary); Spacer() }
                            .padding(.vertical, 10)
                    }
                    if let result {
                        Divider().padding(.vertical, 2)
                        Text("REWRITE")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        SelahAIResultBody(result: result)
                        HStack(spacing: 10) {
                            Button {
                                UIPasteboard.general.string = result.content
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Spacer()
                            Button("Revert to original") {
                                self.result = nil
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Rewrite Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rewrite") { Task { await run() } }
                        .disabled(originalText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
        }
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SelahReflectionRewriteMode.allCases) { m in
                    SelahTopicChip(label: m.displayName, isSelected: mode == m) {
                        mode = m
                    }
                }
            }
        }
    }

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your reflection")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            TextEditor(text: $originalText)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func run() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        result = nil
        do {
            let r = try await SelahReflectionRewritingService.shared.rewrite(originalText, mode: mode)
            result = r
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Scripture Companion Sheet

struct SelahScriptureCompanionSheet: View {
    let reference: SelahScriptureReference
    let translationAbbreviation: String
    let visibleVerses: [String]

    @State private var question: String = ""
    @State private var result: SelahScriptureAIResult?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    promptField
                    if isLoading {
                        HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary); Spacer() }
                            .padding(.vertical, 10)
                    }
                    if let result {
                        Divider().padding(.vertical, 2)
                        SelahAIResultBody(result: result)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text("The companion stays close to the passage. Doctrine specific to your tradition should be confirmed with your pastor.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Scripture Companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ask") { Task { await run() } }
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reference.displayString)
                .font(.system(size: 20, weight: .semibold, design: .serif))
            Text(translationAbbreviation)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your question")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            TextField("What does this passage mean in context?", text: $question, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func run() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        result = nil
        do {
            let r = try await SelahScriptureCompanionService.shared.ask(
                question,
                about: reference,
                translationAbbreviation: translationAbbreviation,
                visibleVerses: visibleVerses
            )
            result = r
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#if DEBUG
#Preview("AI Generated Badge") {
    VStack(spacing: 16) {
        SelahAIGeneratedBadge()
        SelahAIGeneratedBadge(compact: true)
    }
    .padding(40)
    .background(Color(.systemGroupedBackground))
}
#endif
