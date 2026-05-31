// VoiceNavigationView.swift
// AMENAPP — Accessibility Intelligence Layer

import SwiftUI

struct VoiceNavigationView: View {

    let onDismiss: () -> Void

    @StateObject private var service = VoiceNavigationService.shared
    @State private var queryText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            Divider().opacity(0.4)
            contentArea
            suggestionsRow
            inputRow
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice Navigation")
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenPurple)
                .accessibilityHidden(true)

            Text("Voice Navigation")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(6)
                    .background(Circle().fill(AmenTheme.Colors.backgroundSecondary))
            }
            .accessibilityLabel("Close Voice Navigation")
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if service.isProcessing {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(AmenTheme.Colors.amenPurple)
                Text("Thinking…")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
        } else if !service.currentNarration.isEmpty {
            Text(service.currentNarration)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(service.currentNarration)
        }
    }

    @ViewBuilder
    private var suggestionsRow: some View {
        if !service.suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(service.suggestions.prefix(3), id: \.self) { suggestion in
                        Button {
                            Task { await service.askQuestion(suggestion) }
                        } label: {
                            Text(suggestion)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(AmenTheme.Colors.amenPurple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(AmenTheme.Colors.amenPurple.opacity(0.12))
                                )
                        }
                        .accessibilityLabel(suggestion)
                        .accessibilityHint("Ask about \(suggestion)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Ask anything about this screen…", text: $queryText)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .tint(AmenTheme.Colors.amenPurple)
                .submitLabel(.send)
                .onSubmit { submitQuery() }
                .accessibilityLabel("Ask a question about this screen")

            Button {
                submitQuery()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AmenTheme.Colors.textSecondary
                            : AmenTheme.Colors.amenPurple
                    )
            }
            .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send question")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.backgroundSecondary)
        )
    }

    private func submitQuery() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let captured = trimmed
        queryText = ""
        Task { await service.askQuestion(captured) }
    }
}
